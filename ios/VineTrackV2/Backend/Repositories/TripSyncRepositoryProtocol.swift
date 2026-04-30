import Foundation

protocol TripSyncRepositoryProtocol: Sendable {
    func fetchTrips(vineyardId: UUID, since: Date?) async throws -> [BackendTrip]
    func fetchAllTrips(vineyardId: UUID) async throws -> [BackendTrip]
    func upsertTrip(_ trip: BackendTripUpsert) async throws
    func upsertTrips(_ trips: [BackendTripUpsert]) async throws
    func softDeleteTrip(id: UUID) async throws
}
