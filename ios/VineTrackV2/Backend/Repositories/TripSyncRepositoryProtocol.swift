import Foundation

protocol TripSyncRepositoryProtocol: Sendable {
    func fetchTrips(vineyardId: UUID, since: Date?) async throws -> [BackendTrip]
    func fetchAllTrips(vineyardId: UUID) async throws -> [BackendTrip]
    /// Fetch every non-deleted trip the current user can see across all
    /// vineyards (RLS gates the result). Used by the admin trip audit tool.
    func fetchAllAccessibleTrips() async throws -> [BackendTrip]
    func upsertTrip(_ trip: BackendTripUpsert) async throws
    func upsertTrips(_ trips: [BackendTripUpsert]) async throws
    /// Patch a trip's `vineyard_id` (and optional scalar `paddock_id`) without
    /// having to send a full upsert payload. Used by the admin trip audit tool.
    func updateTripVineyardAssignment(id: UUID, vineyardId: UUID, paddockId: UUID?) async throws
    func softDeleteTrip(id: UUID) async throws
}
