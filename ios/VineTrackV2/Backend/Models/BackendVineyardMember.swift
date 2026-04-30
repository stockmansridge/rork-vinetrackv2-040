import Foundation

nonisolated struct BackendVineyardMember: Identifiable, Codable, Sendable {
    let id: UUID?
    let vineyardId: UUID
    let userId: UUID
    let role: BackendRole
    let displayName: String?
    let joinedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case vineyardId = "vineyard_id"
        case userId = "user_id"
        case role
        case displayName = "display_name"
        case joinedAt = "joined_at"
    }
}
