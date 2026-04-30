import Foundation

nonisolated struct BackendVineyard: Identifiable, Codable, Sendable {
    let id: UUID
    let name: String
    let ownerId: UUID?
    let country: String?
    let logoPath: String?
    let logoUpdatedAt: Date?
    let createdAt: Date?
    let updatedAt: Date?
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case ownerId = "owner_id"
        case country
        case logoPath = "logo_path"
        case logoUpdatedAt = "logo_updated_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    nonisolated init(
        id: UUID,
        name: String,
        ownerId: UUID?,
        country: String?,
        logoPath: String?,
        logoUpdatedAt: Date? = nil,
        createdAt: Date?,
        updatedAt: Date?,
        deletedAt: Date?
    ) {
        self.id = id
        self.name = name
        self.ownerId = ownerId
        self.country = country
        self.logoPath = logoPath
        self.logoUpdatedAt = logoUpdatedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        ownerId = try c.decodeIfPresent(UUID.self, forKey: .ownerId)
        country = try c.decodeIfPresent(String.self, forKey: .country)
        logoPath = try c.decodeIfPresent(String.self, forKey: .logoPath)
        logoUpdatedAt = try c.decodeIfPresent(Date.self, forKey: .logoUpdatedAt)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
        deletedAt = try c.decodeIfPresent(Date.self, forKey: .deletedAt)
    }
}
