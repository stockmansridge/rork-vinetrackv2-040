import Foundation
import Supabase

nonisolated struct AdminEngagementSummary: Sendable {
    let totalUsers: Int
    let totalVineyards: Int
    let totalPins: Int
    let totalSprayRecords: Int
    let totalWorkTasks: Int
    let signedInLast7Days: Int
    let signedInLast30Days: Int
    let newUsersLast30Days: Int
    let pendingInvitations: Int
}

nonisolated struct AdminUserRow: Identifiable, Sendable, Hashable {
    let id: UUID
    let email: String
    let fullName: String?
    let createdAt: Date?
    let updatedAt: Date?
    let lastSignInAt: Date?
    let vineyardCount: Int
    let ownedCount: Int
    let blockCount: Int

    var displayName: String {
        if let name = fullName, !name.trimmingCharacters(in: .whitespaces).isEmpty {
            return name
        }
        return email
    }
}

nonisolated struct AdminVineyardRow: Identifiable, Sendable, Hashable {
    let id: UUID
    let name: String
    let ownerId: UUID?
    let ownerEmail: String?
    let ownerFullName: String?
    let country: String?
    let createdAt: Date?
    let deletedAt: Date?
    let memberCount: Int
    let pendingInvites: Int

    var ownerDisplay: String {
        if let n = ownerFullName, !n.trimmingCharacters(in: .whitespaces).isEmpty { return n }
        return ownerEmail ?? "—"
    }
}

nonisolated struct AdminUserVineyardRow: Identifiable, Sendable, Hashable {
    let id: UUID
    let name: String
    let role: String?
    let isOwner: Bool
    let country: String?
    let createdAt: Date?
    let deletedAt: Date?
    let memberCount: Int
}

nonisolated struct AdminInvitationRow: Identifiable, Sendable, Hashable {
    let id: UUID
    let email: String
    let role: String
    let status: String
    let vineyardId: UUID?
    let vineyardName: String?
    let invitedBy: UUID?
    let invitedByEmail: String?
    let createdAt: Date?
    let expiresAt: Date?
}

nonisolated struct AdminPinRow: Identifiable, Sendable, Hashable {
    let id: UUID
    let vineyardId: UUID?
    let vineyardName: String?
    let title: String
    let category: String?
    let status: String?
    let createdAt: Date?
    let isCompleted: Bool
}

nonisolated struct AdminSprayRow: Identifiable, Sendable, Hashable {
    let id: UUID
    let vineyardId: UUID?
    let vineyardName: String?
    let sprayReference: String?
    let operationType: String?
    let date: Date?
    let createdAt: Date?
}

nonisolated struct AdminWorkTaskRow: Identifiable, Sendable, Hashable {
    let id: UUID
    let vineyardId: UUID?
    let vineyardName: String?
    let taskType: String?
    let paddockName: String?
    let date: Date?
    let durationHours: Double?
    let createdAt: Date?
}

nonisolated struct AdminVineyardPaddockRow: Identifiable, Sendable, Hashable {
    let id: UUID
    let vineyardId: UUID
    let name: String
    let polygonPoints: [CoordinatePoint]
    let rows: [PaddockRow]
    let rowCount: Int
    let rowDirection: Double?
    let rowWidth: Double?
    let vineSpacing: Double?
    let createdAt: Date?
    let updatedAt: Date?
    let deletedAt: Date?
}

// MARK: - DTOs

nonisolated private struct EngagementDTO: Decodable, Sendable {
    let totalUsers: Int
    let totalVineyards: Int
    let totalPins: Int
    let totalSprayRecords: Int
    let totalWorkTasks: Int
    let signedInLast7Days: Int
    let signedInLast30Days: Int
    let newUsersLast30Days: Int
    let pendingInvitations: Int

    enum CodingKeys: String, CodingKey {
        case totalUsers = "total_users"
        case totalVineyards = "total_vineyards"
        case totalPins = "total_pins"
        case totalSprayRecords = "total_spray_records"
        case totalWorkTasks = "total_work_tasks"
        case signedInLast7Days = "signed_in_last_7_days"
        case signedInLast30Days = "signed_in_last_30_days"
        case newUsersLast30Days = "new_users_last_30_days"
        case pendingInvitations = "pending_invitations"
    }
}

nonisolated private struct UserDTO: Decodable, Sendable {
    let id: UUID
    let email: String
    let fullName: String?
    let createdAt: Date?
    let updatedAt: Date?
    let lastSignInAt: Date?
    let vineyardCount: Int
    let ownedCount: Int
    let blockCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, email
        case fullName = "full_name"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case lastSignInAt = "last_sign_in_at"
        case vineyardCount = "vineyard_count"
        case ownedCount = "owned_count"
        case blockCount = "block_count"
    }
}

nonisolated private struct VineyardDTO: Decodable, Sendable {
    let id: UUID
    let name: String
    let ownerId: UUID?
    let ownerEmail: String?
    let ownerFullName: String?
    let country: String?
    let createdAt: Date?
    let deletedAt: Date?
    let memberCount: Int
    let pendingInvites: Int

    enum CodingKeys: String, CodingKey {
        case id, name, country
        case ownerId = "owner_id"
        case ownerEmail = "owner_email"
        case ownerFullName = "owner_full_name"
        case createdAt = "created_at"
        case deletedAt = "deleted_at"
        case memberCount = "member_count"
        case pendingInvites = "pending_invites"
    }
}

nonisolated private struct UserVineyardDTO: Decodable, Sendable {
    let id: UUID
    let name: String
    let role: String?
    let isOwner: Bool
    let country: String?
    let createdAt: Date?
    let deletedAt: Date?
    let memberCount: Int

    enum CodingKeys: String, CodingKey {
        case id, name, role, country
        case isOwner = "is_owner"
        case createdAt = "created_at"
        case deletedAt = "deleted_at"
        case memberCount = "member_count"
    }
}

nonisolated private struct InvitationDTO: Decodable, Sendable {
    let id: UUID
    let email: String
    let role: String
    let status: String
    let vineyardId: UUID?
    let vineyardName: String?
    let invitedBy: UUID?
    let invitedByEmail: String?
    let createdAt: Date?
    let expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, email, role, status
        case vineyardId = "vineyard_id"
        case vineyardName = "vineyard_name"
        case invitedBy = "invited_by"
        case invitedByEmail = "invited_by_email"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
    }
}

nonisolated private struct PinDTO: Decodable, Sendable {
    let id: UUID
    let vineyardId: UUID?
    let vineyardName: String?
    let title: String
    let category: String?
    let status: String?
    let createdAt: Date?
    let isCompleted: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, category, status
        case vineyardId = "vineyard_id"
        case vineyardName = "vineyard_name"
        case createdAt = "created_at"
        case isCompleted = "is_completed"
    }
}

nonisolated private struct SprayDTO: Decodable, Sendable {
    let id: UUID
    let vineyardId: UUID?
    let vineyardName: String?
    let sprayReference: String?
    let operationType: String?
    let date: Date?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, date
        case vineyardId = "vineyard_id"
        case vineyardName = "vineyard_name"
        case sprayReference = "spray_reference"
        case operationType = "operation_type"
        case createdAt = "created_at"
    }
}

nonisolated private struct WorkTaskDTO: Decodable, Sendable {
    let id: UUID
    let vineyardId: UUID?
    let vineyardName: String?
    let taskType: String?
    let paddockName: String?
    let date: Date?
    let durationHours: Double?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, date
        case vineyardId = "vineyard_id"
        case vineyardName = "vineyard_name"
        case taskType = "task_type"
        case paddockName = "paddock_name"
        case durationHours = "duration_hours"
        case createdAt = "created_at"
    }
}

nonisolated private struct VineyardPaddockDTO: Decodable, Sendable {
    let id: UUID
    let vineyardId: UUID
    let name: String
    let polygonPoints: [CoordinatePoint]?
    let rows: [PaddockRow]?
    let rowCount: Int?
    let rowDirection: Double?
    let rowWidth: Double?
    let vineSpacing: Double?
    let createdAt: Date?
    let updatedAt: Date?
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, rows
        case vineyardId = "vineyard_id"
        case polygonPoints = "polygon_points"
        case rowCount = "row_count"
        case rowDirection = "row_direction"
        case rowWidth = "row_width"
        case vineSpacing = "vine_spacing"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }
}

nonisolated private struct VineyardIdParams: Encodable, Sendable {
    let vineyardId: UUID
    enum CodingKeys: String, CodingKey { case vineyardId = "p_vineyard_id" }
}

nonisolated private struct EmptyParams: Encodable, Sendable {}

nonisolated private struct UserIdParams: Encodable, Sendable {
    let userId: UUID
    enum CodingKeys: String, CodingKey { case userId = "p_user_id" }
}

nonisolated private struct LimitParams: Encodable, Sendable {
    let limit: Int
    enum CodingKeys: String, CodingKey { case limit = "p_limit" }
}

final class SupabaseAdminRepository {
    private let provider: SupabaseClientProvider

    init(provider: SupabaseClientProvider = .shared) {
        self.provider = provider
    }

    func fetchEngagementSummary() async throws -> AdminEngagementSummary {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        let rows: [EngagementDTO] = try await provider.client
            .rpc("admin_engagement_summary")
            .execute()
            .value
        guard let r = rows.first else {
            return AdminEngagementSummary(totalUsers: 0, totalVineyards: 0, totalPins: 0, totalSprayRecords: 0, totalWorkTasks: 0, signedInLast7Days: 0, signedInLast30Days: 0, newUsersLast30Days: 0, pendingInvitations: 0)
        }
        return AdminEngagementSummary(
            totalUsers: r.totalUsers,
            totalVineyards: r.totalVineyards,
            totalPins: r.totalPins,
            totalSprayRecords: r.totalSprayRecords,
            totalWorkTasks: r.totalWorkTasks,
            signedInLast7Days: r.signedInLast7Days,
            signedInLast30Days: r.signedInLast30Days,
            newUsersLast30Days: r.newUsersLast30Days,
            pendingInvitations: r.pendingInvitations
        )
    }

    func fetchAllUsers() async throws -> [AdminUserRow] {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        let rows: [UserDTO] = try await provider.client
            .rpc("admin_list_users")
            .execute()
            .value
        return rows.map {
            AdminUserRow(
                id: $0.id,
                email: $0.email,
                fullName: $0.fullName,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt,
                lastSignInAt: $0.lastSignInAt,
                vineyardCount: $0.vineyardCount,
                ownedCount: $0.ownedCount,
                blockCount: $0.blockCount ?? 0
            )
        }
    }

    func fetchAllVineyards() async throws -> [AdminVineyardRow] {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        let rows: [VineyardDTO] = try await provider.client
            .rpc("admin_list_vineyards")
            .execute()
            .value
        return rows.map {
            AdminVineyardRow(
                id: $0.id, name: $0.name,
                ownerId: $0.ownerId, ownerEmail: $0.ownerEmail, ownerFullName: $0.ownerFullName,
                country: $0.country, createdAt: $0.createdAt, deletedAt: $0.deletedAt,
                memberCount: $0.memberCount, pendingInvites: $0.pendingInvites
            )
        }
    }

    func fetchUserVineyards(userId: UUID) async throws -> [AdminUserVineyardRow] {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        let rows: [UserVineyardDTO] = try await provider.client
            .rpc("admin_list_user_vineyards", params: UserIdParams(userId: userId))
            .execute()
            .value
        return rows.map {
            AdminUserVineyardRow(
                id: $0.id, name: $0.name, role: $0.role, isOwner: $0.isOwner,
                country: $0.country, createdAt: $0.createdAt, deletedAt: $0.deletedAt,
                memberCount: $0.memberCount
            )
        }
    }

    func fetchInvitations() async throws -> [AdminInvitationRow] {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        let rows: [InvitationDTO] = try await provider.client
            .rpc("admin_list_invitations")
            .execute()
            .value
        return rows.map {
            AdminInvitationRow(
                id: $0.id, email: $0.email, role: $0.role, status: $0.status,
                vineyardId: $0.vineyardId, vineyardName: $0.vineyardName,
                invitedBy: $0.invitedBy, invitedByEmail: $0.invitedByEmail,
                createdAt: $0.createdAt, expiresAt: $0.expiresAt
            )
        }
    }

    func fetchPins(limit: Int = 500) async throws -> [AdminPinRow] {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        let rows: [PinDTO] = try await provider.client
            .rpc("admin_list_pins", params: LimitParams(limit: limit))
            .execute()
            .value
        return rows.map {
            AdminPinRow(
                id: $0.id, vineyardId: $0.vineyardId, vineyardName: $0.vineyardName,
                title: $0.title, category: $0.category, status: $0.status,
                createdAt: $0.createdAt, isCompleted: $0.isCompleted
            )
        }
    }

    func fetchSprayRecords(limit: Int = 500) async throws -> [AdminSprayRow] {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        let rows: [SprayDTO] = try await provider.client
            .rpc("admin_list_spray_records", params: LimitParams(limit: limit))
            .execute()
            .value
        return rows.map {
            AdminSprayRow(
                id: $0.id, vineyardId: $0.vineyardId, vineyardName: $0.vineyardName,
                sprayReference: $0.sprayReference, operationType: $0.operationType,
                date: $0.date, createdAt: $0.createdAt
            )
        }
    }

    func fetchVineyardPaddocks(vineyardId: UUID) async throws -> [AdminVineyardPaddockRow] {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        let rows: [VineyardPaddockDTO] = try await provider.client
            .rpc("admin_list_vineyard_paddocks", params: VineyardIdParams(vineyardId: vineyardId))
            .execute()
            .value
        return rows.map {
            AdminVineyardPaddockRow(
                id: $0.id,
                vineyardId: $0.vineyardId,
                name: $0.name,
                polygonPoints: $0.polygonPoints ?? [],
                rows: $0.rows ?? [],
                rowCount: $0.rowCount ?? ($0.rows?.count ?? 0),
                rowDirection: $0.rowDirection,
                rowWidth: $0.rowWidth,
                vineSpacing: $0.vineSpacing,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt,
                deletedAt: $0.deletedAt
            )
        }
    }

    /// Fetches paddocks across every vineyard the current admin can access.
    /// Issues one call per vineyard in parallel. Annotates rows with vineyard name
    /// for display in admin lists.
    func fetchAllPaddocks() async throws -> [(vineyard: AdminVineyardRow, paddock: AdminVineyardPaddockRow)] {
        let vineyards = try await fetchAllVineyards()
        let byId: [UUID: AdminVineyardRow] = Dictionary(uniqueKeysWithValues: vineyards.map { ($0.id, $0) })
        var results: [(AdminVineyardRow, AdminVineyardPaddockRow)] = []
        try await withThrowingTaskGroup(of: [AdminVineyardPaddockRow].self) { group in
            for v in vineyards where v.deletedAt == nil {
                let vid = v.id
                group.addTask { try await self.fetchVineyardPaddocks(vineyardId: vid) }
            }
            for try await rows in group {
                for r in rows {
                    if let v = byId[r.vineyardId] {
                        results.append((v, r))
                    }
                }
            }
        }
        results.sort { lhs, rhs in
            if lhs.0.name.lowercased() == rhs.0.name.lowercased() {
                return lhs.1.name.lowercased() < rhs.1.name.lowercased()
            }
            return lhs.0.name.lowercased() < rhs.0.name.lowercased()
        }
        return results
    }

    func fetchWorkTasks(limit: Int = 500) async throws -> [AdminWorkTaskRow] {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        let rows: [WorkTaskDTO] = try await provider.client
            .rpc("admin_list_work_tasks", params: LimitParams(limit: limit))
            .execute()
            .value
        return rows.map {
            AdminWorkTaskRow(
                id: $0.id, vineyardId: $0.vineyardId, vineyardName: $0.vineyardName,
                taskType: $0.taskType, paddockName: $0.paddockName,
                date: $0.date, durationHours: $0.durationHours, createdAt: $0.createdAt
            )
        }
    }
}
