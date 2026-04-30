import SwiftUI

struct BackendTeamAccessView: View {
    let vineyardId: UUID
    let vineyardName: String

    @Environment(NewBackendAuthService.self) private var auth
    @State private var members: [BackendVineyardMember] = []
    @State private var pendingInvitations: [BackendInvitation] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var showInviteSheet: Bool = false
    @State private var memberToEdit: BackendVineyardMember?
    @State private var showEditMember: Bool = false

    private let teamRepository: any TeamRepositoryProtocol = SupabaseTeamRepository()

    private var currentUserMember: BackendVineyardMember? {
        guard let userId = auth.userId else { return nil }
        return members.first { $0.userId == userId }
    }

    private var canManage: Bool {
        currentUserMember?.role.canInviteMembers ?? false
    }

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section {
                if members.isEmpty && !isLoading {
                    Text("No members yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(members, id: \.userId) { member in
                        memberRow(member)
                    }
                }
            } header: {
                HStack {
                    Text("Members")
                    Spacer()
                    if isLoading {
                        ProgressView().controlSize(.small)
                    }
                }
            }

            if !pendingInvitations.isEmpty {
                Section("Pending Invitations") {
                    ForEach(pendingInvitations, id: \.id) { invitation in
                        invitationRow(invitation)
                    }
                }
            }

            Section {
                NavigationLink {
                    RolesPermissionsInfoView()
                } label: {
                    Label("Roles & Permissions", systemImage: "person.badge.shield.checkmark.fill")
                }
            }
        }
        .navigationTitle("Team & Access")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canManage {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showInviteSheet = true
                    } label: {
                        Image(systemName: "person.badge.plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showInviteSheet) {
            BackendInviteMemberSheet(vineyardId: vineyardId, vineyardName: vineyardName) {
                Task { await reload() }
            }
        }
        .sheet(isPresented: $showEditMember) {
            if let member = memberToEdit {
                EditMemberRoleSheet(
                    member: member,
                    canManage: canManage,
                    onSave: { newRole in
                        showEditMember = false
                        Task { await updateRole(member: member, newRole: newRole) }
                    },
                    onRemove: {
                        showEditMember = false
                        Task { await removeMember(member) }
                    }
                )
            }
        }
        .refreshable { await reload() }
        .task { await reload() }
    }

    private func memberRow(_ member: BackendVineyardMember) -> some View {
        Button {
            if canManage && member.role != .owner {
                memberToEdit = member
                showEditMember = true
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(roleColor(member.role).gradient)
                        .frame(width: 36, height: 36)
                    Image(systemName: roleIcon(member.role))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(member.displayName ?? "Member")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(member.role.rawValue.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if member.userId == auth.userId {
                    Text("You")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(VineyardTheme.leafGreen)
                }
                if canManage && member.role != .owner {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!canManage || member.role == .owner)
    }

    private func invitationRow(_ invitation: BackendInvitation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(invitation.email)
                .font(.subheadline.weight(.medium))
            HStack(spacing: 6) {
                Text(invitation.role.rawValue.capitalized)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(VineyardTheme.leafGreen)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(VineyardTheme.leafGreen.opacity(0.12), in: Capsule())
                Text(invitation.status.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func reload() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            members = try await teamRepository.listMembers(vineyardId: vineyardId)
        } catch {
            errorMessage = error.localizedDescription
        }
        do {
            let all = try await teamRepository.listPendingInvitations()
            let filtered = all.filter { $0.vineyardId == vineyardId && $0.status.lowercased() == "pending" }
            // Defensive dedupe: keep only the most recent pending invitation per email,
            // and hide any pending invitation whose email already corresponds to a member.
            var seenEmails = Set<String>()
            var deduped: [BackendInvitation] = []
            for invitation in filtered.sorted(by: { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }) {
                let key = invitation.email.lowercased()
                if seenEmails.contains(key) { continue }
                seenEmails.insert(key)
                deduped.append(invitation)
            }
            pendingInvitations = deduped
        } catch {
            // Non-fatal — members still display.
        }
    }

    private func updateRole(member: BackendVineyardMember, newRole: BackendRole) async {
        do {
            try await teamRepository.updateMemberRole(vineyardId: vineyardId, userId: member.userId, role: newRole)
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeMember(_ member: BackendVineyardMember) async {
        do {
            try await teamRepository.removeMember(vineyardId: vineyardId, userId: member.userId)
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func roleColor(_ role: BackendRole) -> Color {
        switch role {
        case .owner: return .orange
        case .manager: return .blue
        case .supervisor: return .purple
        case .operator: return .green
        }
    }

    private func roleIcon(_ role: BackendRole) -> String {
        switch role {
        case .owner: return "crown.fill"
        case .manager: return "person.crop.circle.badge.checkmark"
        case .supervisor: return "person.2.fill"
        case .operator: return "person.fill"
        }
    }
}

private struct EditMemberRoleSheet: View {
    let member: BackendVineyardMember
    let canManage: Bool
    let onSave: (BackendRole) -> Void
    let onRemove: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedRole: BackendRole

    init(member: BackendVineyardMember, canManage: Bool, onSave: @escaping (BackendRole) -> Void, onRemove: @escaping () -> Void) {
        self.member = member
        self.canManage = canManage
        self.onSave = onSave
        self.onRemove = onRemove
        self._selectedRole = State(initialValue: member.role)
    }

    private var availableRoles: [BackendRole] {
        BackendRole.allCases.filter { $0 != .owner }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Member") {
                    LabeledContent("Name", value: member.displayName ?? "—")
                    LabeledContent("Current Role", value: member.role.rawValue.capitalized)
                }

                Section("Change Role") {
                    Picker("Role", selection: $selectedRole) {
                        ForEach(availableRoles, id: \.self) { r in
                            Text(r.rawValue.capitalized).tag(r)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section {
                    Button(role: .destructive) {
                        onRemove()
                    } label: {
                        Label("Remove from Vineyard", systemImage: "person.badge.minus")
                    }
                    .disabled(!canManage)
                }
            }
            .navigationTitle("Edit Member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(selectedRole)
                    }
                    .disabled(!canManage || selectedRole == member.role)
                }
            }
        }
    }
}
