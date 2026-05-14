import Foundation

nonisolated struct BackendVineyardMember: Identifiable, Codable, Sendable {
    let id: UUID?
    let vineyardId: UUID
    let userId: UUID
    let role: BackendRole
    let displayName: String?
    let joinedAt: Date?
    /// Default operator category assigned to this member. Used as a fallback
    /// for trip cost calculations when `trips.operator_category_id` is null.
    /// Synced as `vineyard_members.operator_category_id` (see
    /// `sql/057_trips_costing_links.sql`).
    let operatorCategoryId: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case vineyardId = "vineyard_id"
        case userId = "user_id"
        case role
        case displayName = "display_name"
        case joinedAt = "joined_at"
        case operatorCategoryId = "operator_category_id"
    }
}
