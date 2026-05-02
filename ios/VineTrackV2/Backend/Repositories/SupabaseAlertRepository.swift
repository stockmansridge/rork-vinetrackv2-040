import Foundation
import Supabase

final class SupabaseAlertRepository: AlertRepositoryProtocol {
    private let provider: SupabaseClientProvider

    init(provider: SupabaseClientProvider = .shared) {
        self.provider = provider
    }

    func fetchAlerts(vineyardId: UUID) async throws -> [BackendAlert] {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        let nowIso = ISO8601DateFormatter().string(from: Date())
        return try await provider.client
            .from("vineyard_alerts")
            .select()
            .eq("vineyard_id", value: vineyardId.uuidString)
            .or("expires_at.is.null,expires_at.gt.\(nowIso)")
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func fetchUserStatus(alertIds: [UUID]) async throws -> [BackendAlertUserStatus] {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        guard !alertIds.isEmpty else { return [] }
        let ids = alertIds.map { $0.uuidString }
        return try await provider.client
            .from("vineyard_alert_user_status")
            .select()
            .in("alert_id", values: ids)
            .execute()
            .value
    }

    func upsertAlerts(_ alerts: [BackendAlertUpsert]) async throws {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        guard !alerts.isEmpty else { return }
        try await provider.client
            .from("vineyard_alerts")
            .upsert(alerts, onConflict: "vineyard_id,dedup_key")
            .execute()
    }

    func deleteAlert(id: UUID) async throws {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        try await provider.client
            .from("vineyard_alerts")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }

    func markStatus(alertId: UUID, read: Bool?, dismissed: Bool?) async throws {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        try await provider.client
            .rpc("mark_vineyard_alert_status", params: MarkStatusRequest(
                pAlertId: alertId,
                pRead: read,
                pDismissed: dismissed
            ))
            .execute()
    }

    func fetchPreferences(vineyardId: UUID) async throws -> BackendAlertPreferences? {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        let rows: [BackendAlertPreferences] = try await provider.client
            .from("vineyard_alert_preferences")
            .select()
            .eq("vineyard_id", value: vineyardId.uuidString)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    func upsertPreferences(_ preferences: BackendAlertPreferences) async throws {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        try await provider.client
            .from("vineyard_alert_preferences")
            .upsert(preferences, onConflict: "vineyard_id")
            .execute()
    }
}

nonisolated private struct MarkStatusRequest: Encodable, Sendable {
    let pAlertId: UUID
    let pRead: Bool?
    let pDismissed: Bool?

    enum CodingKeys: String, CodingKey {
        case pAlertId = "p_alert_id"
        case pRead = "p_read"
        case pDismissed = "p_dismissed"
    }
}
