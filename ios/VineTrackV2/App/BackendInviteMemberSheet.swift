import SwiftUI

struct BackendInviteMemberSheet: View {
    let vineyardId: UUID
    let vineyardName: String
    var onSent: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var email: String = ""
    @State private var role: BackendRole = .operator
    @State private var isSending: Bool = false
    @State private var errorMessage: String?
    @State private var showSuccess: Bool = false

    private let teamRepository: any TeamRepositoryProtocol = SupabaseTeamRepository()

    private var availableRoles: [BackendRole] {
        BackendRole.allCases.filter { $0 != .owner }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Invite Details") {
                    TextField("Email address", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section {
                    Picker("Role", selection: $role) {
                        ForEach(availableRoles, id: \.self) { role in
                            Text(role.rawValue.capitalized).tag(role)
                        }
                    }

                    NavigationLink {
                        RolesPermissionsInfoView()
                    } label: {
                        Label("Learn more about roles", systemImage: "info.circle")
                            .font(.footnote)
                    }
                } header: {
                    Text("Role")
                } footer: {
                    Text("Some features and values are hidden based on the assigned role.")
                }

                Section {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(VineyardTheme.info)
                        Text("The invited person will need to sign up or log in with this email to access \(vineyardName).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if showSuccess {
                    Section {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(VineyardTheme.leafGreen)
                            Text("Invitation sent successfully!")
                                .font(.subheadline.weight(.medium))
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } header: {
                        Text("Error")
                    }
                }
            }
            .navigationTitle("Invite Member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSending)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        Task { await send() }
                    }
                    .disabled(email.isEmpty || isSending)
                }
            }
        }
    }

    private func send() async {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.contains("@") else {
            errorMessage = "Please enter a valid email"
            return
        }
        errorMessage = nil
        showSuccess = false
        isSending = true
        defer { isSending = false }
        do {
            _ = try await teamRepository.inviteMember(vineyardId: vineyardId, email: trimmed, role: role)
            showSuccess = true
            email = ""
            onSent?()
            // First-invite milestone: surface the web portal prompt for
            // managers so they discover desktop team management.
            PortalPromptTracker.requestIfUnseen(.firstInvite)
            try? await Task.sleep(for: .seconds(1.2))
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
