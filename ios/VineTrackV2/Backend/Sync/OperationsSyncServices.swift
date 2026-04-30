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

    private weak var store: MigratedDataStore?
    private weak var auth: NewBackendAuthService?
    private let repository: any WorkTaskSyncRepositoryProtocol
    private let metadata: OperationsSyncMetadata
    private var isConfigured: Bool = false

    init(repository: (any WorkTaskSyncRepositoryProtocol)? = nil) {
        self.repository = repository ?? SupabaseWorkTaskSyncRepository()
        self.metadata = OperationsSyncMetadata(key: "vinetrack_work_task_sync_metadata")
    }

    func configure(store: MigratedDataStore, auth: NewBackendAuthService) {
        self.store = store
        self.auth = auth
        guard !isConfigured else { return }
        isConfigured = true
        store.onWorkTaskChanged = { [weak self] id in self?.metadata.markDirty(id, at: Date()) }
        store.onWorkTaskDeleted = { [weak self] id in self?.metadata.markDeleted(id, at: Date()) }
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
            let byId = Dictionary(uniqueKeysWithValues: store.workTasks.map { ($0.id, $0) })
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
        if remote.isEmpty, lastSync == nil {
            let local = store.workTasks.filter { $0.vineyardId == vineyardId }
            if !local.isEmpty {
                let now = Date()
                let createdBy = auth?.userId
                let payloads = local.map { BackendWorkTask.upsert(from: $0, createdBy: createdBy, clientUpdatedAt: now) }
                do { try await repository.upsertMany(payloads) } catch {
                    #if DEBUG
                    print("[WorkTaskSync] initial seed push failed: \(error.localizedDescription)")
                    #endif
                }
            }
            return
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

    init(
        repository: (any MaintenanceLogSyncRepositoryProtocol)? = nil,
        photoStorage: MaintenancePhotoStorageService? = nil
    ) {
        self.repository = repository ?? SupabaseMaintenanceLogSyncRepository()
        self.metadata = OperationsSyncMetadata(key: "vinetrack_maintenance_log_sync_metadata")
        self.photoStorage = photoStorage ?? MaintenancePhotoStorageService()
    }

    func configure(store: MigratedDataStore, auth: NewBackendAuthService) {
        self.store = store
        self.auth = auth
        guard !isConfigured else { return }
        isConfigured = true
        store.onMaintenanceLogChanged = { [weak self] id in self?.metadata.markDirty(id, at: Date()) }
        store.onMaintenanceLogDeleted = { [weak self] id in self?.metadata.markDeleted(id, at: Date()) }
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
            let byId = Dictionary(uniqueKeysWithValues: store.maintenanceLogs.map { ($0.id, $0) })
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
        if remote.isEmpty, lastSync == nil {
            let local = store.maintenanceLogs.filter { $0.vineyardId == vineyardId }
            if !local.isEmpty {
                let now = Date()
                let createdBy = auth?.userId
                let payloads = local.map { BackendMaintenanceLog.upsert(from: $0, createdBy: createdBy, clientUpdatedAt: now) }
                do { try await repository.upsertMany(payloads) } catch {
                    #if DEBUG
                    print("[MaintenanceLogSync] initial seed push failed: \(error.localizedDescription)")
                    #endif
                }
            }
            return
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
            let byId = Dictionary(uniqueKeysWithValues: store.yieldSessions.map { ($0.id, $0) })
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
        if remote.isEmpty, lastSync == nil {
            let local = store.yieldSessions.filter { $0.vineyardId == vineyardId }
            if !local.isEmpty {
                let now = Date()
                let createdBy = auth?.userId
                let payloads = local.map { BackendYieldEstimationSession.upsert(from: $0, createdBy: createdBy, clientUpdatedAt: now) }
                do { try await repository.upsertMany(payloads) } catch {
                    #if DEBUG
                    print("[YieldSessionSync] initial seed push failed: \(error.localizedDescription)")
                    #endif
                }
            }
            return
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

    init(repository: (any DamageRecordSyncRepositoryProtocol)? = nil) {
        self.repository = repository ?? SupabaseDamageRecordSyncRepository()
        self.metadata = OperationsSyncMetadata(key: "vinetrack_damage_record_sync_metadata")
    }

    func configure(store: MigratedDataStore, auth: NewBackendAuthService) {
        self.store = store
        self.auth = auth
        guard !isConfigured else { return }
        isConfigured = true
        store.onDamageRecordChanged = { [weak self] id in self?.metadata.markDirty(id, at: Date()) }
        store.onDamageRecordDeleted = { [weak self] id in self?.metadata.markDeleted(id, at: Date()) }
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
            let byId = Dictionary(uniqueKeysWithValues: store.damageRecords.map { ($0.id, $0) })
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
        if remote.isEmpty, lastSync == nil {
            let local = store.damageRecords.filter { $0.vineyardId == vineyardId }
            if !local.isEmpty {
                let now = Date()
                let createdBy = auth?.userId
                let payloads = local.map { BackendDamageRecord.upsert(from: $0, createdBy: createdBy, clientUpdatedAt: now) }
                do { try await repository.upsertMany(payloads) } catch {
                    #if DEBUG
                    print("[DamageRecordSync] initial seed push failed: \(error.localizedDescription)")
                    #endif
                }
            }
            return
        }
        for item in remote {
            if item.deletedAt != nil {
                store.applyRemoteDamageRecordDelete(item.id)
                metadata.clearDirty([item.id]); metadata.clearDeleted([item.id]); continue
            }
            if let pendingAt = metadata.pendingUpserts[item.id] {
                let remoteAt = item.clientUpdatedAt ?? item.updatedAt ?? .distantPast
                if pendingAt > remoteAt { continue }
            }
            store.applyRemoteDamageRecordUpsert(item.toDamageRecord())
            metadata.clearDirty([item.id])
        }
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
            let byId = Dictionary(uniqueKeysWithValues: store.historicalYieldRecords.map { ($0.id, $0) })
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
        if remote.isEmpty, lastSync == nil {
            let local = store.historicalYieldRecords.filter { $0.vineyardId == vineyardId }
            if !local.isEmpty {
                let now = Date()
                let createdBy = auth?.userId
                let payloads = local.map { BackendHistoricalYieldRecord.upsert(from: $0, createdBy: createdBy, clientUpdatedAt: now) }
                do { try await repository.upsertMany(payloads) } catch {
                    #if DEBUG
                    print("[HistoricalYieldSync] initial seed push failed: \(error.localizedDescription)")
                    #endif
                }
            }
            return
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
