import Foundation
import Observation

/// Local-first sync service for Trip records.
/// Tracks dirty/deleted trips locally and pushes/pulls them against Supabase
/// using `SupabaseTripSyncRepository`. Conflict resolution is last-write-wins
/// based on `client_updated_at`/`updated_at`.
@Observable
@MainActor
final class TripSyncService {

    enum Status: Equatable, Sendable {
        case idle
        case syncing
        case success
        case failure(String)
    }

    var syncStatus: Status = .idle
    var lastSyncDate: Date?
    var errorMessage: String?

    private weak var store: MigratedDataStore?
    private weak var auth: NewBackendAuthService?
    private let repository: any TripSyncRepositoryProtocol
    private let metadata: TripSyncMetadata
    private var isConfigured: Bool = false

    init(
        repository: (any TripSyncRepositoryProtocol)? = nil,
        metadata: TripSyncMetadata? = nil
    ) {
        self.repository = repository ?? SupabaseTripSyncRepository()
        self.metadata = metadata ?? TripSyncMetadata()
    }

    // MARK: - Configuration

    func configure(store: MigratedDataStore, auth: NewBackendAuthService) {
        self.store = store
        self.auth = auth
        guard !isConfigured else { return }
        isConfigured = true
        store.onTripChanged = { [weak self] id in
            self?.markTripDirty(id)
        }
        store.onTripDeleted = { [weak self] id in
            self?.markTripDeleted(id)
        }
    }

    // MARK: - Dirty tracking

    func markTripDirty(_ id: UUID) {
        metadata.markDirty(id, at: Date())
    }

    func markTripDeleted(_ id: UUID) {
        metadata.markDeleted(id, at: Date())
    }

    // MARK: - Public sync entry points

    func syncTripsForSelectedVineyard() async {
        guard let store, let auth, auth.isSignedIn,
              let vineyardId = store.selectedVineyardId else { return }
        await sync(vineyardId: vineyardId)
    }

    func sync(vineyardId: UUID) async {
        guard SupabaseClientProvider.shared.isConfigured else {
            errorMessage = "Supabase not configured"
            syncStatus = .failure("Supabase not configured")
            return
        }
        syncStatus = .syncing
        errorMessage = nil
        do {
            try await pushLocalTrips(vineyardId: vineyardId)
            try await pullRemoteTrips(vineyardId: vineyardId)
            metadata.setLastSync(Date(), for: vineyardId)
            lastSyncDate = Date()
            syncStatus = .success
        } catch {
            errorMessage = error.localizedDescription
            syncStatus = .failure(error.localizedDescription)
        }
    }

    // MARK: - Push

    func pushLocalTrips(vineyardId: UUID) async throws {
        guard let store else { return }
        let createdBy = auth?.userId
        let dirty = metadata.pendingUpserts
        if !dirty.isEmpty {
            let byId = Dictionary(uniqueKeysWithValues: store.trips.map { ($0.id, $0) })
            var payloads: [BackendTripUpsert] = []
            var pushedIds: [UUID] = []
            for (tripId, ts) in dirty {
                guard let trip = byId[tripId], trip.vineyardId == vineyardId else { continue }
                payloads.append(BackendTrip.upsert(from: trip, createdBy: createdBy, clientUpdatedAt: ts))
                pushedIds.append(tripId)
            }
            if !payloads.isEmpty {
                try await repository.upsertTrips(payloads)
                metadata.clearDirty(pushedIds)
            }
        }

        let deletes = metadata.pendingDeletes
        var deleteFailures: [String] = []
        for (tripId, _) in deletes {
            do {
                try await repository.softDeleteTrip(id: tripId)
                metadata.clearDeleted([tripId])
            } catch {
                if Self.isMissingRowError(error) {
                    metadata.clearDeleted([tripId])
                    #if DEBUG
                    print("[TripSync] soft delete: remote trip \(tripId) already missing — clearing pending delete")
                    #endif
                } else {
                    #if DEBUG
                    print("[TripSync] soft delete failed for \(tripId): \(error.localizedDescription)")
                    #endif
                    deleteFailures.append(error.localizedDescription)
                    continue
                }
            }
        }
        if !deleteFailures.isEmpty {
            errorMessage = "Some trip deletes failed: \(deleteFailures.first ?? "unknown")"
        }
    }

    private static func isMissingRowError(_ error: Error) -> Bool {
        let message = String(describing: error).lowercased()
        if message.contains("trip not found") { return true }
        if message.contains("not found") { return true }
        if message.contains("pgrst116") { return true }
        if message.contains("no rows") { return true }
        if message.contains("0 rows") { return true }
        return false
    }

    // MARK: - Pull

    func pullRemoteTrips(vineyardId: UUID) async throws {
        guard let store else { return }
        let lastSync = metadata.lastSync(for: vineyardId)
        let remote = try await repository.fetchTrips(vineyardId: vineyardId, since: lastSync)

        // Initial sync: if remote is empty AND we have local trips AND we have
        // never synced before, push them all up.
        if remote.isEmpty, lastSync == nil {
            let localForVineyard = store.trips.filter { $0.vineyardId == vineyardId }
            if !localForVineyard.isEmpty {
                let now = Date()
                let createdBy = auth?.userId
                let payloads = localForVineyard.map {
                    BackendTrip.upsert(from: $0, createdBy: createdBy, clientUpdatedAt: now)
                }
                try await repository.upsertTrips(payloads)
            }
            return
        }

        for backendTrip in remote {
            applyRemote(backendTrip, vineyardId: vineyardId, store: store)
        }
    }

    private func applyRemote(_ backendTrip: BackendTrip, vineyardId: UUID, store: MigratedDataStore) {
        // Soft-deleted remotely.
        if backendTrip.deletedAt != nil {
            store.applyRemoteTripDelete(backendTrip.id)
            metadata.clearDirty([backendTrip.id])
            metadata.clearDeleted([backendTrip.id])
            return
        }

        // Last-write-wins: only apply remote if it's newer than the local pending change.
        if let pendingDirtyAt = metadata.pendingUpserts[backendTrip.id] {
            let remoteAt = backendTrip.clientUpdatedAt ?? backendTrip.updatedAt ?? .distantPast
            if pendingDirtyAt > remoteAt { return }
        }

        let mapped = backendTrip.toTrip()
        store.applyRemoteTripUpsert(mapped)
        metadata.clearDirty([backendTrip.id])
    }
}

// MARK: - Metadata

@MainActor
final class TripSyncMetadata {
    private let persistence: PersistenceStore
    private let key: String = "vinetrack_trip_sync_metadata"
    private var state: State

    nonisolated struct State: Codable, Sendable {
        var lastSyncByVineyard: [UUID: Date] = [:]
        var pendingUpserts: [UUID: Date] = [:]
        var pendingDeletes: [UUID: Date] = [:]
    }

    init(persistence: PersistenceStore = .shared) {
        self.persistence = persistence
        self.state = persistence.load(key: key) ?? State()
    }

    var pendingUpserts: [UUID: Date] { state.pendingUpserts }
    var pendingDeletes: [UUID: Date] { state.pendingDeletes }

    func lastSync(for vineyardId: UUID) -> Date? {
        state.lastSyncByVineyard[vineyardId]
    }

    func setLastSync(_ date: Date, for vineyardId: UUID) {
        state.lastSyncByVineyard[vineyardId] = date
        save()
    }

    func markDirty(_ id: UUID, at date: Date) {
        state.pendingUpserts[id] = date
        save()
    }

    func markDeleted(_ id: UUID, at date: Date) {
        state.pendingUpserts.removeValue(forKey: id)
        state.pendingDeletes[id] = date
        save()
    }

    func clearDirty(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        for id in ids { state.pendingUpserts.removeValue(forKey: id) }
        save()
    }

    func clearDeleted(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        for id in ids { state.pendingDeletes.removeValue(forKey: id) }
        save()
    }

    private func save() {
        persistence.save(state, key: key)
    }
}
