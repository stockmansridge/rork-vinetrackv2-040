import SwiftUI

struct DisclaimerInfoView: View {
    @Environment(NewBackendAuthService.self) private var auth
    @State private var acceptedRemotely: Bool?
    @State private var isChecking: Bool = false
    @State private var checkError: String?

    private let repository: any DisclaimerRepositoryProtocol = SupabaseDisclaimerRepository(currentVersion: DisclaimerInfo.version)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VineyardCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.shield.fill")
                                .foregroundStyle(.orange)
                            Text(DisclaimerInfo.title)
                                .font(.headline)
                        }
                        Text("Version \(DisclaimerInfo.version)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                VineyardCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Acceptance status")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            if isChecking {
                                ProgressView().controlSize(.mini)
                            } else if let acceptedRemotely {
                                VineyardStatusBadge(
                                    text: acceptedRemotely ? "Accepted" : "Not accepted",
                                    icon: acceptedRemotely ? "checkmark.circle.fill" : "xmark.circle.fill",
                                    kind: acceptedRemotely ? .success : .warning
                                )
                            } else {
                                Text("—").foregroundStyle(.secondary)
                            }
                        }
                        if let checkError {
                            Text(checkError)
                                .font(.caption)
                                .foregroundStyle(VineyardTheme.destructive)
                        }
                    }
                }

                VineyardCard {
                    Text(DisclaimerInfo.bodyText)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
        }
        .background(VineyardTheme.appBackground)
        .navigationTitle("Disclaimer")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
    }

    private func refresh() async {
        isChecking = true
        checkError = nil
        defer { isChecking = false }
        do {
            acceptedRemotely = try await repository.hasAcceptedCurrentDisclaimer()
        } catch {
            checkError = error.localizedDescription
        }
    }
}

struct AccountDeletionRequestView: View {
    @Environment(NewBackendAuthService.self) private var auth

    private let supportEmail: String = "jonathan@stockmansridge.com.au"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VineyardCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "person.crop.circle.badge.xmark")
                                .foregroundStyle(.red)
                            Text("Request Account Deletion")
                                .font(.headline)
                        }
                        Text("To delete your account and associated VineTrackV2 access, please contact support from the email address used for your account.")
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Account deletion is irreversible. Your vineyard data may remain accessible to other team members of vineyards you belong to.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VineyardCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your account")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        VineyardInfoRow(label: "Name", value: auth.userName ?? "—", icon: "person.fill", iconColor: .gray)
                        VineyardInfoRow(label: "Email", value: auth.userEmail ?? "—", icon: "envelope.fill", iconColor: .blue)
                    }
                }

                Button {
                    openMail()
                } label: {
                    Label("Email Support", systemImage: "envelope.fill")
                }
                .buttonStyle(.vineyardPrimary(tint: VineyardTheme.destructive))

                Text("Support: \(supportEmail)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(16)
        }
        .background(VineyardTheme.appBackground)
        .navigationTitle("Delete Account")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func openMail() {
        let subject = "VineTrackV2 account deletion request"
        let body = """
Please delete my VineTrackV2 account.

Name: \(auth.userName ?? "—")
Email: \(auth.userEmail ?? "—")
"""
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = supportEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]
        if let url = components.url {
            UIApplication.shared.open(url)
        }
    }
}
