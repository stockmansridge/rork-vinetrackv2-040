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

nonisolated struct AdminUserRow: Identifiable, Sendable {
    let id: UUID
    let email: String
    let fullName: String?
    let createdAt: Date?
    let updatedAt: Date?
    let vineyardCount: Int

    var displayName: String {
        if let name = fullName, !name.trimmingCharacters(in: .whitespaces).isEmpty {
            return name
        }
        return email
    }
}

final class SupabaseAdminRepository {
    private let provider: SupabaseClientProvider

    init(provider: SupabaseClientProvider = .shared) {
        self.provider = provider
    }

    func fetchEngagementSummary() async throws -> AdminEngagementSummary {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }

        let now = Date()
        let last7 = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
        let last30 = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        async let usersTask = countRows(table: "profiles")
        async let vineyardsTask = countRows(table: "vineyards", filter: { $0.is("deleted_at", value: nil) })
        async let pinsTask = countRows(table: "pins")
        async let spraysTask = countRows(table: "spray_records")
        async let tasksTask = countRows(table: "work_tasks")
        async let signed7Task = countRows(table: "profiles", filter: { $0.gte("updated_at", value: iso.string(from: last7)) })
        async let signed30Task = countRows(table: "profiles", filter: { $0.gte("updated_at", value: iso.string(from: last30)) })
        async let new30Task = countRows(table: "profiles", filter: { $0.gte("created_at", value: iso.string(from: last30)) })
        async let pendingTask = countRows(table: "invitations", filter: { $0.eq("status", value: "pending") })

        return try await AdminEngagementSummary(
            totalUsers: usersTask,
            totalVineyards: vineyardsTask,
            totalPins: pinsTask,
            totalSprayRecords: spraysTask,
            totalWorkTasks: tasksTask,
            signedInLast7Days: signed7Task,
            signedInLast30Days: signed30Task,
            newUsersLast30Days: new30Task,
            pendingInvitations: pendingTask
        )
    }

    func fetchAllUsers(limit: Int = 200) async throws -> [AdminUserRow] {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }

        let profiles: [BackendProfile] = try await provider.client
            .from("profiles")
            .select()
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value

        let memberships: [VineyardMemberRow] = (try? await provider.client
            .from("vineyard_members")
            .select("user_id")
            .execute()
            .value) ?? []

        var membershipCounts: [UUID: Int] = [:]
        for row in memberships {
            membershipCounts[row.userId, default: 0] += 1
        }

        return profiles.map { p in
            AdminUserRow(
                id: p.id,
                email: p.email,
                fullName: p.fullName,
                createdAt: p.createdAt,
                updatedAt: p.updatedAt,
                vineyardCount: membershipCounts[p.id] ?? 0
            )
        }
    }

    private func countRows(
        table: String,
        filter: ((PostgrestFilterBuilder) -> PostgrestFilterBuilder)? = nil
    ) async -> Int {
        do {
            var query = provider.client.from(table).select("*", head: true, count: .exact)
            if let filter {
                query = filter(query)
            }
            let response = try await query.execute()
            return response.count ?? 0
        } catch {
            return 0
        }
    }
}

nonisolated private struct VineyardMemberRow: Decodable, Sendable {
    let userId: UUID

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
    }
}
