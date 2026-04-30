import Foundation
import Supabase

private nonisolated struct OpsSoftDeleteByIdRequest: Encodable, Sendable {
    let id: UUID
    enum CodingKeys: String, CodingKey { case id = "p_id" }
}

private func opsIso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }

// MARK: - Work Tasks

final class SupabaseWorkTaskSyncRepository: WorkTaskSyncRepositoryProtocol {
    private let provider: SupabaseClientProvider
    init(provider: SupabaseClientProvider = .shared) { self.provider = provider }

    func fetch(vineyardId: UUID, since: Date?) async throws -> [BackendWorkTask] {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        let q = provider.client.from("work_tasks").select().eq("vineyard_id", value: vineyardId.uuidString)
        if let since {
            return try await q.gte("updated_at", value: opsIso(since)).order("updated_at", ascending: true).execute().value
        }
        return try await q.order("updated_at", ascending: true).execute().value
    }

    func upsertMany(_ items: [BackendWorkTaskUpsert]) async throws {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        guard !items.isEmpty else { return }
        try await provider.client.from("work_tasks").upsert(items, onConflict: "id").execute()
    }

    func softDelete(id: UUID) async throws {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        try await provider.client.rpc("soft_delete_work_task", params: OpsSoftDeleteByIdRequest(id: id)).execute()
    }
}

// MARK: - Maintenance Logs

final class SupabaseMaintenanceLogSyncRepository: MaintenanceLogSyncRepositoryProtocol {
    private let provider: SupabaseClientProvider
    init(provider: SupabaseClientProvider = .shared) { self.provider = provider }

    func fetch(vineyardId: UUID, since: Date?) async throws -> [BackendMaintenanceLog] {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        let q = provider.client.from("maintenance_logs").select().eq("vineyard_id", value: vineyardId.uuidString)
        if let since {
            return try await q.gte("updated_at", value: opsIso(since)).order("updated_at", ascending: true).execute().value
        }
        return try await q.order("updated_at", ascending: true).execute().value
    }

    func upsertMany(_ items: [BackendMaintenanceLogUpsert]) async throws {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        guard !items.isEmpty else { return }
        try await provider.client.from("maintenance_logs").upsert(items, onConflict: "id").execute()
    }

    func softDelete(id: UUID) async throws {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        try await provider.client.rpc("soft_delete_maintenance_log", params: OpsSoftDeleteByIdRequest(id: id)).execute()
    }
}

// MARK: - Yield Estimation Sessions

final class SupabaseYieldEstimationSessionSyncRepository: YieldEstimationSessionSyncRepositoryProtocol {
    private let provider: SupabaseClientProvider
    init(provider: SupabaseClientProvider = .shared) { self.provider = provider }

    func fetch(vineyardId: UUID, since: Date?) async throws -> [BackendYieldEstimationSession] {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        let q = provider.client.from("yield_estimation_sessions").select().eq("vineyard_id", value: vineyardId.uuidString)
        if let since {
            return try await q.gte("updated_at", value: opsIso(since)).order("updated_at", ascending: true).execute().value
        }
        return try await q.order("updated_at", ascending: true).execute().value
    }

    func upsertMany(_ items: [BackendYieldEstimationSessionUpsert]) async throws {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        guard !items.isEmpty else { return }
        try await provider.client.from("yield_estimation_sessions").upsert(items, onConflict: "id").execute()
    }

    func softDelete(id: UUID) async throws {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        try await provider.client.rpc("soft_delete_yield_estimation_session", params: OpsSoftDeleteByIdRequest(id: id)).execute()
    }
}

// MARK: - Damage Records

final class SupabaseDamageRecordSyncRepository: DamageRecordSyncRepositoryProtocol {
    private let provider: SupabaseClientProvider
    init(provider: SupabaseClientProvider = .shared) { self.provider = provider }

    func fetch(vineyardId: UUID, since: Date?) async throws -> [BackendDamageRecord] {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        let q = provider.client.from("damage_records").select().eq("vineyard_id", value: vineyardId.uuidString)
        if let since {
            return try await q.gte("updated_at", value: opsIso(since)).order("updated_at", ascending: true).execute().value
        }
        return try await q.order("updated_at", ascending: true).execute().value
    }

    func upsertMany(_ items: [BackendDamageRecordUpsert]) async throws {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        guard !items.isEmpty else { return }
        try await provider.client.from("damage_records").upsert(items, onConflict: "id").execute()
    }

    func softDelete(id: UUID) async throws {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        try await provider.client.rpc("soft_delete_damage_record", params: OpsSoftDeleteByIdRequest(id: id)).execute()
    }
}

// MARK: - Historical Yield Records

final class SupabaseHistoricalYieldRecordSyncRepository: HistoricalYieldRecordSyncRepositoryProtocol {
    private let provider: SupabaseClientProvider
    init(provider: SupabaseClientProvider = .shared) { self.provider = provider }

    func fetch(vineyardId: UUID, since: Date?) async throws -> [BackendHistoricalYieldRecord] {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        let q = provider.client.from("historical_yield_records").select().eq("vineyard_id", value: vineyardId.uuidString)
        if let since {
            return try await q.gte("updated_at", value: opsIso(since)).order("updated_at", ascending: true).execute().value
        }
        return try await q.order("updated_at", ascending: true).execute().value
    }

    func upsertMany(_ items: [BackendHistoricalYieldRecordUpsert]) async throws {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        guard !items.isEmpty else { return }
        try await provider.client.from("historical_yield_records").upsert(items, onConflict: "id").execute()
    }

    func softDelete(id: UUID) async throws {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        try await provider.client.rpc("soft_delete_historical_yield_record", params: OpsSoftDeleteByIdRequest(id: id)).execute()
    }
}
