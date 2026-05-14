import Foundation
import Supabase

final class SupabaseTeamRepository: TeamRepositoryProtocol {
    private let provider: SupabaseClientProvider

    init(provider: SupabaseClientProvider = .shared) {
        self.provider = provider
    }

    func listMembers(vineyardId: UUID) async throws -> [BackendVineyardMember] {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        return try await provider.client
            .from("vineyard_members")
            .select()
            .eq("vineyard_id", value: vineyardId.uuidString)
            .order("joined_at", ascending: true)
            .execute()
            .value
    }

    func updateMemberRole(vineyardId: UUID, userId: UUID, role: BackendRole) async throws {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        try await provider.client
            .from("vineyard_members")
            .update(MemberRoleUpdate(role: role))
            .eq("vineyard_id", value: vineyardId.uuidString)
            .eq("user_id", value: userId.uuidString)
            .execute()
    }

    func updateMemberOperatorCategory(vineyardId: UUID, userId: UUID, operatorCategoryId: UUID?) async throws {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        try await provider.client
            .from("vineyard_members")
            .update(MemberOperatorCategoryUpdate(operatorCategoryId: operatorCategoryId))
            .eq("vineyard_id", value: vineyardId.uuidString)
            .eq("user_id", value: userId.uuidString)
            .execute()
    }

    func removeMember(vineyardId: UUID, userId: UUID) async throws {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        try await provider.client
            .from("vineyard_members")
            .delete()
            .eq("vineyard_id", value: vineyardId.uuidString)
            .eq("user_id", value: userId.uuidString)
            .execute()
    }

    func inviteMember(vineyardId: UUID, email: String, role: BackendRole) async throws -> BackendInvitation {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Cancel any existing pending invitations for this email + vineyard to avoid duplicates.
        try? await provider.client
            .from("invitations")
            .update(InvitationStatusUpdate(status: "cancelled"))
            .eq("vineyard_id", value: vineyardId.uuidString)
            .eq("email", value: normalizedEmail)
            .eq("status", value: "pending")
            .execute()
        return try await provider.client
            .from("invitations")
            .insert(InvitationInsert(vineyardId: vineyardId, email: normalizedEmail, role: role))
            .select()
            .single()
            .execute()
            .value
    }

    func listPendingInvitations() async throws -> [BackendInvitation] {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        return try await provider.client
            .from("invitations")
            .select("*, vineyards(name)")
            .eq("status", value: "pending")
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func acceptInvitation(invitationId: UUID) async throws {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        try await ensureCurrentUserProfileExists()
        try await provider.client
            .rpc("accept_invitation", params: AcceptInvitationRequest(invitationId: invitationId))
            .execute()
    }

    private func ensureCurrentUserProfileExists() async throws {
        guard let user = provider.client.auth.currentUser else { throw BackendRepositoryError.missingAuthenticatedUser }
        try await provider.client
            .from("profiles")
            .upsert(InvitationAcceptanceProfileUpsert(id: user.id, email: user.email ?? ""))
            .execute()
    }

    func declineInvitation(invitationId: UUID) async throws {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        try await provider.client
            .rpc("decline_invitation", params: DeclineInvitationRequest(invitationId: invitationId))
            .execute()
    }

    func transferOwnership(vineyardId: UUID, newOwnerId: UUID, removeOldOwner: Bool) async throws {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        try await provider.client
            .rpc("transfer_vineyard_ownership", params: TransferOwnershipRequest(
                vineyardId: vineyardId,
                newOwnerId: newOwnerId,
                removeOldOwner: removeOldOwner
            ))
            .execute()
    }
}

nonisolated private struct TransferOwnershipRequest: Encodable, Sendable {
    let vineyardId: UUID
    let newOwnerId: UUID
    let removeOldOwner: Bool

    enum CodingKeys: String, CodingKey {
        case vineyardId = "p_vineyard_id"
        case newOwnerId = "p_new_owner_id"
        case removeOldOwner = "p_remove_old_owner"
    }
}

nonisolated private struct MemberRoleUpdate: Encodable, Sendable {
    let role: BackendRole
}

nonisolated private struct MemberOperatorCategoryUpdate: Encodable, Sendable {
    let operatorCategoryId: UUID?

    enum CodingKeys: String, CodingKey {
        case operatorCategoryId = "operator_category_id"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        // Always encode the key (even when nil) so we can clear the assignment.
        try c.encode(operatorCategoryId, forKey: .operatorCategoryId)
    }
}

nonisolated private struct InvitationInsert: Encodable, Sendable {
    let vineyardId: UUID
    let email: String
    let role: BackendRole

    enum CodingKeys: String, CodingKey {
        case vineyardId = "vineyard_id"
        case email
        case role
    }
}

nonisolated private struct InvitationStatusUpdate: Encodable, Sendable {
    let status: String
}

nonisolated private struct DeclineInvitationRequest: Encodable, Sendable {
    let invitationId: UUID

    enum CodingKeys: String, CodingKey {
        case invitationId = "p_invitation_id"
    }
}

nonisolated private struct InvitationAcceptanceProfileUpsert: Encodable, Sendable {
    let id: UUID
    let email: String
}

nonisolated private struct AcceptInvitationRequest: Encodable, Sendable {
    let invitationId: UUID

    enum CodingKeys: String, CodingKey {
        case invitationId = "p_invitation_id"
    }
}
