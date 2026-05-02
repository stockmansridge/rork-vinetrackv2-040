import SwiftUI

struct AlertsCentreView: View {
    @Environment(AlertService.self) private var alertService
    @Environment(BackendAccessControl.self) private var accessControl

    @State private var isRefreshing: Bool = false

    var body: some View {
        List {
            if alertService.activeAlerts.isEmpty {
                Section {
                    emptyState
                }
            } else {
                Section {
                    ForEach(alertService.activeAlerts) { item in
                        Button {
                            Task { await alertService.markRead(item) }
                            handleAction(item.alert)
                        } label: {
                            AlertRow(item: item)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { await alertService.dismiss(item) }
                            } label: {
                                Label("Dismiss", systemImage: "xmark.circle")
                            }
                            if !item.isRead {
                                Button {
                                    Task { await alertService.markRead(item) }
                                } label: {
                                    Label("Read", systemImage: "envelope.open")
                                }
                                .tint(.blue)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Active alerts (\(alertService.activeAlerts.count))")
                        Spacer()
                        if !alertService.unreadAlerts.isEmpty {
                            Button("Mark all read") {
                                Task { await alertService.markAllRead() }
                            }
                            .font(.caption)
                        }
                    }
                }
            }
        }
        .navigationTitle("Alerts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if accessControl.canChangeSettings {
                    NavigationLink {
                        AlertSettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
        .refreshable {
            await alertService.generateAndRefresh()
        }
        .task {
            await alertService.generateAndRefresh()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "bell.slash")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No alerts")
                .font(.headline)
            Text("You're all caught up. Pull to refresh and regenerate alerts.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    private func handleAction(_ alert: BackendAlert) {
        // Action routing kept lightweight: relies on user navigating from
        // their main tabs. Future work: wire deep links per AlertAction.
    }
}

private struct AlertRow: View {
    let item: AlertWithStatus

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(severityColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: severityIcon)
                    .foregroundStyle(severityColor)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.alert.title)
                        .font(.subheadline.weight(item.isRead ? .regular : .semibold))
                        .foregroundStyle(.primary)
                    if !item.isRead {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 6, height: 6)
                    }
                }
                Text(item.alert.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                if let date = item.alert.createdAt {
                    Text(date.formatted(.relative(presentation: .named)))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private var severityColor: Color {
        switch item.alert.typedSeverity {
        case .info: return .blue
        case .warning: return .orange
        case .critical: return .red
        }
    }

    private var severityIcon: String {
        switch item.alert.typedAlertType {
        case .irrigationNeeded: return "drop.fill"
        case .agedPins: return "mappin.and.ellipse"
        case .weatherRisk: return "cloud.rain.fill"
        case .sprayJobDue: return "sprinkler.and.droplets.fill"
        case .syncIssue: return "exclamationmark.icloud"
        case .none: return "bell.fill"
        }
    }
}
