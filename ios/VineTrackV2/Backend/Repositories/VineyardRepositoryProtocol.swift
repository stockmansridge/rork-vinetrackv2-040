import Foundation

protocol VineyardRepositoryProtocol: Sendable {
    func listMyVineyards() async throws -> [BackendVineyard]
    /// List every vineyard the current user can see, optionally including
    /// soft-deleted ones (RLS gates the result). Used by the admin trip audit.
    func listAllAccessibleVineyards(includeDeleted: Bool) async throws -> [BackendVineyard]
    func createVineyard(name: String, country: String?) async throws -> BackendVineyard
    func updateVineyard(_ vineyard: BackendVineyard) async throws
    func updateVineyardLogoPath(vineyardId: UUID, logoPath: String?) async throws -> Date?
    func softDeleteVineyard(id: UUID) async throws
    func archiveVineyard(id: UUID) async throws
    func accountDeletionPreflight() async throws -> AccountDeletionPreflight
    func submitAccountDeletionRequest(reason: String?) async throws -> AccountDeletionRequestResult
}

nonisolated struct AccountDeletionPreflight: Decodable, Sendable {
    let ownedVineyards: [OwnedVineyard]
    let blockerCount: Int
    let safeToDelete: Bool

    nonisolated struct OwnedVineyard: Decodable, Sendable, Identifiable {
        let vineyardId: UUID
        let vineyardName: String
        let otherActiveMembers: Int
        let transferRequired: Bool

        var id: UUID { vineyardId }

        enum CodingKeys: String, CodingKey {
            case vineyardId = "vineyard_id"
            case vineyardName = "vineyard_name"
            case otherActiveMembers = "other_active_members"
            case transferRequired = "transfer_required"
        }
    }

    enum CodingKeys: String, CodingKey {
        case ownedVineyards = "owned_vineyards"
        case blockerCount = "blocker_count"
        case safeToDelete = "safe_to_delete"
    }
}

nonisolated struct AccountDeletionRequestResult: Decodable, Sendable {
    let submitted: Bool
    let blockerCount: Int?
    let message: String?
    let requestId: UUID?

    enum CodingKeys: String, CodingKey {
        case submitted
        case blockerCount = "blocker_count"
        case message
        case requestId = "request_id"
    }
}
