import Foundation
import Observation

// MARK: - Shared metadata (Phase 15G)

@MainActor
final class OperationsSyncMetadata {
    private let persistence: PersistenceStore
    private let key: String
    private var state: State

    nonisolated struct State: Codable, Sendable {
        var lastSyncByVineyard: [UUID: Date] = [:]
        var pendingUpserts: [UUID: Date] = [:]
        var pendingDeletes: [UUID: Date] = [:]
    }

    init(key: String, persistence: PersistenceStore = .shared) {
        self.key = key
        self.persistence = persistence
        self.state = persistence.load(key: key) ?? State()
    }

    var pendingUpserts: [UUID: Date] { state.pendingUpserts }
    var pendingDeletes: [UUID: Date] { state.pendingDeletes }

    func lastSync(for vineyardId: UUID) -> Date? { state.lastSyncByVineyard[vineyardId] }
    func setLastSync(_ date: Date, for vineyardId: UUID) {
        state.lastSyncByVineyard[vineyardId] = date; save()
    }
    func markDirty(_ id: UUID, at date: Date) { state.pendingUpserts[id] = date; save() }
    func markDeleted(_ id: UUID, at date: Date) {
        state.pendingUpserts.removeValue(forKey: id); state.pendingDeletes[id] = date; save()
    }
    func clearDirty(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        for id in ids { state.pendingUpserts.removeValue(forKey: id) }; save()
    }
    func clearDeleted(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        for id in ids { state.pendingDeletes.removeValue(forKey: id) }; save()
    }

    /// Reset all per-vineyard last-sync timestamps so the next sync is treated
    /// as an initial sync. Used by one-time recovery migrations for rows that
    /// pre-date sync wiring and were never pushed.
    func resetAllLastSync() {
        guard !state.lastSyncByVineyard.isEmpty else { return }
        state.lastSyncByVineyard = [:]
        save()
    }

    private func save() { persistence.save(state, key: key) }
}

private func isOperationsMissingRowError(_ error: Error) -> Bool {
    let m = String(describing: error).lowercased()
    return m.contains("not found") || m.contains("pgrst116") || m.contains("no rows") || m.contains("0 rows")
}

nonisolated enum OperationsSyncStatus: Equatable, Sendable {
    case idle
    case syncing
    case success
    case failure(String)
}

// MARK: - WorkTaskSyncService

@Observable
@MainActor
final class WorkTaskSyncService {
    typealias Status = OperationsSyncStatus

    var syncStatus: Status = .idle
    var lastSyncDate: Date?
    var errorMessage: String?

    var pendingUpsertCount: Int { metadata.pendingUpserts.count }
    var pendingDeleteCount: Int { metadata.pendingDeletes.count }

    private weak var store: MigratedDataStore?
    private weak var auth: NewBackendAuthService?
    private let repository: any WorkTaskSyncRepositoryProtocol
    private let metadata: OperationsSyncMetadata
    private var isConfigured: Bool = false
    private var eagerPushTask: Task<Void, Never>?

    private func scheduleEagerPush() {
        eagerPushTask?.cancel()
        eagerPushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            if Task.isCancelled { return }
            await self?.syncForSelectedVineyard()
        }
    }

    init(repository: (any WorkTaskSyncRepositoryProtocol)? = nil) {
        self.repository = repository ?? SupabaseWorkTaskSyncRepository()
        self.metadata = OperationsSyncMetadata(key: "vinetrack_work_task_sync_metadata")

        // One-time recovery: re-attempt initial seed push for rows that
        // pre-date sync wiring but never reached Supabase.
        let migrationKey = "vinetrack_work_task_sync_reset_v1"
        if !UserDefaults.standard.bool(forKey: migrationKey) {
            self.metadata.resetAllLastSync()
            UserDefaults.standard.set(true, forKey: migrationKey)
        }
    }

    func configure(store: MigratedDataStore, auth: NewBackendAuthService) {
        self.store = store
        self.auth = auth
        guard !isConfigured else { return }
        isConfigured = true
        store.onWorkTaskChanged = { [weak self] id in
            self?.metadata.markDirty(id, at: Date()); self?.scheduleEagerPush()
        }
        store.onWorkTaskDeleted = { [weak self] id in
            self?.metadata.markDeleted(id, at: Date()); self?.scheduleEagerPush()
        }
    }

    func syncForSelectedVineyard() async {
        guard let store, let auth, auth.isSignedIn,
              let vineyardId = store.selectedVineyardId else { return }
        await sync(vineyardId: vineyardId)
    }

    func sync(vineyardId: UUID) async {
        guard SupabaseClientProvider.shared.isConfigured else {
            errorMessage = "Supabase not configured"; syncStatus = .failure("Supabase not configured"); return
        }
        syncStatus = .syncing; errorMessage = nil
        do {
            try await push(vineyardId: vineyardId)
            try await pull(vineyardId: vineyardId)
            metadata.setLastSync(Date(), for: vineyardId)
            lastSyncDate = Date()
            syncStatus = .success
        } catch {
            errorMessage = error.localizedDescription
            syncStatus = .failure(error.localizedDescription)
        }
    }

    private func push(vineyardId: UUID) async throws {
        guard let store else { return }
        let createdBy = auth?.userId
        let dirty = metadata.pendingUpserts
        if !dirty.isEmpty {
            let byId = Dictionary(store.workTasks.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
            var payloads: [BackendWorkTaskUpsert] = []
            var pushed: [UUID] = []
            for (id, ts) in dirty {
                guard let item = byId[id], item.vineyardId == vineyardId else { continue }
                payloads.append(BackendWorkTask.upsert(from: item, createdBy: createdBy, clientUpdatedAt: ts))
                pushed.append(id)
            }
            if !payloads.isEmpty {
                try await repository.upsertMany(payloads)
                metadata.clearDirty(pushed)
            }
        }
        let pendingDeletes = metadata.pendingDeletes
        if !pendingDeletes.isEmpty {
            #if DEBUG
            print("[WorkTaskSync] push: \(pendingDeletes.count) pending delete(s) for vineyard \(vineyardId.uuidString)")
            #endif
        }
        var firstDeleteError: Error?
        for (id, _) in pendingDeletes {
            do {
                try await repository.softDelete(id: id)
                metadata.clearDeleted([id])
                #if DEBUG
                print("[WorkTaskSync] push: soft-deleted id=\(id) on server")
                #endif
            } catch {
                if isOperationsMissingRowError(error) {
                    metadata.clearDeleted([id])
                    #if DEBUG
                    print("[WorkTaskSync] push: id=\(id) missing on server — clearing pending delete")
                    #endif
                } else {
                    #if DEBUG
                    print("[WorkTaskSync] push: soft-delete FAILED id=\(id) error=\(error.localizedDescription) raw=\(String(describing: error))")
                    #endif
                    if firstDeleteError == nil { firstDeleteError = error }
                }
            }
        }
        if let firstDeleteError { throw firstDeleteError }
    }

    private func pull(vineyardId: UUID) async throws {
        guard let store else { return }
        let lastSync = metadata.lastSync(for: vineyardId)
        let remote = try await repository.fetch(vineyardId: vineyardId, since: lastSync)
        if lastSync == nil {
            let remoteIds = Set(remote.map { $0.id })
            let local = store.workTasks.filter { $0.vineyardId == vineyardId }
            let missing = local.filter { !remoteIds.contains($0.id) }
            if !missing.isEmpty {
                let now = Date()
                let createdBy = auth?.userId
                let payloads = missing.map { BackendWorkTask.upsert(from: $0, createdBy: createdBy, clientUpdatedAt: now) }
                do {
                    try await repository.upsertMany(payloads)
                    #if DEBUG
                    print("[WorkTaskSync] initial seed pushed \(payloads.count) local row(s) missing remotely")
                    #endif
                } catch {
                    #if DEBUG
                    print("[WorkTaskSync] initial seed push failed: \(error.localizedDescription)")
                    #endif
                }
            }
            if remote.isEmpty { return }
        }
        for item in remote {
            if item.deletedAt != nil {
                store.applyRemoteWorkTaskDelete(item.id)
                metadata.clearDirty([item.id]); metadata.clearDeleted([item.id]); continue
            }
            if let pendingAt = metadata.pendingUpserts[item.id] {
                let remoteAt = item.clientUpdatedAt ?? item.updatedAt ?? .distantPast
                if pendingAt > remoteAt { continue }
            }
            store.applyRemoteWorkTaskUpsert(item.toWorkTask())
            metadata.clearDirty([item.id])
        }
    }
}

// MARK: - WorkTaskLabourLineSyncService

@Observable
@MainActor
final class WorkTaskLabourLineSyncService {
    typealias Status = OperationsSyncStatus

    var syncStatus: Status = .idle
    var lastSyncDate: Date?
    var errorMessage: String?

    var pendingUpsertCount: Int { metadata.pendingUpserts.count }
    var pendingDeleteCount: Int { metadata.pendingDeletes.count }

    private weak var store: MigratedDataStore?
    private weak var auth: NewBackendAuthService?
    private let repository: any WorkTaskLabourLineSyncRepositoryProtocol
    private let metadata: OperationsSyncMetadata
    private var isConfigured: Bool = false
    private var eagerPushTask: Task<Void, Never>?

    private func scheduleEagerPush() {
        eagerPushTask?.cancel()
        eagerPushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            if Task.isCancelled { return }
            await self?.syncForSelectedVineyard()
        }
    }

    init(repository: (any WorkTaskLabourLineSyncRepositoryProtocol)? = nil) {
        self.repository = repository ?? SupabaseWorkTaskLabourLineSyncRepository()
        self.metadata = OperationsSyncMetadata(key: "vinetrack_work_task_labour_line_sync_metadata")
    }

    func configure(store: MigratedDataStore, auth: NewBackendAuthService) {
        self.store = store
        self.auth = auth
        guard !isConfigured else { return }
        isConfigured = true
        store.onWorkTaskLabourLineChanged = { [weak self] id in
            self?.metadata.markDirty(id, at: Date()); self?.scheduleEagerPush()
        }
        store.onWorkTaskLabourLineDeleted = { [weak self] id in
            self?.metadata.markDeleted(id, at: Date()); self?.scheduleEagerPush()
        }
    }

    func syncForSelectedVineyard() async {
        guard let store, let auth, auth.isSignedIn,
              let vineyardId = store.selectedVineyardId else { return }
        await sync(vineyardId: vineyardId)
    }

    func sync(vineyardId: UUID) async {
        guard SupabaseClientProvider.shared.isConfigured else {
            errorMessage = "Supabase not configured"; syncStatus = .failure("Supabase not configured"); return
        }
        syncStatus = .syncing; errorMessage = nil
        do {
            try await push(vineyardId: vineyardId)
            try await pull(vineyardId: vineyardId)
            metadata.setLastSync(Date(), for: vineyardId)
            lastSyncDate = Date()
            syncStatus = .success
        } catch {
            errorMessage = error.localizedDescription
            syncStatus = .failure(error.localizedDescription)
        }
    }

    private func push(vineyardId: UUID) async throws {
        guard let store else { return }
        let userId = auth?.userId
        let dirty = metadata.pendingUpserts
        if !dirty.isEmpty {
            let byId = Dictionary(store.workTaskLabourLines.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
            var payloads: [BackendWorkTaskLabourLineUpsert] = []
            var pushed: [UUID] = []
            for (id, ts) in dirty {
                guard let item = byId[id], item.vineyardId == vineyardId else { continue }
                payloads.append(BackendWorkTaskLabourLine.upsert(
                    from: item, createdBy: userId, updatedBy: userId, clientUpdatedAt: ts
                ))
                pushed.append(id)
            }
            if !payloads.isEmpty {
                try await repository.upsertMany(payloads)
                metadata.clearDirty(pushed)
            }
        }
        let pendingDeletes = metadata.pendingDeletes
        if !pendingDeletes.isEmpty {
            #if DEBUG
            print("[WorkTaskLabourLineSync] push: \(pendingDeletes.count) pending delete(s) for vineyard \(vineyardId.uuidString)")
            #endif
        }
        var firstDeleteError: Error?
        for (id, _) in pendingDeletes {
            do {
                try await repository.softDelete(id: id)
                metadata.clearDeleted([id])
                #if DEBUG
                print("[WorkTaskLabourLineSync] push: soft-deleted id=\(id) on server")
                #endif
            } catch {
                if isOperationsMissingRowError(error) {
                    metadata.clearDeleted([id])
                    #if DEBUG
                    print("[WorkTaskLabourLineSync] push: id=\(id) missing on server — clearing pending delete")
                    #endif
                } else {
                    #if DEBUG
                    print("[WorkTaskLabourLineSync] push: soft-delete FAILED id=\(id) error=\(error.localizedDescription) raw=\(String(describing: error))")
                    #endif
                    if firstDeleteError == nil { firstDeleteError = error }
                }
            }
        }
        if let firstDeleteError { throw firstDeleteError }
    }

    private func pull(vineyardId: UUID) async throws {
        guard let store else { return }
        let lastSync = metadata.lastSync(for: vineyardId)
        let remote = try await repository.fetch(vineyardId: vineyardId, since: lastSync)
        if lastSync == nil {
            let remoteIds = Set(remote.map { $0.id })
            let local = store.workTaskLabourLines.filter { $0.vineyardId == vineyardId }
            let missing = local.filter { !remoteIds.contains($0.id) }
            if !missing.isEmpty {
                let now = Date()
                let userId = auth?.userId
                let payloads = missing.map {
                    BackendWorkTaskLabourLine.upsert(from: $0, createdBy: userId, updatedBy: userId, clientUpdatedAt: now)
                }
                do {
                    try await repository.upsertMany(payloads)
                    #if DEBUG
                    print("[WorkTaskLabourLineSync] initial seed pushed \(payloads.count) local row(s) missing remotely")
                    #endif
                } catch {
                    #if DEBUG
                    print("[WorkTaskLabourLineSync] initial seed push failed: \(error.localizedDescription)")
                    #endif
                }
            }
            if remote.isEmpty { return }
        }
        for item in remote {
            if item.deletedAt != nil {
                store.applyRemoteWorkTaskLabourLineDelete(item.id)
                metadata.clearDirty([item.id]); metadata.clearDeleted([item.id]); continue
            }
            if let pendingAt = metadata.pendingUpserts[item.id] {
                let remoteAt = item.clientUpdatedAt ?? item.updatedAt ?? .distantPast
                if pendingAt > remoteAt { continue }
            }
            store.applyRemoteWorkTaskLabourLineUpsert(item.toWorkTaskLabourLine())
            metadata.clearDirty([item.id])
        }
    }
}

// MARK: - WorkTaskPaddockSyncService

@Observable
@MainActor
final class WorkTaskPaddockSyncService {
    typealias Status = OperationsSyncStatus

    var syncStatus: Status = .idle
    var lastSyncDate: Date?
    var errorMessage: String?

    var pendingUpsertCount: Int { metadata.pendingUpserts.count }
    var pendingDeleteCount: Int { metadata.pendingDeletes.count }

    private weak var store: MigratedDataStore?
    private weak var auth: NewBackendAuthService?
    private let repository: any WorkTaskPaddockSyncRepositoryProtocol
    private let metadata: OperationsSyncMetadata
    private var isConfigured: Bool = false
    private var eagerPushTask: Task<Void, Never>?

    private func scheduleEagerPush() {
        eagerPushTask?.cancel()
        eagerPushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            if Task.isCancelled { return }
            await self?.syncForSelectedVineyard()
        }
    }

    init(repository: (any WorkTaskPaddockSyncRepositoryProtocol)? = nil) {
        self.repository = repository ?? SupabaseWorkTaskPaddockSyncRepository()
        self.metadata = OperationsSyncMetadata(key: "vinetrack_work_task_paddock_sync_metadata")
    }

    func configure(store: MigratedDataStore, auth: NewBackendAuthService) {
        self.store = store
        self.auth = auth
        guard !isConfigured else { return }
        isConfigured = true
        store.onWorkTaskPaddockChanged = { [weak self] id in
            self?.metadata.markDirty(id, at: Date()); self?.scheduleEagerPush()
        }
        store.onWorkTaskPaddockDeleted = { [weak self] id in
            self?.metadata.markDeleted(id, at: Date()); self?.scheduleEagerPush()
        }
    }

    func syncForSelectedVineyard() async {
        guard let store, let auth, auth.isSignedIn,
              let vineyardId = store.selectedVineyardId else { return }
        await sync(vineyardId: vineyardId)
    }

    func sync(vineyardId: UUID) async {
        guard SupabaseClientProvider.shared.isConfigured else {
            errorMessage = "Supabase not configured"; syncStatus = .failure("Supabase not configured"); return
        }
        syncStatus = .syncing; errorMessage = nil
        do {
            try await push(vineyardId: vineyardId)
            try await pull(vineyardId: vineyardId)
            metadata.setLastSync(Date(), for: vineyardId)
            lastSyncDate = Date()
            syncStatus = .success
        } catch {
            errorMessage = error.localizedDescription
            syncStatus = .failure(error.localizedDescription)
        }
    }

    private func push(vineyardId: UUID) async throws {
        guard let store else { return }
        let userId = auth?.userId
        let dirty = metadata.pendingUpserts
        if !dirty.isEmpty {
            let byId = Dictionary(store.workTaskPaddocks.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
            var payloads: [BackendWorkTaskPaddockUpsert] = []
            var pushed: [UUID] = []
            for (id, ts) in dirty {
                guard let item = byId[id], item.vineyardId == vineyardId else { continue }
                payloads.append(BackendWorkTaskPaddock.upsert(
                    from: item, createdBy: userId, updatedBy: userId, clientUpdatedAt: ts
                ))
                pushed.append(id)
            }
            if !payloads.isEmpty {
                try await repository.upsertMany(payloads)
                metadata.clearDirty(pushed)
            }
        }
        let pendingDeletes = metadata.pendingDeletes
        if !pendingDeletes.isEmpty {
            #if DEBUG
            print("[WorkTaskPaddockSync] push: \(pendingDeletes.count) pending delete(s) for vineyard \(vineyardId.uuidString)")
            #endif
        }
        var firstDeleteError: Error?
        for (id, _) in pendingDeletes {
            do {
                try await repository.softDelete(id: id)
                metadata.clearDeleted([id])
                #if DEBUG
                print("[WorkTaskPaddockSync] push: soft-deleted id=\(id) on server")
                #endif
            } catch {
                if isOperationsMissingRowError(error) {
                    metadata.clearDeleted([id])
                    #if DEBUG
                    print("[WorkTaskPaddockSync] push: id=\(id) missing on server — clearing pending delete")
                    #endif
                } else {
                    #if DEBUG
                    print("[WorkTaskPaddockSync] push: soft-delete FAILED id=\(id) error=\(error.localizedDescription)")
                    #endif
                    if firstDeleteError == nil { firstDeleteError = error }
                }
            }
        }
        if let firstDeleteError { throw firstDeleteError }
    }

    private func pull(vineyardId: UUID) async throws {
        guard let store else { return }
        let lastSync = metadata.lastSync(for: vineyardId)
        let remote = try await repository.fetch(vineyardId: vineyardId, since: lastSync)
        if lastSync == nil {
            let remoteIds = Set(remote.map { $0.id })
            let local = store.workTaskPaddocks.filter { $0.vineyardId == vineyardId }
            let missing = local.filter { !remoteIds.contains($0.id) }
            if !missing.isEmpty {
                let now = Date()
                let userId = auth?.userId
                let payloads = missing.map {
                    BackendWorkTaskPaddock.upsert(from: $0, createdBy: userId, updatedBy: userId, clientUpdatedAt: now)
                }
                do {
                    try await repository.upsertMany(payloads)
                    #if DEBUG
                    print("[WorkTaskPaddockSync] initial seed pushed \(payloads.count) local row(s) missing remotely")
                    #endif
                } catch {
                    #if DEBUG
                    print("[WorkTaskPaddockSync] initial seed push failed: \(error.localizedDescription)")
                    #endif
                }
            }
            if remote.isEmpty { return }
        }
        for item in remote {
            if item.deletedAt != nil {
                store.applyRemoteWorkTaskPaddockDelete(item.id)
                metadata.clearDirty([item.id]); metadata.clearDeleted([item.id]); continue
            }
            if let pendingAt = metadata.pendingUpserts[item.id] {
                let remoteAt = item.clientUpdatedAt ?? item.updatedAt ?? .distantPast
                if pendingAt > remoteAt { continue }
            }
            store.applyRemoteWorkTaskPaddockUpsert(item.toWorkTaskPaddock())
            metadata.clearDirty([item.id])
        }
    }
}

// MARK: - MaintenanceLogSyncService

@Observable
@MainActor
final class MaintenanceLogSyncService {
    typealias Status = OperationsSyncStatus

    var syncStatus: Status = .idle
    var lastSyncDate: Date?
    var errorMessage: String?

    private weak var store: MigratedDataStore?
    private weak var auth: NewBackendAuthService?
    private let repository: any MaintenanceLogSyncRepositoryProtocol
    private let metadata: OperationsSyncMetadata
    private let photoStorage: MaintenancePhotoStorageService
    private var isConfigured: Bool = false
    private var eagerPushTask: Task<Void, Never>?

    private func scheduleEagerPush() {
        eagerPushTask?.cancel()
        eagerPushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            if Task.isCancelled { return }
            await self?.syncForSelectedVineyard()
        }
    }

    init(
        repository: (any MaintenanceLogSyncRepositoryProtocol)? = nil,
        photoStorage: MaintenancePhotoStorageService? = nil
    ) {
        self.repository = repository ?? SupabaseMaintenanceLogSyncRepository()
        self.metadata = OperationsSyncMetadata(key: "vinetrack_maintenance_log_sync_metadata")
        self.photoStorage = photoStorage ?? MaintenancePhotoStorageService()

        let migrationKey = "vinetrack_maintenance_log_sync_reset_v1"
        if !UserDefaults.standard.bool(forKey: migrationKey) {
            self.metadata.resetAllLastSync()
            UserDefaults.standard.set(true, forKey: migrationKey)
        }
    }

    func configure(store: MigratedDataStore, auth: NewBackendAuthService) {
        self.store = store
        self.auth = auth
        guard !isConfigured else { return }
        isConfigured = true
        store.onMaintenanceLogChanged = { [weak self] id in
            self?.metadata.markDirty(id, at: Date()); self?.scheduleEagerPush()
        }
        store.onMaintenanceLogDeleted = { [weak self] id in
            self?.metadata.markDeleted(id, at: Date()); self?.scheduleEagerPush()
        }
    }

    func syncForSelectedVineyard() async {
        guard let store, let auth, auth.isSignedIn,
              let vineyardId = store.selectedVineyardId else { return }
        await sync(vineyardId: vineyardId)
    }

    func sync(vineyardId: UUID) async {
        guard SupabaseClientProvider.shared.isConfigured else {
            errorMessage = "Supabase not configured"; syncStatus = .failure("Supabase not configured"); return
        }
        syncStatus = .syncing; errorMessage = nil
        do {
            try await push(vineyardId: vineyardId)
            try await pull(vineyardId: vineyardId)
            metadata.setLastSync(Date(), for: vineyardId)
            lastSyncDate = Date()
            syncStatus = .success
        } catch {
            errorMessage = error.localizedDescription
            syncStatus = .failure(error.localizedDescription)
        }
    }

    private func push(vineyardId: UUID) async throws {
        guard let store else { return }
        let createdBy = auth?.userId
        let dirty = metadata.pendingUpserts
        if !dirty.isEmpty {
            let byId = Dictionary(store.maintenanceLogs.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
            var payloads: [BackendMaintenanceLogUpsert] = []
            var pushed: [UUID] = []
            var photoUploadFailures: [String] = []
            for (id, ts) in dirty {
                guard var item = byId[id], item.vineyardId == vineyardId else { continue }
                // If the log has a local invoice photo but no synced path, upload first.
                if let data = item.invoicePhotoData, item.photoPath == nil {
                    SharedImageCache.shared.saveImageData(
                        data,
                        for: .maintenancePhoto(vineyardId: vineyardId, maintenanceId: item.id),
                        remotePath: nil,
                        remoteUpdatedAt: nil
                    )
                    do {
                        let path = try await photoStorage.uploadPhoto(
                            vineyardId: vineyardId,
                            maintenanceId: item.id,
                            imageData: data
                        )
                        item.photoPath = path
                        store.applyRemoteMaintenanceLogUpsert(item)
                    } catch {
                        #if DEBUG
                        print("[MaintenanceLogSync] photo upload failed for \(item.id): \(error.localizedDescription)")
                        #endif
                        photoUploadFailures.append(error.localizedDescription)
                        // Still push log metadata; photo will retry next sync.
                    }
                }
                payloads.append(BackendMaintenanceLog.upsert(from: item, createdBy: createdBy, clientUpdatedAt: ts))
                pushed.append(id)
            }
            if !payloads.isEmpty {
                try await repository.upsertMany(payloads)
                metadata.clearDirty(pushed)
            }
            if !photoUploadFailures.isEmpty {
                let first = photoUploadFailures.first ?? "unknown"
                errorMessage = "Some maintenance photos failed to upload: \(first)"
            }
        }
        for (id, _) in metadata.pendingDeletes {
            do {
                try await repository.softDelete(id: id)
                metadata.clearDeleted([id])
            } catch {
                if isOperationsMissingRowError(error) { metadata.clearDeleted([id]) }
            }
        }
    }

    private func pull(vineyardId: UUID) async throws {
        guard let store else { return }
        let lastSync = metadata.lastSync(for: vineyardId)
        let remote = try await repository.fetch(vineyardId: vineyardId, since: lastSync)
        if lastSync == nil {
            let remoteIds = Set(remote.map { $0.id })
            let local = store.maintenanceLogs.filter { $0.vineyardId == vineyardId }
            let missing = local.filter { !remoteIds.contains($0.id) }
            if !missing.isEmpty {
                let now = Date()
                let createdBy = auth?.userId
                let payloads = missing.map { BackendMaintenanceLog.upsert(from: $0, createdBy: createdBy, clientUpdatedAt: now) }
                do {
                    try await repository.upsertMany(payloads)
                    #if DEBUG
                    print("[MaintenanceLogSync] initial seed pushed \(payloads.count) local row(s) missing remotely")
                    #endif
                } catch {
                    #if DEBUG
                    print("[MaintenanceLogSync] initial seed push failed: \(error.localizedDescription)")
                    #endif
                }
            }
            if remote.isEmpty { return }
        }
        for item in remote {
            if item.deletedAt != nil {
                if let local = store.maintenanceLogs.first(where: { $0.id == item.id }) {
                    SharedImageCache.shared.removeCachedImage(
                        for: .maintenancePhoto(vineyardId: local.vineyardId, maintenanceId: local.id)
                    )
                }
                store.applyRemoteMaintenanceLogDelete(item.id)
                metadata.clearDirty([item.id]); metadata.clearDeleted([item.id]); continue
            }
            if let pendingAt = metadata.pendingUpserts[item.id] {
                let remoteAt = item.clientUpdatedAt ?? item.updatedAt ?? .distantPast
                if pendingAt > remoteAt { continue }
            }

            let existingLocal = store.maintenanceLogs.first(where: { $0.id == item.id })
            let existingPhotoData = existingLocal?.invoicePhotoData
            let existingPhotoPath = existingLocal?.photoPath

            var mapped = item.toMaintenanceLog(preservingPhoto: existingPhotoData)

            if let remotePath = mapped.photoPath {
                let cacheKey = SharedImageCacheKey.maintenancePhoto(vineyardId: vineyardId, maintenanceId: item.id)
                let pathChanged = existingPhotoPath != remotePath

                if mapped.invoicePhotoData == nil || pathChanged {
                    if !pathChanged,
                       let cached = SharedImageCache.shared.cachedImageData(for: cacheKey) {
                        mapped.invoicePhotoData = cached
                    }
                }

                let needsDownload = mapped.invoicePhotoData == nil || pathChanged
                if needsDownload {
                    do {
                        let data = try await photoStorage.downloadPhoto(
                            path: remotePath,
                            vineyardId: vineyardId,
                            maintenanceId: item.id
                        )
                        mapped.invoicePhotoData = data
                    } catch {
                        #if DEBUG
                        print("[MaintenanceLogSync] photo download failed for \(item.id) at \(remotePath): \(error.localizedDescription)")
                        #endif
                        if mapped.invoicePhotoData == nil,
                           let cached = SharedImageCache.shared.cachedImageData(for: cacheKey) {
                            mapped.invoicePhotoData = cached
                        }
                    }
                }
            }

            store.applyRemoteMaintenanceLogUpsert(mapped)
            metadata.clearDirty([item.id])
        }
    }
}

// MARK: - YieldEstimationSessionSyncService

@Observable
@MainActor
final class YieldEstimationSessionSyncService {
    typealias Status = OperationsSyncStatus

    var syncStatus: Status = .idle
    var lastSyncDate: Date?
    var errorMessage: String?

    private weak var store: MigratedDataStore?
    private weak var auth: NewBackendAuthService?
    private let repository: any YieldEstimationSessionSyncRepositoryProtocol
    private let metadata: OperationsSyncMetadata
    private var isConfigured: Bool = false

    init(repository: (any YieldEstimationSessionSyncRepositoryProtocol)? = nil) {
        self.repository = repository ?? SupabaseYieldEstimationSessionSyncRepository()
        self.metadata = OperationsSyncMetadata(key: "vinetrack_yield_session_sync_metadata")

        let migrationKey = "vinetrack_yield_session_sync_reset_v1"
        if !UserDefaults.standard.bool(forKey: migrationKey) {
            self.metadata.resetAllLastSync()
            UserDefaults.standard.set(true, forKey: migrationKey)
        }
    }

    func configure(store: MigratedDataStore, auth: NewBackendAuthService) {
        self.store = store
        self.auth = auth
        guard !isConfigured else { return }
        isConfigured = true
        store.onYieldSessionChanged = { [weak self] id in self?.metadata.markDirty(id, at: Date()) }
        store.onYieldSessionDeleted = { [weak self] id in self?.metadata.markDeleted(id, at: Date()) }
    }

    func syncForSelectedVineyard() async {
        guard let store, let auth, auth.isSignedIn,
              let vineyardId = store.selectedVineyardId else { return }
        await sync(vineyardId: vineyardId)
    }

    func sync(vineyardId: UUID) async {
        guard SupabaseClientProvider.shared.isConfigured else {
            errorMessage = "Supabase not configured"; syncStatus = .failure("Supabase not configured"); return
        }
        syncStatus = .syncing; errorMessage = nil
        do {
            try await push(vineyardId: vineyardId)
            try await pull(vineyardId: vineyardId)
            metadata.setLastSync(Date(), for: vineyardId)
            lastSyncDate = Date()
            syncStatus = .success
        } catch {
            errorMessage = error.localizedDescription
            syncStatus = .failure(error.localizedDescription)
        }
    }

    private func push(vineyardId: UUID) async throws {
        guard let store else { return }
        let createdBy = auth?.userId
        let dirty = metadata.pendingUpserts
        if !dirty.isEmpty {
            let byId = Dictionary(store.yieldSessions.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
            var payloads: [BackendYieldEstimationSessionUpsert] = []
            var pushed: [UUID] = []
            for (id, ts) in dirty {
                guard let item = byId[id], item.vineyardId == vineyardId else { continue }
                payloads.append(BackendYieldEstimationSession.upsert(from: item, createdBy: createdBy, clientUpdatedAt: ts))
                pushed.append(id)
            }
            if !payloads.isEmpty {
                try await repository.upsertMany(payloads)
                metadata.clearDirty(pushed)
            }
        }
        for (id, _) in metadata.pendingDeletes {
            do {
                try await repository.softDelete(id: id)
                metadata.clearDeleted([id])
            } catch {
                if isOperationsMissingRowError(error) { metadata.clearDeleted([id]) }
            }
        }
    }

    private func pull(vineyardId: UUID) async throws {
        guard let store else { return }
        let lastSync = metadata.lastSync(for: vineyardId)
        let remote = try await repository.fetch(vineyardId: vineyardId, since: lastSync)
        if lastSync == nil {
            let remoteIds = Set(remote.map { $0.id })
            let local = store.yieldSessions.filter { $0.vineyardId == vineyardId }
            let missing = local.filter { !remoteIds.contains($0.id) }
            if !missing.isEmpty {
                let now = Date()
                let createdBy = auth?.userId
                let payloads = missing.map { BackendYieldEstimationSession.upsert(from: $0, createdBy: createdBy, clientUpdatedAt: now) }
                do {
                    try await repository.upsertMany(payloads)
                    #if DEBUG
                    print("[YieldSessionSync] initial seed pushed \(payloads.count) local row(s) missing remotely")
                    #endif
                } catch {
                    #if DEBUG
                    print("[YieldSessionSync] initial seed push failed: \(error.localizedDescription)")
                    #endif
                }
            }
            if remote.isEmpty { return }
        }
        for item in remote {
            if item.deletedAt != nil {
                store.applyRemoteYieldSessionDelete(item.id)
                metadata.clearDirty([item.id]); metadata.clearDeleted([item.id]); continue
            }
            if let pendingAt = metadata.pendingUpserts[item.id] {
                let remoteAt = item.clientUpdatedAt ?? item.updatedAt ?? .distantPast
                if pendingAt > remoteAt { continue }
            }
            guard let mapped = item.toYieldEstimationSession() else { continue }
            store.applyRemoteYieldSessionUpsert(mapped)
            metadata.clearDirty([item.id])
        }
    }
}

// MARK: - DamageRecordSyncService

@Observable
@MainActor
final class DamageRecordSyncService {
    typealias Status = OperationsSyncStatus

    var syncStatus: Status = .idle
    var lastSyncDate: Date?
    var errorMessage: String?

    private weak var store: MigratedDataStore?
    private weak var auth: NewBackendAuthService?
    private let repository: any DamageRecordSyncRepositoryProtocol
    private let metadata: OperationsSyncMetadata
    private var isConfigured: Bool = false
    private var eagerPushTask: Task<Void, Never>?

    private func scheduleEagerPush() {
        eagerPushTask?.cancel()
        eagerPushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            if Task.isCancelled { return }
            await self?.syncForSelectedVineyard()
        }
    }

    init(repository: (any DamageRecordSyncRepositoryProtocol)? = nil) {
        self.repository = repository ?? SupabaseDamageRecordSyncRepository()
        self.metadata = OperationsSyncMetadata(key: "vinetrack_damage_record_sync_metadata")

        let migrationKey = "vinetrack_damage_record_sync_reset_v1"
        if !UserDefaults.standard.bool(forKey: migrationKey) {
            self.metadata.resetAllLastSync()
            UserDefaults.standard.set(true, forKey: migrationKey)
        }
    }

    func configure(store: MigratedDataStore, auth: NewBackendAuthService) {
        self.store = store
        self.auth = auth
        guard !isConfigured else { return }
        isConfigured = true
        store.onDamageRecordChanged = { [weak self] id in
            self?.metadata.markDirty(id, at: Date()); self?.scheduleEagerPush()
        }
        store.onDamageRecordDeleted = { [weak self] id in
            self?.metadata.markDeleted(id, at: Date()); self?.scheduleEagerPush()
        }
    }

    func syncForSelectedVineyard() async {
        guard let store, let auth, auth.isSignedIn,
              let vineyardId = store.selectedVineyardId else { return }
        await sync(vineyardId: vineyardId)
    }

    func sync(vineyardId: UUID) async {
        guard SupabaseClientProvider.shared.isConfigured else {
            errorMessage = "Supabase not configured"; syncStatus = .failure("Supabase not configured"); return
        }
        syncStatus = .syncing; errorMessage = nil
        do {
            try await push(vineyardId: vineyardId)
            try await pull(vineyardId: vineyardId)
            metadata.setLastSync(Date(), for: vineyardId)
            lastSyncDate = Date()
            syncStatus = .success
        } catch {
            errorMessage = error.localizedDescription
            syncStatus = .failure(error.localizedDescription)
        }
    }

    private func push(vineyardId: UUID) async throws {
        guard let store else { return }
        let createdBy = auth?.userId
        let dirty = metadata.pendingUpserts
        if !dirty.isEmpty {
            let byId = Dictionary(store.damageRecords.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
            var payloads: [BackendDamageRecordUpsert] = []
            var pushed: [UUID] = []
            for (id, ts) in dirty {
                guard let item = byId[id], item.vineyardId == vineyardId else { continue }
                payloads.append(BackendDamageRecord.upsert(from: item, createdBy: createdBy, clientUpdatedAt: ts))
                pushed.append(id)
            }
            if !payloads.isEmpty {
                try await repository.upsertMany(payloads)
                metadata.clearDirty(pushed)
            }
        }
        let pendingDeletes = metadata.pendingDeletes
        if !pendingDeletes.isEmpty {
            #if DEBUG
            print("[DamageRecordSync] push: \(pendingDeletes.count) pending delete(s) for vineyard \(vineyardId.uuidString)")
            #endif
        }
        var firstDeleteError: Error?
        for (id, _) in pendingDeletes {
            do {
                try await repository.softDelete(id: id)
                metadata.clearDeleted([id])
                #if DEBUG
                print("[DamageRecordSync] push: soft-deleted id=\(id) on server")
                #endif
            } catch {
                if isOperationsMissingRowError(error) {
                    metadata.clearDeleted([id])
                    #if DEBUG
                    print("[DamageRecordSync] push: id=\(id) missing on server — clearing pending delete")
                    #endif
                } else {
                    #if DEBUG
                    print("[DamageRecordSync] push: soft-delete FAILED id=\(id) error=\(error.localizedDescription) raw=\(String(describing: error))")
                    #endif
                    if firstDeleteError == nil { firstDeleteError = error }
                }
            }
        }
        if let firstDeleteError { throw firstDeleteError }
    }

    private func pull(vineyardId: UUID) async throws {
        guard let store else { return }
        let lastSync = metadata.lastSync(for: vineyardId)
        let remote = try await repository.fetch(vineyardId: vineyardId, since: lastSync)
        if lastSync == nil {
            let remoteIds = Set(remote.map { $0.id })
            let local = store.damageRecords.filter { $0.vineyardId == vineyardId }
            let missing = local.filter { !remoteIds.contains($0.id) }
            if !missing.isEmpty {
                let now = Date()
                let createdBy = auth?.userId
                let payloads = missing.map { BackendDamageRecord.upsert(from: $0, createdBy: createdBy, clientUpdatedAt: now) }
                do {
                    try await repository.upsertMany(payloads)
                    #if DEBUG
                    print("[DamageRecordSync] initial seed pushed \(payloads.count) local row(s) missing remotely")
                    #endif
                } catch {
                    #if DEBUG
                    print("[DamageRecordSync] initial seed push failed: \(error.localizedDescription)")
                    #endif
                }
            }
            if remote.isEmpty { return }
        }
        #if DEBUG
        print("[DamageRecordSync] pull vineyard=\(vineyardId.uuidString) since=\(lastSync.map { ISO8601DateFormatter().string(from: $0) } ?? "nil") remote.count=\(remote.count)")
        for item in remote {
            print("[DamageRecordSync]   remote id=\(item.id) paddock=\(item.paddockId) type=\(item.damageType ?? "nil") deletedAt=\(item.deletedAt?.description ?? "nil")")
        }
        #endif
        for item in remote {
            if item.deletedAt != nil {
                store.applyRemoteDamageRecordDelete(item.id)
                metadata.clearDirty([item.id]); metadata.clearDeleted([item.id]); continue
            }
            if let pendingAt = metadata.pendingUpserts[item.id] {
                let remoteAt = item.clientUpdatedAt ?? item.updatedAt ?? .distantPast
                if pendingAt > remoteAt {
                    #if DEBUG
                    print("[DamageRecordSync]   skip id=\(item.id) — local pending newer than remote")
                    #endif
                    continue
                }
            }
            store.applyRemoteDamageRecordUpsert(item.toDamageRecord())
            metadata.clearDirty([item.id])
            #if DEBUG
            print("[DamageRecordSync]   upsert local id=\(item.id)")
            #endif
        }
        #if DEBUG
        print("[DamageRecordSync] local store now has \(store.damageRecords.filter { $0.vineyardId == vineyardId }.count) damage record(s) for vineyard")
        #endif
    }
}

// MARK: - HistoricalYieldRecordSyncService

@Observable
@MainActor
final class HistoricalYieldRecordSyncService {
    typealias Status = OperationsSyncStatus

    var syncStatus: Status = .idle
    var lastSyncDate: Date?
    var errorMessage: String?

    private weak var store: MigratedDataStore?
    private weak var auth: NewBackendAuthService?
    private let repository: any HistoricalYieldRecordSyncRepositoryProtocol
    private let metadata: OperationsSyncMetadata
    private var isConfigured: Bool = false

    init(repository: (any HistoricalYieldRecordSyncRepositoryProtocol)? = nil) {
        self.repository = repository ?? SupabaseHistoricalYieldRecordSyncRepository()
        self.metadata = OperationsSyncMetadata(key: "vinetrack_historical_yield_sync_metadata")

        let migrationKey = "vinetrack_historical_yield_sync_reset_v1"
        if !UserDefaults.standard.bool(forKey: migrationKey) {
            self.metadata.resetAllLastSync()
            UserDefaults.standard.set(true, forKey: migrationKey)
        }
    }

    func configure(store: MigratedDataStore, auth: NewBackendAuthService) {
        self.store = store
        self.auth = auth
        guard !isConfigured else { return }
        isConfigured = true
        store.onHistoricalYieldRecordChanged = { [weak self] id in self?.metadata.markDirty(id, at: Date()) }
        store.onHistoricalYieldRecordDeleted = { [weak self] id in self?.metadata.markDeleted(id, at: Date()) }
    }

    func syncForSelectedVineyard() async {
        guard let store, let auth, auth.isSignedIn,
              let vineyardId = store.selectedVineyardId else { return }
        await sync(vineyardId: vineyardId)
    }

    func sync(vineyardId: UUID) async {
        guard SupabaseClientProvider.shared.isConfigured else {
            errorMessage = "Supabase not configured"; syncStatus = .failure("Supabase not configured"); return
        }
        syncStatus = .syncing; errorMessage = nil
        do {
            try await push(vineyardId: vineyardId)
            try await pull(vineyardId: vineyardId)
            metadata.setLastSync(Date(), for: vineyardId)
            lastSyncDate = Date()
            syncStatus = .success
        } catch {
            errorMessage = error.localizedDescription
            syncStatus = .failure(error.localizedDescription)
        }
    }

    private func push(vineyardId: UUID) async throws {
        guard let store else { return }
        let createdBy = auth?.userId
        let dirty = metadata.pendingUpserts
        if !dirty.isEmpty {
            let byId = Dictionary(store.historicalYieldRecords.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
            var payloads: [BackendHistoricalYieldRecordUpsert] = []
            var pushed: [UUID] = []
            for (id, ts) in dirty {
                guard let item = byId[id], item.vineyardId == vineyardId else { continue }
                payloads.append(BackendHistoricalYieldRecord.upsert(from: item, createdBy: createdBy, clientUpdatedAt: ts))
                pushed.append(id)
            }
            if !payloads.isEmpty {
                try await repository.upsertMany(payloads)
                metadata.clearDirty(pushed)
            }
        }
        for (id, _) in metadata.pendingDeletes {
            do {
                try await repository.softDelete(id: id)
                metadata.clearDeleted([id])
            } catch {
                if isOperationsMissingRowError(error) { metadata.clearDeleted([id]) }
            }
        }
    }

    private func pull(vineyardId: UUID) async throws {
        guard let store else { return }
        let lastSync = metadata.lastSync(for: vineyardId)
        let remote = try await repository.fetch(vineyardId: vineyardId, since: lastSync)
        if lastSync == nil {
            let remoteIds = Set(remote.map { $0.id })
            let local = store.historicalYieldRecords.filter { $0.vineyardId == vineyardId }
            let missing = local.filter { !remoteIds.contains($0.id) }
            if !missing.isEmpty {
                let now = Date()
                let createdBy = auth?.userId
                let payloads = missing.map { BackendHistoricalYieldRecord.upsert(from: $0, createdBy: createdBy, clientUpdatedAt: now) }
                do {
                    try await repository.upsertMany(payloads)
                    #if DEBUG
                    print("[HistoricalYieldSync] initial seed pushed \(payloads.count) local row(s) missing remotely")
                    #endif
                } catch {
                    #if DEBUG
                    print("[HistoricalYieldSync] initial seed push failed: \(error.localizedDescription)")
                    #endif
                }
            }
            if remote.isEmpty { return }
        }
        for item in remote {
            if item.deletedAt != nil {
                store.applyRemoteHistoricalYieldRecordDelete(item.id)
                metadata.clearDirty([item.id]); metadata.clearDeleted([item.id]); continue
            }
            if let pendingAt = metadata.pendingUpserts[item.id] {
                let remoteAt = item.clientUpdatedAt ?? item.updatedAt ?? .distantPast
                if pendingAt > remoteAt { continue }
            }
            store.applyRemoteHistoricalYieldRecordUpsert(item.toHistoricalYieldRecord())
            metadata.clearDirty([item.id])
        }
    }
}
