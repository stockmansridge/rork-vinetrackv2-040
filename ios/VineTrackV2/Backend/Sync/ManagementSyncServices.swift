import Foundation
import Observation

// MARK: - Shared metadata

@MainActor
final class ManagementSyncMetadata {
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

    private func save() { persistence.save(state, key: key) }
}

private func isMissingRowError(_ error: Error) -> Bool {
    let message = String(describing: error).lowercased()
    if message.contains("not found") { return true }
    if message.contains("pgrst116") { return true }
    if message.contains("no rows") { return true }
    if message.contains("0 rows") { return true }
    return false
}

nonisolated enum ManagementSyncStatus: Equatable, Sendable {
    case idle
    case syncing
    case success
    case failure(String)
}

// MARK: - SavedChemicalSyncService

@Observable
@MainActor
final class SavedChemicalSyncService {
    typealias Status = ManagementSyncStatus

    var syncStatus: Status = .idle
    var lastSyncDate: Date?
    var errorMessage: String?

    private weak var store: MigratedDataStore?
    private weak var auth: NewBackendAuthService?
    private let repository: any SavedChemicalSyncRepositoryProtocol
    private let metadata: ManagementSyncMetadata
    private var isConfigured: Bool = false

    init(repository: (any SavedChemicalSyncRepositoryProtocol)? = nil) {
        self.repository = repository ?? SupabaseSavedChemicalSyncRepository()
        self.metadata = ManagementSyncMetadata(key: "vinetrack_saved_chemical_sync_metadata")
    }

    func configure(store: MigratedDataStore, auth: NewBackendAuthService) {
        self.store = store
        self.auth = auth
        guard !isConfigured else { return }
        isConfigured = true
        store.onSavedChemicalChanged = { [weak self] id in self?.metadata.markDirty(id, at: Date()) }
        store.onSavedChemicalDeleted = { [weak self] id in self?.metadata.markDeleted(id, at: Date()) }
    }

    func syncForSelectedVineyard() async {
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
            let byId = Dictionary(uniqueKeysWithValues: store.savedChemicals.map { ($0.id, $0) })
            var payloads: [BackendSavedChemicalUpsert] = []
            var pushed: [UUID] = []
            for (id, ts) in dirty {
                guard let item = byId[id], item.vineyardId == vineyardId else { continue }
                payloads.append(BackendSavedChemical.upsert(from: item, createdBy: createdBy, clientUpdatedAt: ts))
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
                if isMissingRowError(error) {
                    metadata.clearDeleted([id])
                }
            }
        }
    }

    private func pull(vineyardId: UUID) async throws {
        guard let store else { return }
        let lastSync = metadata.lastSync(for: vineyardId)
        let remote = try await repository.fetch(vineyardId: vineyardId, since: lastSync)
        if remote.isEmpty, lastSync == nil {
            let local = store.savedChemicals.filter { $0.vineyardId == vineyardId }
            if !local.isEmpty {
                let now = Date()
                let createdBy = auth?.userId
                let payloads = local.map { BackendSavedChemical.upsert(from: $0, createdBy: createdBy, clientUpdatedAt: now) }
                do {
                    try await repository.upsertMany(payloads)
                } catch {
                    // Likely RLS — operator can't write. Ignore default seeding push.
                    #if DEBUG
                    print("[SavedChemicalSync] initial seed push failed: \(error.localizedDescription)")
                    #endif
                }
            }
            return
        }
        for item in remote {
            if item.deletedAt != nil {
                store.applyRemoteSavedChemicalDelete(item.id)
                metadata.clearDirty([item.id])
                metadata.clearDeleted([item.id])
                continue
            }
            if let pendingAt = metadata.pendingUpserts[item.id] {
                let remoteAt = item.clientUpdatedAt ?? item.updatedAt ?? .distantPast
                if pendingAt > remoteAt { continue }
            }
            store.applyRemoteSavedChemicalUpsert(item.toSavedChemical())
            metadata.clearDirty([item.id])
        }
    }
}

// MARK: - SavedSprayPresetSyncService

@Observable
@MainActor
final class SavedSprayPresetSyncService {
    typealias Status = ManagementSyncStatus

    var syncStatus: Status = .idle
    var lastSyncDate: Date?
    var errorMessage: String?

    private weak var store: MigratedDataStore?
    private weak var auth: NewBackendAuthService?
    private let repository: any SavedSprayPresetSyncRepositoryProtocol
    private let metadata: ManagementSyncMetadata
    private var isConfigured: Bool = false

    init(repository: (any SavedSprayPresetSyncRepositoryProtocol)? = nil) {
        self.repository = repository ?? SupabaseSavedSprayPresetSyncRepository()
        self.metadata = ManagementSyncMetadata(key: "vinetrack_saved_spray_preset_sync_metadata")
    }

    func configure(store: MigratedDataStore, auth: NewBackendAuthService) {
        self.store = store
        self.auth = auth
        guard !isConfigured else { return }
        isConfigured = true
        store.onSavedSprayPresetChanged = { [weak self] id in self?.metadata.markDirty(id, at: Date()) }
        store.onSavedSprayPresetDeleted = { [weak self] id in self?.metadata.markDeleted(id, at: Date()) }
    }

    func syncForSelectedVineyard() async {
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
            let byId = Dictionary(uniqueKeysWithValues: store.savedSprayPresets.map { ($0.id, $0) })
            var payloads: [BackendSavedSprayPresetUpsert] = []
            var pushed: [UUID] = []
            for (id, ts) in dirty {
                guard let item = byId[id], item.vineyardId == vineyardId else { continue }
                payloads.append(BackendSavedSprayPreset.upsert(from: item, createdBy: createdBy, clientUpdatedAt: ts))
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
                if isMissingRowError(error) { metadata.clearDeleted([id]) }
            }
        }
    }

    private func pull(vineyardId: UUID) async throws {
        guard let store else { return }
        let lastSync = metadata.lastSync(for: vineyardId)
        let remote = try await repository.fetch(vineyardId: vineyardId, since: lastSync)
        if remote.isEmpty, lastSync == nil {
            let local = store.savedSprayPresets.filter { $0.vineyardId == vineyardId }
            if !local.isEmpty {
                let now = Date()
                let createdBy = auth?.userId
                let payloads = local.map { BackendSavedSprayPreset.upsert(from: $0, createdBy: createdBy, clientUpdatedAt: now) }
                do { try await repository.upsertMany(payloads) } catch {
                    #if DEBUG
                    print("[SavedSprayPresetSync] initial seed push failed: \(error.localizedDescription)")
                    #endif
                }
            }
            return
        }
        for item in remote {
            if item.deletedAt != nil {
                store.applyRemoteSavedSprayPresetDelete(item.id)
                metadata.clearDirty([item.id])
                metadata.clearDeleted([item.id])
                continue
            }
            if let pendingAt = metadata.pendingUpserts[item.id] {
                let remoteAt = item.clientUpdatedAt ?? item.updatedAt ?? .distantPast
                if pendingAt > remoteAt { continue }
            }
            store.applyRemoteSavedSprayPresetUpsert(item.toSavedSprayPreset())
            metadata.clearDirty([item.id])
        }
    }
}

// MARK: - SprayEquipmentSyncService

@Observable
@MainActor
final class SprayEquipmentSyncService {
    typealias Status = ManagementSyncStatus

    var syncStatus: Status = .idle
    var lastSyncDate: Date?
    var errorMessage: String?

    private weak var store: MigratedDataStore?
    private weak var auth: NewBackendAuthService?
    private let repository: any SprayEquipmentSyncRepositoryProtocol
    private let metadata: ManagementSyncMetadata
    private var isConfigured: Bool = false

    init(repository: (any SprayEquipmentSyncRepositoryProtocol)? = nil) {
        self.repository = repository ?? SupabaseSprayEquipmentSyncRepository()
        self.metadata = ManagementSyncMetadata(key: "vinetrack_spray_equipment_sync_metadata")
    }

    func configure(store: MigratedDataStore, auth: NewBackendAuthService) {
        self.store = store
        self.auth = auth
        guard !isConfigured else { return }
        isConfigured = true
        store.onSprayEquipmentChanged = { [weak self] id in self?.metadata.markDirty(id, at: Date()) }
        store.onSprayEquipmentDeleted = { [weak self] id in self?.metadata.markDeleted(id, at: Date()) }
    }

    func syncForSelectedVineyard() async {
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
            let byId = Dictionary(uniqueKeysWithValues: store.sprayEquipment.map { ($0.id, $0) })
            var payloads: [BackendSprayEquipmentUpsert] = []
            var pushed: [UUID] = []
            for (id, ts) in dirty {
                guard let item = byId[id], item.vineyardId == vineyardId else { continue }
                payloads.append(BackendSprayEquipment.upsert(from: item, createdBy: createdBy, clientUpdatedAt: ts))
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
                if isMissingRowError(error) { metadata.clearDeleted([id]) }
            }
        }
    }

    private func pull(vineyardId: UUID) async throws {
        guard let store else { return }
        let lastSync = metadata.lastSync(for: vineyardId)
        let remote = try await repository.fetch(vineyardId: vineyardId, since: lastSync)
        if remote.isEmpty, lastSync == nil {
            let local = store.sprayEquipment.filter { $0.vineyardId == vineyardId }
            if !local.isEmpty {
                let now = Date()
                let createdBy = auth?.userId
                let payloads = local.map { BackendSprayEquipment.upsert(from: $0, createdBy: createdBy, clientUpdatedAt: now) }
                do { try await repository.upsertMany(payloads) } catch {
                    #if DEBUG
                    print("[SprayEquipmentSync] initial seed push failed: \(error.localizedDescription)")
                    #endif
                }
            }
            return
        }
        for item in remote {
            if item.deletedAt != nil {
                store.applyRemoteSprayEquipmentDelete(item.id)
                metadata.clearDirty([item.id])
                metadata.clearDeleted([item.id])
                continue
            }
            if let pendingAt = metadata.pendingUpserts[item.id] {
                let remoteAt = item.clientUpdatedAt ?? item.updatedAt ?? .distantPast
                if pendingAt > remoteAt { continue }
            }
            store.applyRemoteSprayEquipmentUpsert(item.toSprayEquipmentItem())
            metadata.clearDirty([item.id])
        }
    }
}

// MARK: - TractorSyncService

@Observable
@MainActor
final class TractorSyncService {
    typealias Status = ManagementSyncStatus

    var syncStatus: Status = .idle
    var lastSyncDate: Date?
    var errorMessage: String?

    private weak var store: MigratedDataStore?
    private weak var auth: NewBackendAuthService?
    private let repository: any TractorSyncRepositoryProtocol
    private let metadata: ManagementSyncMetadata
    private var isConfigured: Bool = false

    init(repository: (any TractorSyncRepositoryProtocol)? = nil) {
        self.repository = repository ?? SupabaseTractorSyncRepository()
        self.metadata = ManagementSyncMetadata(key: "vinetrack_tractor_sync_metadata")
    }

    func configure(store: MigratedDataStore, auth: NewBackendAuthService) {
        self.store = store
        self.auth = auth
        guard !isConfigured else { return }
        isConfigured = true
        store.onTractorChanged = { [weak self] id in self?.metadata.markDirty(id, at: Date()) }
        store.onTractorDeleted = { [weak self] id in self?.metadata.markDeleted(id, at: Date()) }
    }

    func syncForSelectedVineyard() async {
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
            let byId = Dictionary(uniqueKeysWithValues: store.tractors.map { ($0.id, $0) })
            var payloads: [BackendTractorUpsert] = []
            var pushed: [UUID] = []
            for (id, ts) in dirty {
                guard let item = byId[id], item.vineyardId == vineyardId else { continue }
                payloads.append(BackendTractor.upsert(from: item, createdBy: createdBy, clientUpdatedAt: ts))
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
                if isMissingRowError(error) { metadata.clearDeleted([id]) }
            }
        }
    }

    private func pull(vineyardId: UUID) async throws {
        guard let store else { return }
        let lastSync = metadata.lastSync(for: vineyardId)
        let remote = try await repository.fetch(vineyardId: vineyardId, since: lastSync)
        if remote.isEmpty, lastSync == nil {
            let local = store.tractors.filter { $0.vineyardId == vineyardId }
            if !local.isEmpty {
                let now = Date()
                let createdBy = auth?.userId
                let payloads = local.map { BackendTractor.upsert(from: $0, createdBy: createdBy, clientUpdatedAt: now) }
                do { try await repository.upsertMany(payloads) } catch {
                    #if DEBUG
                    print("[TractorSync] initial seed push failed: \(error.localizedDescription)")
                    #endif
                }
            }
            return
        }
        for item in remote {
            if item.deletedAt != nil {
                store.applyRemoteTractorDelete(item.id)
                metadata.clearDirty([item.id])
                metadata.clearDeleted([item.id])
                continue
            }
            if let pendingAt = metadata.pendingUpserts[item.id] {
                let remoteAt = item.clientUpdatedAt ?? item.updatedAt ?? .distantPast
                if pendingAt > remoteAt { continue }
            }
            store.applyRemoteTractorUpsert(item.toTractor())
            metadata.clearDirty([item.id])
        }
    }
}

// MARK: - FuelPurchaseSyncService

@Observable
@MainActor
final class FuelPurchaseSyncService {
    typealias Status = ManagementSyncStatus

    var syncStatus: Status = .idle
    var lastSyncDate: Date?
    var errorMessage: String?

    private weak var store: MigratedDataStore?
    private weak var auth: NewBackendAuthService?
    private let repository: any FuelPurchaseSyncRepositoryProtocol
    private let metadata: ManagementSyncMetadata
    private var isConfigured: Bool = false

    init(repository: (any FuelPurchaseSyncRepositoryProtocol)? = nil) {
        self.repository = repository ?? SupabaseFuelPurchaseSyncRepository()
        self.metadata = ManagementSyncMetadata(key: "vinetrack_fuel_purchase_sync_metadata")
    }

    func configure(store: MigratedDataStore, auth: NewBackendAuthService) {
        self.store = store
        self.auth = auth
        guard !isConfigured else { return }
        isConfigured = true
        store.onFuelPurchaseChanged = { [weak self] id in self?.metadata.markDirty(id, at: Date()) }
        store.onFuelPurchaseDeleted = { [weak self] id in self?.metadata.markDeleted(id, at: Date()) }
    }

    func syncForSelectedVineyard() async {
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
            let byId = Dictionary(uniqueKeysWithValues: store.fuelPurchases.map { ($0.id, $0) })
            var payloads: [BackendFuelPurchaseUpsert] = []
            var pushed: [UUID] = []
            for (id, ts) in dirty {
                guard let item = byId[id], item.vineyardId == vineyardId else { continue }
                payloads.append(BackendFuelPurchase.upsert(from: item, createdBy: createdBy, clientUpdatedAt: ts))
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
                if isMissingRowError(error) { metadata.clearDeleted([id]) }
            }
        }
    }

    private func pull(vineyardId: UUID) async throws {
        guard let store else { return }
        let lastSync = metadata.lastSync(for: vineyardId)
        let remote = try await repository.fetch(vineyardId: vineyardId, since: lastSync)
        if remote.isEmpty, lastSync == nil {
            let local = store.fuelPurchases.filter { $0.vineyardId == vineyardId }
            if !local.isEmpty {
                let now = Date()
                let createdBy = auth?.userId
                let payloads = local.map { BackendFuelPurchase.upsert(from: $0, createdBy: createdBy, clientUpdatedAt: now) }
                do { try await repository.upsertMany(payloads) } catch {
                    #if DEBUG
                    print("[FuelPurchaseSync] initial seed push failed: \(error.localizedDescription)")
                    #endif
                }
            }
            return
        }
        for item in remote {
            if item.deletedAt != nil {
                store.applyRemoteFuelPurchaseDelete(item.id)
                metadata.clearDirty([item.id])
                metadata.clearDeleted([item.id])
                continue
            }
            if let pendingAt = metadata.pendingUpserts[item.id] {
                let remoteAt = item.clientUpdatedAt ?? item.updatedAt ?? .distantPast
                if pendingAt > remoteAt { continue }
            }
            store.applyRemoteFuelPurchaseUpsert(item.toFuelPurchase())
            metadata.clearDirty([item.id])
        }
    }
}

// MARK: - OperatorCategorySyncService

@Observable
@MainActor
final class OperatorCategorySyncService {
    typealias Status = ManagementSyncStatus

    var syncStatus: Status = .idle
    var lastSyncDate: Date?
    var errorMessage: String?

    private weak var store: MigratedDataStore?
    private weak var auth: NewBackendAuthService?
    private let repository: any OperatorCategorySyncRepositoryProtocol
    private let metadata: ManagementSyncMetadata
    private var isConfigured: Bool = false

    init(repository: (any OperatorCategorySyncRepositoryProtocol)? = nil) {
        self.repository = repository ?? SupabaseOperatorCategorySyncRepository()
        self.metadata = ManagementSyncMetadata(key: "vinetrack_operator_category_sync_metadata")
    }

    func configure(store: MigratedDataStore, auth: NewBackendAuthService) {
        self.store = store
        self.auth = auth
        guard !isConfigured else { return }
        isConfigured = true
        store.onOperatorCategoryChanged = { [weak self] id in self?.metadata.markDirty(id, at: Date()) }
        store.onOperatorCategoryDeleted = { [weak self] id in self?.metadata.markDeleted(id, at: Date()) }
    }

    func syncForSelectedVineyard() async {
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
            let byId = Dictionary(uniqueKeysWithValues: store.operatorCategories.map { ($0.id, $0) })
            var payloads: [BackendOperatorCategoryUpsert] = []
            var pushed: [UUID] = []
            for (id, ts) in dirty {
                guard let item = byId[id], item.vineyardId == vineyardId else { continue }
                payloads.append(BackendOperatorCategory.upsert(from: item, createdBy: createdBy, clientUpdatedAt: ts))
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
                if isMissingRowError(error) { metadata.clearDeleted([id]) }
            }
        }
    }

    private func pull(vineyardId: UUID) async throws {
        guard let store else { return }
        let lastSync = metadata.lastSync(for: vineyardId)
        let remote = try await repository.fetch(vineyardId: vineyardId, since: lastSync)
        if remote.isEmpty, lastSync == nil {
            let local = store.operatorCategories.filter { $0.vineyardId == vineyardId }
            if !local.isEmpty {
                let now = Date()
                let createdBy = auth?.userId
                let payloads = local.map { BackendOperatorCategory.upsert(from: $0, createdBy: createdBy, clientUpdatedAt: now) }
                do { try await repository.upsertMany(payloads) } catch {
                    #if DEBUG
                    print("[OperatorCategorySync] initial seed push failed: \(error.localizedDescription)")
                    #endif
                }
            }
            return
        }
        for item in remote {
            if item.deletedAt != nil {
                store.applyRemoteOperatorCategoryDelete(item.id)
                metadata.clearDirty([item.id])
                metadata.clearDeleted([item.id])
                continue
            }
            if let pendingAt = metadata.pendingUpserts[item.id] {
                let remoteAt = item.clientUpdatedAt ?? item.updatedAt ?? .distantPast
                if pendingAt > remoteAt { continue }
            }
            store.applyRemoteOperatorCategoryUpsert(item.toOperatorCategory())
            metadata.clearDirty([item.id])
        }
    }
}
