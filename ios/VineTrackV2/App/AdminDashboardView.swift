import SwiftUI

struct AdminDashboardView: View {
    @State private var summary: AdminEngagementSummary?
    @State private var users: [AdminUserRow] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var searchText: String = ""

    private let repository = SupabaseAdminRepository()

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.footnote)
                }
            }

            engagementSection
            usersSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Admin")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search users")
        .refreshable { await loadAll() }
        .task { await loadAll() }
        .overlay {
            if isLoading && summary == nil {
                ProgressView()
            }
        }
    }

    private var engagementSection: some View {
        Section {
            if let summary {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    StatTile(title: "Total Users", value: "\(summary.totalUsers)", symbol: "person.3.fill", color: .blue)
                    StatTile(title: "Vineyards", value: "\(summary.totalVineyards)", symbol: "building.2.fill", color: VineyardTheme.leafGreen)
                    StatTile(title: "Active 7d", value: "\(summary.signedInLast7Days)", symbol: "bolt.fill", color: .orange)
                    StatTile(title: "Active 30d", value: "\(summary.signedInLast30Days)", symbol: "calendar", color: .indigo)
                    StatTile(title: "New 30d", value: "\(summary.newUsersLast30Days)", symbol: "person.fill.badge.plus", color: .pink)
                    StatTile(title: "Pending Invites", value: "\(summary.pendingInvitations)", symbol: "envelope.badge.fill", color: .red)
                    StatTile(title: "Pins", value: "\(summary.totalPins)", symbol: "mappin.and.ellipse", color: .teal)
                    StatTile(title: "Spray Records", value: "\(summary.totalSprayRecords)", symbol: "drop.fill", color: .cyan)
                    StatTile(title: "Work Tasks", value: "\(summary.totalWorkTasks)", symbol: "checkmark.circle.fill", color: .green)
                }
                .padding(.vertical, 4)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
            } else if !isLoading {
                Text("No engagement data available.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Engagement")
        } footer: {
            if summary != nil {
                Text("Active = profile updated in the period (sign-in or app activity).")
            }
        }
    }

    private var filteredUsers: [AdminUserRow] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return users }
        return users.filter {
            $0.email.lowercased().contains(q) ||
            ($0.fullName?.lowercased().contains(q) ?? false)
        }
    }

    private var usersSection: some View {
        Section {
            if filteredUsers.isEmpty && !isLoading {
                Text(users.isEmpty ? "No users found." : "No matches.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(filteredUsers) { user in
                NavigationLink {
                    AdminUserDetailView(user: user)
                } label: {
                    AdminUserRowView(user: user)
                }
            }
        } header: {
            HStack {
                Text("Users")
                Spacer()
                if !users.isEmpty {
                    Text("\(filteredUsers.count) of \(users.count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @MainActor
    private func loadAll() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let summaryTask = repository.fetchEngagementSummary()
            async let usersTask = repository.fetchAllUsers()
            let (s, u) = try await (summaryTask, usersTask)
            summary = s
            users = u
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct StatTile: View {
    let title: String
    let value: String
    let symbol: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(color.gradient, in: RoundedRectangle(cornerRadius: 7))
                Spacer()
            }
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct AdminUserRowView: View {
    let user: AdminUserRow

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue.gradient)
                    .frame(width: 36, height: 36)
                Text(initials)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(user.email)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if user.vineyardCount > 0 {
                    Label("\(user.vineyardCount)", systemImage: "building.2.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(VineyardTheme.leafGreen)
                }
                if let created = user.createdAt {
                    Text(created, format: .dateTime.month(.abbreviated).day().year())
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var initials: String {
        let source = user.fullName?.isEmpty == false ? user.fullName! : user.email
        let parts = source.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map { String($0) }.joined()
        return letters.isEmpty ? String(source.prefix(1)).uppercased() : letters.uppercased()
    }
}

private struct AdminUserDetailView: View {
    let user: AdminUserRow
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            Section {
                LabeledContent("Name", value: user.fullName ?? "—")
                LabeledContent("Email", value: user.email)
                LabeledContent("Vineyards", value: "\(user.vineyardCount)")
                if let created = user.createdAt {
                    LabeledContent("Joined") {
                        Text(created, format: .dateTime.month(.abbreviated).day().year())
                    }
                }
                if let updated = user.updatedAt {
                    LabeledContent("Last Active") {
                        Text(updated, format: .relative(presentation: .named))
                    }
                }
            } header: {
                Text("Profile")
            }

            Section {
                Button {
                    sendEmail(subject: "VineTrack Support", body: "Hi \(user.fullName ?? ""),\n\n")
                } label: {
                    Label("Email Support Reply", systemImage: "envelope.fill")
                }
                Button {
                    sendEmail(subject: "VineTrack — Welcome & Onboarding", body: "Hi \(user.fullName ?? ""),\n\nWelcome to VineTrack! ")
                } label: {
                    Label("Send Welcome Email", systemImage: "hand.wave.fill")
                }
                Button {
                    UIPasteboard.general.string = user.email
                } label: {
                    Label("Copy Email Address", systemImage: "doc.on.doc")
                }
                Button {
                    UIPasteboard.general.string = user.id.uuidString
                } label: {
                    Label("Copy User ID", systemImage: "number")
                }
            } header: {
                Text("Support Actions")
            }

            Section {
                Text(user.id.uuidString)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            } header: {
                Text("User ID")
            }
        }
        .navigationTitle(user.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sendEmail(subject: String, body: String) {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = user.email
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]
        if let url = components.url {
            openURL(url)
        }
    }
}
