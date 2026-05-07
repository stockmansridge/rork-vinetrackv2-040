import Foundation

protocol PaddockSyncRepositoryProtocol: Sendable {
    func fetchPaddocks(vineyardId: UUID, since: Date?) async throws -> [BackendPaddock]
    func fetchAllPaddocks(vineyardId: UUID) async throws -> [BackendPaddock]
    /// Fetch every non-deleted paddock the current user can see across all
    /// vineyards (RLS gates the result). Used by the admin trip audit tool to
    /// resolve `paddock_id` -> `vineyard_id` across vineyards.
    func fetchAllAccessiblePaddocks() async throws -> [BackendPaddock]
    func upsertPaddock(_ paddock: BackendPaddockUpsert) async throws
    func upsertPaddocks(_ paddocks: [BackendPaddockUpsert]) async throws
    func softDeletePaddock(id: UUID) async throws
}
