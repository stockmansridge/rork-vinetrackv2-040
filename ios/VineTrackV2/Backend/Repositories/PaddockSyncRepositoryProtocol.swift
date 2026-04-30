import Foundation

protocol PaddockSyncRepositoryProtocol: Sendable {
    func fetchPaddocks(vineyardId: UUID, since: Date?) async throws -> [BackendPaddock]
    func fetchAllPaddocks(vineyardId: UUID) async throws -> [BackendPaddock]
    func upsertPaddock(_ paddock: BackendPaddockUpsert) async throws
    func upsertPaddocks(_ paddocks: [BackendPaddockUpsert]) async throws
    func softDeletePaddock(id: UUID) async throws
}
