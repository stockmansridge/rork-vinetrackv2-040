import SwiftUI

struct AlertsCentreView: View {
    @Environment(AlertService.self) private var alertService
    @Environment(BackendAccessControl.self) private var accessControl
    @Environment(\.dismiss) private var dismiss

    @State private var isRefreshing: Bool = false
    @State private var pushDestination: AlertPushDestination?

    var body: some View {
        List {
            if alertService.activeAlerts.isEmpty {
                Section {
                    emptyState
                }
                if alertService.lastRefresh != nil {
                    lastCheckedSection
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
                lastCheckedSection
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
        .navigationDestination(item: $pushDestination) { dest in
            switch dest {
            case .irrigation, .weather:
                IrrigationRecommendationView()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 40))
                .foregroundStyle(.green)
            Text("Your vineyard is up to date")
                .font(.headline)
            Text("We'll flag irrigation needs, aged pins, spray jobs and weather risks here.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    @ViewBuilder
    private var lastCheckedSection: some View {
        if let last = alertService.lastRefresh {
            Section {
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(.tertiary)
                    Text("Last checked \(last.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .listRowBackground(Color.clear)
        }
    }

    private func handleAction(_ alert: BackendAlert) {
        guard let action = alert.typedAction else { return }
        switch action {
        case .openPins, .openSprayProgram, .openSprayRecord:
            // Tab switches handled by NewMainTabView; pop back to home root.
            alertService.pendingNavigation = action
            dismiss()
        case .openIrrigationAdvisor, .openWeather:
            // Weather alerts route to Irrigation Advisor (where the data
            // turns into an action) until a dedicated weather hub exists.
            pushDestination = .irrigation
        }
    }
}

private enum AlertPushDestination: Identifiable, Hashable {
    case irrigation
    case weather
    var id: String {
        switch self {
        case .irrigation: return "irrigation"
        case .weather: return "weather"
        }
    }
}

private struct AlertRow: View {
    let item: AlertWithStatus

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(severityColor.opacity(0.18))
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
                HStack(spacing: 8) {
                    if let label = actionLabel {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption2)
                            Text(label)
                                .font(.caption2.weight(.semibold))
                        }
                        .foregroundStyle(severityColor)
                    }
                    if let date = item.alert.createdAt {
                        Text("·")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(date.formatted(.relative(presentation: .named)))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private var actionLabel: String? {
        switch item.alert.typedAction {
        case .openIrrigationAdvisor, .openWeather: return "Open Irrigation Advisor"
        case .openPins: return "View Pins"
        case .openSprayProgram: return "Open Spray Program"
        case .openSprayRecord: return "Open Spray Record"
        case .none: return nil
        }
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
