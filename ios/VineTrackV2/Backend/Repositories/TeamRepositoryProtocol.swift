import Foundation

protocol TeamRepositoryProtocol: Sendable {
    func listMembers(vineyardId: UUID) async throws -> [BackendVineyardMember]
    func updateMemberRole(vineyardId: UUID, userId: UUID, role: BackendRole) async throws
    func removeMember(vineyardId: UUID, userId: UUID) async throws
    func inviteMember(vineyardId: UUID, email: String, role: BackendRole) async throws -> BackendInvitation
    func listPendingInvitations() async throws -> [BackendInvitation]
    func acceptInvitation(invitationId: UUID) async throws
    func declineInvitation(invitationId: UUID) async throws
}
