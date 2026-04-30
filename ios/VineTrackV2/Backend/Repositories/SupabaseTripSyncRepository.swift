import Foundation
import Supabase

final class SupabaseTripSyncRepository: TripSyncRepositoryProtocol {
    private let provider: SupabaseClientProvider

    init(provider: SupabaseClientProvider = .shared) {
        self.provider = provider
    }

    func fetchTrips(vineyardId: UUID, since: Date?) async throws -> [BackendTrip] {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        let query = provider.client
            .from("trips")
            .select()
            .eq("vineyard_id", value: vineyardId.uuidString)
        if let since {
            return try await query
                .gte("updated_at", value: ISO8601DateFormatter().string(from: since))
                .order("updated_at", ascending: true)
                .execute()
                .value
        } else {
            return try await query
                .order("updated_at", ascending: true)
                .execute()
                .value
        }
    }

    func fetchAllTrips(vineyardId: UUID) async throws -> [BackendTrip] {
        try await fetchTrips(vineyardId: vineyardId, since: nil)
    }

    func upsertTrip(_ trip: BackendTripUpsert) async throws {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        try await provider.client
            .from("trips")
            .upsert(trip, onConflict: "id")
            .execute()
    }

    func upsertTrips(_ trips: [BackendTripUpsert]) async throws {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        guard !trips.isEmpty else { return }
        try await provider.client
            .from("trips")
            .upsert(trips, onConflict: "id")
            .execute()
    }

    func softDeleteTrip(id: UUID) async throws {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        try await provider.client
            .rpc("soft_delete_trip", params: SoftDeleteTripRequest(tripId: id))
            .execute()
    }
}

nonisolated private struct SoftDeleteTripRequest: Encodable, Sendable {
    let tripId: UUID

    enum CodingKeys: String, CodingKey {
        case tripId = "p_trip_id"
    }
}
