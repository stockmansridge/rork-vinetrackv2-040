import Foundation

nonisolated struct BackendInvitation: Identifiable, Codable, Sendable {
    let id: UUID
    let vineyardId: UUID
    let email: String
    let role: BackendRole
    let status: String
    let invitedBy: UUID?
    let expiresAt: Date?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case vineyardId = "vineyard_id"
        case email
        case role
        case status
        case invitedBy = "invited_by"
        case expiresAt = "expires_at"
        case createdAt = "created_at"
    }
}
