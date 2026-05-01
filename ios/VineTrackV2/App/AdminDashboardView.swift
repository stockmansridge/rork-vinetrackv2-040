import SwiftUI

private enum AdminUserFilter: Hashable {
    case active7
    case active30
    case new30
}

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
                    tile("Total Users", "\(summary.totalUsers)", "person.3.fill", .blue) { AdminUsersListView(title: "All Users", users: users) }
                    tile("Vineyards", "\(summary.totalVineyards)", "building.2.fill", VineyardTheme.leafGreen) { AdminVineyardsListView() }
                    tile("Active 7d", "\(summary.signedInLast7Days)", "bolt.fill", .orange) { AdminUsersListView(title: "Active in last 7 days", users: filtered(by: .active7)) }
                    tile("Active 30d", "\(summary.signedInLast30Days)", "calendar", .indigo) { AdminUsersListView(title: "Active in last 30 days", users: filtered(by: .active30)) }
                    tile("New 30d", "\(summary.newUsersLast30Days)", "person.fill.badge.plus", .pink) { AdminUsersListView(title: "New users (30d)", users: filtered(by: .new30)) }
                    tile("Pending Invites", "\(summary.pendingInvitations)", "envelope.badge.fill", .red) { AdminInvitationsListView() }
                    tile("Pins", "\(summary.totalPins)", "mappin.and.ellipse", .teal) { AdminPinsListView() }
                    tile("Spray Records", "\(summary.totalSprayRecords)", "drop.fill", .cyan) { AdminSprayRecordsListView() }
                    tile("Work Tasks", "\(summary.totalWorkTasks)", "checkmark.circle.fill", .green) { AdminWorkTasksListView() }
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
                Text("Tap any tile to see the underlying records. Active = signed in within the period.")
            }
        }
    }

    @ViewBuilder
    private func tile<Destination: View>(_ title: String, _ value: String, _ symbol: String, _ color: Color, @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink {
            destination()
        } label: {
            StatTile(title: title, value: value, symbol: symbol, color: color)
        }
        .buttonStyle(.plain)
    }

    private var filteredUsers: [AdminUserRow] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return users }
        return users.filter {
            $0.email.lowercased().contains(q) ||
            ($0.fullName?.lowercased().contains(q) ?? false)
        }
    }

    private func filtered(by filter: AdminUserFilter) -> [AdminUserRow] {
        let cal = Calendar.current
        let now = Date()
        switch filter {
        case .active7:
            let cutoff = cal.date(byAdding: .day, value: -7, to: now) ?? now
            return users.filter { ($0.lastSignInAt ?? .distantPast) >= cutoff }
        case .active30:
            let cutoff = cal.date(byAdding: .day, value: -30, to: now) ?? now
            return users.filter { ($0.lastSignInAt ?? .distantPast) >= cutoff }
        case .new30:
            let cutoff = cal.date(byAdding: .day, value: -30, to: now) ?? now
            return users.filter { ($0.createdAt ?? .distantPast) >= cutoff }
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

// MARK: - Tile

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
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - User Row

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
                if let last = user.lastSignInAt {
                    Text(last, format: .relative(presentation: .named))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else if let created = user.createdAt {
                    Text(created, format: .dateTime.month(.abbreviated).day().year())
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .contentShape(Rectangle())
    }

    private var initials: String {
        let source = user.fullName?.isEmpty == false ? user.fullName! : user.email
        let parts = source.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map { String($0) }.joined()
        return letters.isEmpty ? String(source.prefix(1)).uppercased() : letters.uppercased()
    }
}

// MARK: - Users list

private struct AdminUsersListView: View {
    let title: String
    let users: [AdminUserRow]
    @State private var query: String = ""

    private var filtered: [AdminUserRow] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return users }
        return users.filter {
            $0.email.lowercased().contains(q) ||
            ($0.fullName?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        List {
            Section {
                if filtered.isEmpty {
                    Text("No users.").font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(filtered) { user in
                    NavigationLink {
                        AdminUserDetailView(user: user)
                    } label: {
                        AdminUserRowView(user: user)
                    }
                }
            } header: {
                Text("\(filtered.count) of \(users.count)")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search")
    }
}

// MARK: - User detail

private struct AdminUserDetailView: View {
    let user: AdminUserRow
    @Environment(\.openURL) private var openURL
    @State private var vineyards: [AdminUserVineyardRow] = []
    @State private var isLoading: Bool = false
    @State private var loadError: String?

    private let repository = SupabaseAdminRepository()

    var body: some View {
        Form {
            Section {
                LabeledContent("Name", value: user.fullName ?? "—")
                LabeledContent("Email", value: user.email)
                LabeledContent("Vineyards", value: "\(user.vineyardCount)")
                LabeledContent("Owned", value: "\(user.ownedCount)")
                if let created = user.createdAt {
                    LabeledContent("Joined") {
                        Text(created, format: .dateTime.month(.abbreviated).day().year())
                    }
                }
                if let last = user.lastSignInAt {
                    LabeledContent("Last Sign-In") {
                        Text(last, format: .relative(presentation: .named))
                    }
                } else if let updated = user.updatedAt {
                    LabeledContent("Last Active") {
                        Text(updated, format: .relative(presentation: .named))
                    }
                }
            } header: {
                Text("Profile")
            }

            Section {
                if isLoading && vineyards.isEmpty {
                    HStack { ProgressView(); Text("Loading…").foregroundStyle(.secondary) }
                } else if let loadError {
                    Label(loadError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.footnote)
                } else if vineyards.isEmpty {
                    Text("No vineyards.").font(.footnote).foregroundStyle(.secondary)
                } else {
                    ForEach(vineyards) { v in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(v.name).font(.subheadline.weight(.semibold))
                                if v.isOwner {
                                    Text("OWNER")
                                        .font(.caption2.weight(.bold))
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(VineyardTheme.leafGreen.opacity(0.15), in: Capsule())
                                        .foregroundStyle(VineyardTheme.leafGreen)
                                } else if let role = v.role {
                                    Text(role.uppercased())
                                        .font(.caption2.weight(.bold))
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Color.blue.opacity(0.12), in: Capsule())
                                        .foregroundStyle(.blue)
                                }
                                Spacer()
                                if v.deletedAt != nil {
                                    Text("ARCHIVED")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            HStack(spacing: 12) {
                                Label("\(v.memberCount)", systemImage: "person.2.fill")
                                if let c = v.country, !c.isEmpty { Text(c) }
                                if let d = v.createdAt {
                                    Text(d, format: .dateTime.month(.abbreviated).day().year())
                                }
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Vineyards (\(vineyards.count))")
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
        .task { await loadVineyards() }
        .refreshable { await loadVineyards() }
    }

    @MainActor
    private func loadVineyards() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            vineyards = try await repository.fetchUserVineyards(userId: user.id)
        } catch {
            loadError = error.localizedDescription
        }
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

// MARK: - Vineyards list

private struct AdminVineyardsListView: View {
    @State private var vineyards: [AdminVineyardRow] = []
    @State private var isLoading: Bool = false
    @State private var loadError: String?
    @State private var query: String = ""

    private let repository = SupabaseAdminRepository()

    private var filtered: [AdminVineyardRow] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return vineyards }
        return vineyards.filter {
            $0.name.lowercased().contains(q) ||
            ($0.ownerEmail?.lowercased().contains(q) ?? false) ||
            ($0.ownerFullName?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        List {
            if let loadError {
                Section {
                    Label(loadError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange).font(.footnote)
                }
            }
            Section {
                if filtered.isEmpty && !isLoading {
                    Text("No vineyards.").font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(filtered) { v in
                    NavigationLink {
                        AdminVineyardDetailView(vineyard: v)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(v.name).font(.subheadline.weight(.semibold))
                                Spacer()
                                if v.deletedAt != nil {
                                    Text("ARCHIVED").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                                }
                            }
                            Text(v.ownerDisplay).font(.caption).foregroundStyle(.secondary)
                            HStack(spacing: 12) {
                                Label("\(v.memberCount)", systemImage: "person.2.fill")
                                if v.pendingInvites > 0 {
                                    Label("\(v.pendingInvites)", systemImage: "envelope.badge.fill")
                                        .foregroundStyle(.orange)
                                }
                                if let d = v.createdAt {
                                    Text(d, format: .dateTime.month(.abbreviated).day().year())
                                }
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("\(filtered.count) of \(vineyards.count)")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Vineyards")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search vineyards or owners")
        .overlay { if isLoading && vineyards.isEmpty { ProgressView() } }
        .task { await load() }
        .refreshable { await load() }
    }

    @MainActor
    private func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            vineyards = try await repository.fetchAllVineyards()
        } catch {
            loadError = error.localizedDescription
        }
    }
}

private struct AdminVineyardDetailView: View {
    let vineyard: AdminVineyardRow

    var body: some View {
        Form {
            Section("Vineyard") {
                LabeledContent("Name", value: vineyard.name)
                LabeledContent("Owner", value: vineyard.ownerDisplay)
                if let email = vineyard.ownerEmail { LabeledContent("Owner Email", value: email) }
                if let c = vineyard.country, !c.isEmpty { LabeledContent("Country", value: c) }
                LabeledContent("Members", value: "\(vineyard.memberCount)")
                LabeledContent("Pending Invites", value: "\(vineyard.pendingInvites)")
                if let d = vineyard.createdAt {
                    LabeledContent("Created") { Text(d, format: .dateTime.month(.abbreviated).day().year()) }
                }
                if vineyard.deletedAt != nil {
                    LabeledContent("Status", value: "Archived")
                }
            }
            Section("Vineyard ID") {
                Text(vineyard.id.uuidString).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(vineyard.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Invitations

private struct AdminInvitationsListView: View {
    @State private var rows: [AdminInvitationRow] = []
    @State private var isLoading: Bool = false
    @State private var loadError: String?

    private let repository = SupabaseAdminRepository()

    var body: some View {
        List {
            if let loadError {
                Section { Label(loadError, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.footnote) }
            }
            Section {
                if rows.isEmpty && !isLoading {
                    Text("No invitations.").font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(rows) { r in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(r.email).font(.subheadline.weight(.semibold))
                            Spacer()
                            statusBadge(r.status)
                        }
                        HStack(spacing: 8) {
                            Text(r.role.capitalized).font(.caption.weight(.medium))
                            if let v = r.vineyardName { Text("• \(v)").font(.caption).foregroundStyle(.secondary) }
                        }
                        if let d = r.createdAt {
                            Text(d, format: .dateTime.month(.abbreviated).day().year())
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
            } header: {
                Text("\(rows.count) invitations")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Invitations")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if isLoading && rows.isEmpty { ProgressView() } }
        .task { await load() }
        .refreshable { await load() }
    }

    @ViewBuilder
    private func statusBadge(_ status: String) -> some View {
        let color: Color = {
            switch status.lowercased() {
            case "pending": return .orange
            case "accepted": return .green
            case "declined", "expired", "cancelled": return .gray
            default: return .blue
            }
        }()
        Text(status.uppercased())
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    @MainActor
    private func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do { rows = try await repository.fetchInvitations() }
        catch { loadError = error.localizedDescription }
    }
}

// MARK: - Pins

private struct AdminPinsListView: View {
    @State private var rows: [AdminPinRow] = []
    @State private var isLoading: Bool = false
    @State private var loadError: String?

    private let repository = SupabaseAdminRepository()

    var body: some View {
        List {
            if let loadError {
                Section { Label(loadError, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.footnote) }
            }
            Section {
                if rows.isEmpty && !isLoading {
                    Text("No pins.").font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(rows) { r in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(r.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Spacer()
                            if r.isCompleted {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            }
                        }
                        HStack(spacing: 8) {
                            if let v = r.vineyardName { Text(v).font(.caption).foregroundStyle(.secondary) }
                            if let c = r.category { Text("• \(c)").font(.caption).foregroundStyle(.secondary) }
                        }
                        if let d = r.createdAt {
                            Text(d, format: .dateTime.month(.abbreviated).day().year())
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
            } header: {
                Text("\(rows.count) pins")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Pins")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if isLoading && rows.isEmpty { ProgressView() } }
        .task { await load() }
        .refreshable { await load() }
    }

    @MainActor
    private func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do { rows = try await repository.fetchPins() }
        catch { loadError = error.localizedDescription }
    }
}

// MARK: - Spray Records

private struct AdminSprayRecordsListView: View {
    @State private var rows: [AdminSprayRow] = []
    @State private var isLoading: Bool = false
    @State private var loadError: String?

    private let repository = SupabaseAdminRepository()

    var body: some View {
        List {
            if let loadError {
                Section { Label(loadError, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.footnote) }
            }
            Section {
                if rows.isEmpty && !isLoading {
                    Text("No spray records.").font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(rows) { r in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(r.sprayReference?.isEmpty == false ? r.sprayReference! : (r.operationType ?? "Spray"))
                                .font(.subheadline.weight(.semibold)).lineLimit(1)
                            Spacer()
                            if let op = r.operationType { Text(op).font(.caption2).foregroundStyle(.secondary) }
                        }
                        if let v = r.vineyardName { Text(v).font(.caption).foregroundStyle(.secondary) }
                        if let d = r.date ?? r.createdAt {
                            Text(d, format: .dateTime.month(.abbreviated).day().year())
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
            } header: {
                Text("\(rows.count) spray records")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Spray Records")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if isLoading && rows.isEmpty { ProgressView() } }
        .task { await load() }
        .refreshable { await load() }
    }

    @MainActor
    private func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do { rows = try await repository.fetchSprayRecords() }
        catch { loadError = error.localizedDescription }
    }
}

// MARK: - Work Tasks

private struct AdminWorkTasksListView: View {
    @State private var rows: [AdminWorkTaskRow] = []
    @State private var isLoading: Bool = false
    @State private var loadError: String?

    private let repository = SupabaseAdminRepository()

    var body: some View {
        List {
            if let loadError {
                Section { Label(loadError, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.footnote) }
            }
            Section {
                if rows.isEmpty && !isLoading {
                    Text("No work tasks.").font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(rows) { r in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(r.taskType?.isEmpty == false ? r.taskType! : "Task")
                                .font(.subheadline.weight(.semibold)).lineLimit(1)
                            Spacer()
                            if let h = r.durationHours, h > 0 {
                                Text(String(format: "%.1fh", h)).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        HStack(spacing: 8) {
                            if let v = r.vineyardName { Text(v).font(.caption).foregroundStyle(.secondary) }
                            if let p = r.paddockName, !p.isEmpty { Text("• \(p)").font(.caption).foregroundStyle(.secondary) }
                        }
                        if let d = r.date ?? r.createdAt {
                            Text(d, format: .dateTime.month(.abbreviated).day().year())
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
            } header: {
                Text("\(rows.count) work tasks")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Work Tasks")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if isLoading && rows.isEmpty { ProgressView() } }
        .task { await load() }
        .refreshable { await load() }
    }

    @MainActor
    private func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do { rows = try await repository.fetchWorkTasks() }
        catch { loadError = error.localizedDescription }
    }
}
