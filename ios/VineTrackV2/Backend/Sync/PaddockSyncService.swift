import Foundation
import Observation

/// Local-first sync service for Paddock records.
/// Tracks dirty/deleted paddocks locally and pushes/pulls them against Supabase
/// using `SupabasePaddockSyncRepository`. Conflict resolution is last-write-wins
/// based on `client_updated_at`/`updated_at`.
@Observable
@MainActor
final class PaddockSyncService {

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
    private let repository: any PaddockSyncRepositoryProtocol
    private let metadata: PaddockSyncMetadata
    private var isConfigured: Bool = false

    init(
        repository: (any PaddockSyncRepositoryProtocol)? = nil,
        metadata: PaddockSyncMetadata? = nil
    ) {
        self.repository = repository ?? SupabasePaddockSyncRepository()
        self.metadata = metadata ?? PaddockSyncMetadata()
    }

    // MARK: - Configuration

    func configure(store: MigratedDataStore, auth: NewBackendAuthService) {
        self.store = store
        self.auth = auth
        guard !isConfigured else { return }
        isConfigured = true
        store.onPaddockChanged = { [weak self] id in
            self?.markPaddockDirty(id)
        }
        store.onPaddockDeleted = { [weak self] id in
            self?.markPaddockDeleted(id)
        }
    }

    // MARK: - Dirty tracking

    func markPaddockDirty(_ id: UUID) {
        metadata.markDirty(id, at: Date())
    }

    func markPaddockDeleted(_ id: UUID) {
        metadata.markDeleted(id, at: Date())
    }

    // MARK: - Public sync entry points

    func syncPaddocksForSelectedVineyard() async {
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
            try await pushLocalPaddocks(vineyardId: vineyardId)
            try await pullRemotePaddocks(vineyardId: vineyardId)
            metadata.setLastSync(Date(), for: vineyardId)
            lastSyncDate = Date()
            syncStatus = .success
        } catch {
            errorMessage = error.localizedDescription
            syncStatus = .failure(error.localizedDescription)
        }
    }

    // MARK: - Push

    func pushLocalPaddocks(vineyardId: UUID) async throws {
        guard let store else { return }
        let createdBy = auth?.userId
        let dirty = metadata.pendingUpserts
        if !dirty.isEmpty {
            let byId = Dictionary(uniqueKeysWithValues: store.paddocks.map { ($0.id, $0) })
            var payloads: [BackendPaddockUpsert] = []
            var pushedIds: [UUID] = []
            for (paddockId, ts) in dirty {
                guard let paddock = byId[paddockId], paddock.vineyardId == vineyardId else { continue }
                payloads.append(BackendPaddock.upsert(from: paddock, createdBy: createdBy, clientUpdatedAt: ts))
                pushedIds.append(paddockId)
            }
            if !payloads.isEmpty {
                try await repository.upsertPaddocks(payloads)
                metadata.clearDirty(pushedIds)
            }
        }

        let deletes = metadata.pendingDeletes
        var deleteFailures: [String] = []
        for (paddockId, _) in deletes {
            do {
                try await repository.softDeletePaddock(id: paddockId)
                metadata.clearDeleted([paddockId])
            } catch {
                if Self.isMissingRowError(error) {
                    metadata.clearDeleted([paddockId])
                    #if DEBUG
                    print("[PaddockSync] soft delete: remote paddock \(paddockId) already missing — clearing pending delete")
                    #endif
                } else {
                    #if DEBUG
                    print("[PaddockSync] soft delete failed for \(paddockId): \(error.localizedDescription)")
                    #endif
                    deleteFailures.append(error.localizedDescription)
                    continue
                }
            }
        }
        if !deleteFailures.isEmpty {
            errorMessage = "Some paddock deletes failed: \(deleteFailures.first ?? "unknown")"
        }
    }

    private static func isMissingRowError(_ error: Error) -> Bool {
        let message = String(describing: error).lowercased()
        if message.contains("paddock not found") { return true }
        if message.contains("not found") { return true }
        if message.contains("pgrst116") { return true }
        if message.contains("no rows") { return true }
        if message.contains("0 rows") { return true }
        return false
    }

    // MARK: - Pull

    func pullRemotePaddocks(vineyardId: UUID) async throws {
        guard let store else { return }
        let lastSync = metadata.lastSync(for: vineyardId)
        let remote = try await repository.fetchPaddocks(vineyardId: vineyardId, since: lastSync)

        // Initial sync: if remote is empty AND we have local paddocks AND we have
        // never synced before, push them all up so the cloud picks them up.
        if remote.isEmpty, lastSync == nil {
            let localForVineyard = store.paddocks.filter { $0.vineyardId == vineyardId }
            if !localForVineyard.isEmpty {
                let now = Date()
                let createdBy = auth?.userId
                let payloads = localForVineyard.map {
                    BackendPaddock.upsert(from: $0, createdBy: createdBy, clientUpdatedAt: now)
                }
                try await repository.upsertPaddocks(payloads)
            }
            return
        }

        for backendPaddock in remote {
            applyRemote(backendPaddock, vineyardId: vineyardId, store: store)
        }
    }

    private func applyRemote(_ backendPaddock: BackendPaddock, vineyardId: UUID, store: MigratedDataStore) {
        // Soft-deleted remotely.
        if backendPaddock.deletedAt != nil {
            store.applyRemotePaddockDelete(backendPaddock.id)
            metadata.clearDirty([backendPaddock.id])
            metadata.clearDeleted([backendPaddock.id])
            return
        }

        // Last-write-wins: only apply remote if it's newer than the local pending change.
        if let pendingDirtyAt = metadata.pendingUpserts[backendPaddock.id] {
            let remoteAt = backendPaddock.clientUpdatedAt ?? backendPaddock.updatedAt ?? .distantPast
            if pendingDirtyAt > remoteAt { return }
        }

        let mapped = backendPaddock.toPaddock()
        store.applyRemotePaddockUpsert(mapped)
        metadata.clearDirty([backendPaddock.id])
    }
}

// MARK: - Metadata

@MainActor
final class PaddockSyncMetadata {
    private let persistence: PersistenceStore
    private let key: String = "vinetrack_paddock_sync_metadata"
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
