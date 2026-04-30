import Foundation
import Observation

/// Local-first sync service for VinePin records.
/// Tracks dirty/deleted pins locally and pushes/pulls them against Supabase
/// using `SupabasePinSyncRepository`. Conflict resolution is last-write-wins
/// based on `client_updated_at`/`updated_at`.
@Observable
@MainActor
final class PinSyncService {

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
    private let repository: any PinSyncRepositoryProtocol
    private let metadata: PinSyncMetadata
    private let photoStorage: PinPhotoStorageService
    private var isConfigured: Bool = false

    init(
        repository: (any PinSyncRepositoryProtocol)? = nil,
        metadata: PinSyncMetadata? = nil,
        photoStorage: PinPhotoStorageService? = nil
    ) {
        self.repository = repository ?? SupabasePinSyncRepository()
        self.metadata = metadata ?? PinSyncMetadata()
        self.photoStorage = photoStorage ?? PinPhotoStorageService()
    }

    // MARK: - Configuration

    func configure(store: MigratedDataStore, auth: NewBackendAuthService) {
        self.store = store
        self.auth = auth
        guard !isConfigured else { return }
        isConfigured = true
        store.onPinChanged = { [weak self] id in
            self?.markPinDirty(id)
        }
        store.onPinDeleted = { [weak self] id in
            self?.markPinDeleted(id)
        }
    }

    // MARK: - Dirty tracking

    func markPinDirty(_ id: UUID) {
        metadata.markDirty(id, at: Date())
    }

    func markPinDeleted(_ id: UUID) {
        metadata.markDeleted(id, at: Date())
    }

    // MARK: - Public sync entry points

    func syncPinsForSelectedVineyard() async {
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
            try await pushLocalPins(vineyardId: vineyardId)
            try await pullRemotePins(vineyardId: vineyardId)
            metadata.setLastSync(Date(), for: vineyardId)
            lastSyncDate = Date()
            syncStatus = .success
        } catch {
            errorMessage = error.localizedDescription
            syncStatus = .failure(error.localizedDescription)
        }
    }

    // MARK: - Push

    func pushLocalPins(vineyardId: UUID) async throws {
        guard let store else { return }
        let dirty = metadata.pendingUpserts
        if !dirty.isEmpty {
            let pinsById = Dictionary(uniqueKeysWithValues: store.pins.map { ($0.id, $0) })
            var payloads: [BackendPinUpsert] = []
            var pushedIds: [UUID] = []
            var photoUploadFailures: [String] = []
            for (pinId, ts) in dirty {
                guard var pin = pinsById[pinId], pin.vineyardId == vineyardId else { continue }
                // If the pin has local photo bytes but no synced path yet, upload first.
                if let data = pin.photoData, pin.photoPath == nil {
                    // Cache locally first so even an upload failure leaves a
                    // hot cache entry for the next sync attempt.
                    SharedImageCache.shared.saveImageData(
                        data,
                        for: .pinPhoto(vineyardId: vineyardId, pinId: pin.id),
                        remotePath: nil,
                        remoteUpdatedAt: nil
                    )
                    do {
                        let path = try await photoStorage.uploadPhoto(
                            vineyardId: vineyardId,
                            pinId: pin.id,
                            imageData: data
                        )
                        pin.photoPath = path
                        store.applyRemotePinUpsert(pin)
                    } catch {
                        #if DEBUG
                        print("[PinSync] photo upload failed for \(pin.id): \(error.localizedDescription)")
                        #endif
                        photoUploadFailures.append(error.localizedDescription)
                        // Still upsert pin metadata; photo will retry next sync.
                    }
                }
                payloads.append(BackendPin.upsert(from: pin, clientUpdatedAt: ts))
                pushedIds.append(pinId)
            }
            if !payloads.isEmpty {
                try await repository.upsertPins(payloads)
                metadata.clearDirty(pushedIds)
            }
            if !photoUploadFailures.isEmpty {
                errorMessage = "Some pin photos failed to upload: \(photoUploadFailures.first ?? "unknown")"
            }
        }

        let deletes = metadata.pendingDeletes
        var deleteFailures: [String] = []
        for (pinId, _) in deletes {
            do {
                try await repository.softDeletePin(id: pinId)
                metadata.clearDeleted([pinId])
            } catch {
                if Self.isMissingRowError(error) {
                    // Remote row already gone — treat as already deleted.
                    metadata.clearDeleted([pinId])
                    #if DEBUG
                    print("[PinSync] soft delete: remote pin \(pinId) already missing — clearing pending delete")
                    #endif
                } else {
                    #if DEBUG
                    print("[PinSync] soft delete failed for \(pinId): \(error.localizedDescription)")
                    #endif
                    deleteFailures.append(error.localizedDescription)
                    // Keep the deletion pending so it retries next sync, but don't abort.
                    continue
                }
            }
        }
        if !deleteFailures.isEmpty {
            // Surface a non-fatal warning via errorMessage but don't throw — let pull and
            // future upserts continue.
            errorMessage = "Some pin deletes failed: \(deleteFailures.first ?? "unknown")"
        }
    }

    private static func isMissingRowError(_ error: Error) -> Bool {
        let message = String(describing: error).lowercased()
        if message.contains("pin not found") { return true }
        if message.contains("not found") { return true }
        if message.contains("pgrst116") { return true }
        if message.contains("no rows") { return true }
        if message.contains("0 rows") { return true }
        return false
    }

    // MARK: - Pull

    func pullRemotePins(vineyardId: UUID) async throws {
        guard let store else { return }
        let lastSync = metadata.lastSync(for: vineyardId)
        let remote = try await repository.fetchPins(vineyardId: vineyardId, since: lastSync)

        // Initial sync: if both local and remote slices are empty, nothing to do.
        // If remote is empty AND we have local pins AND we have never synced before,
        // push them all up so the cloud picks them up.
        if remote.isEmpty, lastSync == nil {
            let localForVineyard = store.pins.filter { $0.vineyardId == vineyardId }
            if !localForVineyard.isEmpty {
                let now = Date()
                let payloads = localForVineyard.map {
                    BackendPin.upsert(from: $0, clientUpdatedAt: now)
                }
                try await repository.upsertPins(payloads)
            }
            return
        }

        for backendPin in remote {
            await applyRemote(backendPin, vineyardId: vineyardId, store: store)
        }
    }

    private func applyRemote(_ backendPin: BackendPin, vineyardId: UUID, store: MigratedDataStore) async {
        let existingIndex = store.pins.firstIndex { $0.id == backendPin.id }

        // Soft-deleted remotely.
        if backendPin.deletedAt != nil {
            if existingIndex != nil {
                store.applyRemotePinDelete(backendPin.id)
            }
            metadata.clearDirty([backendPin.id])
            metadata.clearDeleted([backendPin.id])
            return
        }

        // Last-write-wins: only apply remote if it's newer than the local pending change.
        if let pendingDirtyAt = metadata.pendingUpserts[backendPin.id] {
            let remoteAt = backendPin.clientUpdatedAt ?? backendPin.updatedAt ?? .distantPast
            if pendingDirtyAt > remoteAt {
                return
            }
        }

        let existingPin: VinePin? = existingIndex.map { store.pins[$0] }
        let existingPhotoData: Data? = existingPin?.photoData
        let existingPhotoPath: String? = existingPin?.photoPath

        guard var mapped = backendPin.toVinePin(preservingPhoto: existingPhotoData) else { return }

        // If the remote has a photoPath, try the disk cache first, then
        // fall back to a network download. Failures are non-fatal — we keep
        // whatever cached/local bytes we already have.
        if let remotePath = mapped.photoPath {
            let cacheKey = SharedImageCacheKey.pinPhoto(vineyardId: vineyardId, pinId: backendPin.id)
            let pathChanged = existingPhotoPath != remotePath

            if mapped.photoData == nil || pathChanged {
                if !pathChanged,
                   let cached = SharedImageCache.shared.cachedImageData(for: cacheKey) {
                    mapped.photoData = cached
                }
            }

            let needsDownload = mapped.photoData == nil || pathChanged
            if needsDownload {
                do {
                    let data = try await photoStorage.downloadPhoto(
                        path: remotePath,
                        vineyardId: vineyardId,
                        pinId: backendPin.id
                    )
                    mapped.photoData = data
                } catch {
                    #if DEBUG
                    print("[PinSync] photo download failed for \(backendPin.id) at \(remotePath): \(error.localizedDescription)")
                    #endif
                    // Keep existing cached bytes if any.
                    if mapped.photoData == nil,
                       let cached = SharedImageCache.shared.cachedImageData(for: cacheKey) {
                        mapped.photoData = cached
                    }
                }
            }
        }

        store.applyRemotePinUpsert(mapped)
        metadata.clearDirty([backendPin.id])
    }
}

// MARK: - Metadata

@MainActor
final class PinSyncMetadata {
    private let persistence: PersistenceStore
    private let key: String = "vinetrack_pin_sync_metadata"
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
