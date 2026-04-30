import Foundation

protocol SavedChemicalSyncRepositoryProtocol: Sendable {
    func fetch(vineyardId: UUID, since: Date?) async throws -> [BackendSavedChemical]
    func upsertMany(_ items: [BackendSavedChemicalUpsert]) async throws
    func softDelete(id: UUID) async throws
}

protocol SavedSprayPresetSyncRepositoryProtocol: Sendable {
    func fetch(vineyardId: UUID, since: Date?) async throws -> [BackendSavedSprayPreset]
    func upsertMany(_ items: [BackendSavedSprayPresetUpsert]) async throws
    func softDelete(id: UUID) async throws
}

protocol SprayEquipmentSyncRepositoryProtocol: Sendable {
    func fetch(vineyardId: UUID, since: Date?) async throws -> [BackendSprayEquipment]
    func upsertMany(_ items: [BackendSprayEquipmentUpsert]) async throws
    func softDelete(id: UUID) async throws
}

protocol TractorSyncRepositoryProtocol: Sendable {
    func fetch(vineyardId: UUID, since: Date?) async throws -> [BackendTractor]
    func upsertMany(_ items: [BackendTractorUpsert]) async throws
    func softDelete(id: UUID) async throws
}

protocol FuelPurchaseSyncRepositoryProtocol: Sendable {
    func fetch(vineyardId: UUID, since: Date?) async throws -> [BackendFuelPurchase]
    func upsertMany(_ items: [BackendFuelPurchaseUpsert]) async throws
    func softDelete(id: UUID) async throws
}

protocol OperatorCategorySyncRepositoryProtocol: Sendable {
    func fetch(vineyardId: UUID, since: Date?) async throws -> [BackendOperatorCategory]
    func upsertMany(_ items: [BackendOperatorCategoryUpsert]) async throws
    func softDelete(id: UUID) async throws
}
