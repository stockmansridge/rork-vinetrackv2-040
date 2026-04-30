import Foundation
import Supabase

private nonisolated struct SoftDeleteByIdRequest: Encodable, Sendable {
    let id: UUID
    enum CodingKeys: String, CodingKey {
        case id = "p_id"
    }
}

private func iso(_ date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
}

// MARK: - Saved Chemicals

final class SupabaseSavedChemicalSyncRepository: SavedChemicalSyncRepositoryProtocol {
    private let provider: SupabaseClientProvider
    init(provider: SupabaseClientProvider = .shared) { self.provider = provider }

    func fetch(vineyardId: UUID, since: Date?) async throws -> [BackendSavedChemical] {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        let q = provider.client.from("saved_chemicals").select().eq("vineyard_id", value: vineyardId.uuidString)
        if let since {
            return try await q.gte("updated_at", value: iso(since)).order("updated_at", ascending: true).execute().value
        }
        return try await q.order("updated_at", ascending: true).execute().value
    }

    func upsertMany(_ items: [BackendSavedChemicalUpsert]) async throws {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        guard !items.isEmpty else { return }
        try await provider.client.from("saved_chemicals").upsert(items, onConflict: "id").execute()
    }

    func softDelete(id: UUID) async throws {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        try await provider.client.rpc("soft_delete_saved_chemical", params: SoftDeleteByIdRequest(id: id)).execute()
    }
}

// MARK: - Saved Spray Presets

final class SupabaseSavedSprayPresetSyncRepository: SavedSprayPresetSyncRepositoryProtocol {
    private let provider: SupabaseClientProvider
    init(provider: SupabaseClientProvider = .shared) { self.provider = provider }

    func fetch(vineyardId: UUID, since: Date?) async throws -> [BackendSavedSprayPreset] {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        let q = provider.client.from("saved_spray_presets").select().eq("vineyard_id", value: vineyardId.uuidString)
        if let since {
            return try await q.gte("updated_at", value: iso(since)).order("updated_at", ascending: true).execute().value
        }
        return try await q.order("updated_at", ascending: true).execute().value
    }

    func upsertMany(_ items: [BackendSavedSprayPresetUpsert]) async throws {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        guard !items.isEmpty else { return }
        try await provider.client.from("saved_spray_presets").upsert(items, onConflict: "id").execute()
    }

    func softDelete(id: UUID) async throws {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        try await provider.client.rpc("soft_delete_saved_spray_preset", params: SoftDeleteByIdRequest(id: id)).execute()
    }
}

// MARK: - Spray Equipment

final class SupabaseSprayEquipmentSyncRepository: SprayEquipmentSyncRepositoryProtocol {
    private let provider: SupabaseClientProvider
    init(provider: SupabaseClientProvider = .shared) { self.provider = provider }

    func fetch(vineyardId: UUID, since: Date?) async throws -> [BackendSprayEquipment] {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        let q = provider.client.from("spray_equipment").select().eq("vineyard_id", value: vineyardId.uuidString)
        if let since {
            return try await q.gte("updated_at", value: iso(since)).order("updated_at", ascending: true).execute().value
        }
        return try await q.order("updated_at", ascending: true).execute().value
    }

    func upsertMany(_ items: [BackendSprayEquipmentUpsert]) async throws {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        guard !items.isEmpty else { return }
        try await provider.client.from("spray_equipment").upsert(items, onConflict: "id").execute()
    }

    func softDelete(id: UUID) async throws {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        try await provider.client.rpc("soft_delete_spray_equipment", params: SoftDeleteByIdRequest(id: id)).execute()
    }
}

// MARK: - Tractors

final class SupabaseTractorSyncRepository: TractorSyncRepositoryProtocol {
    private let provider: SupabaseClientProvider
    init(provider: SupabaseClientProvider = .shared) { self.provider = provider }

    func fetch(vineyardId: UUID, since: Date?) async throws -> [BackendTractor] {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        let q = provider.client.from("tractors").select().eq("vineyard_id", value: vineyardId.uuidString)
        if let since {
            return try await q.gte("updated_at", value: iso(since)).order("updated_at", ascending: true).execute().value
        }
        return try await q.order("updated_at", ascending: true).execute().value
    }

    func upsertMany(_ items: [BackendTractorUpsert]) async throws {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        guard !items.isEmpty else { return }
        try await provider.client.from("tractors").upsert(items, onConflict: "id").execute()
    }

    func softDelete(id: UUID) async throws {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        try await provider.client.rpc("soft_delete_tractor", params: SoftDeleteByIdRequest(id: id)).execute()
    }
}

// MARK: - Fuel Purchases

final class SupabaseFuelPurchaseSyncRepository: FuelPurchaseSyncRepositoryProtocol {
    private let provider: SupabaseClientProvider
    init(provider: SupabaseClientProvider = .shared) { self.provider = provider }

    func fetch(vineyardId: UUID, since: Date?) async throws -> [BackendFuelPurchase] {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        let q = provider.client.from("fuel_purchases").select().eq("vineyard_id", value: vineyardId.uuidString)
        if let since {
            return try await q.gte("updated_at", value: iso(since)).order("updated_at", ascending: true).execute().value
        }
        return try await q.order("updated_at", ascending: true).execute().value
    }

    func upsertMany(_ items: [BackendFuelPurchaseUpsert]) async throws {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        guard !items.isEmpty else { return }
        try await provider.client.from("fuel_purchases").upsert(items, onConflict: "id").execute()
    }

    func softDelete(id: UUID) async throws {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        try await provider.client.rpc("soft_delete_fuel_purchase", params: SoftDeleteByIdRequest(id: id)).execute()
    }
}

// MARK: - Operator Categories

final class SupabaseOperatorCategorySyncRepository: OperatorCategorySyncRepositoryProtocol {
    private let provider: SupabaseClientProvider
    init(provider: SupabaseClientProvider = .shared) { self.provider = provider }

    func fetch(vineyardId: UUID, since: Date?) async throws -> [BackendOperatorCategory] {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        let q = provider.client.from("operator_categories").select().eq("vineyard_id", value: vineyardId.uuidString)
        if let since {
            return try await q.gte("updated_at", value: iso(since)).order("updated_at", ascending: true).execute().value
        }
        return try await q.order("updated_at", ascending: true).execute().value
    }

    func upsertMany(_ items: [BackendOperatorCategoryUpsert]) async throws {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        guard !items.isEmpty else { return }
        try await provider.client.from("operator_categories").upsert(items, onConflict: "id").execute()
    }

    func softDelete(id: UUID) async throws {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        try await provider.client.rpc("soft_delete_operator_category", params: SoftDeleteByIdRequest(id: id)).execute()
    }
}
