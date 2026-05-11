import SwiftUI

/// Compact "Alerts & Watchlist" summary shown on the Home dashboard.
///
/// Surfaces items that need attention from existing data sources, sorted by
/// importance:
///   1. Critical / warning alerts from AlertService (rain, weather risk,
///      disease, spray job due, etc.)
///   2. Open repair pins (count)
///   3. Overdue work tasks (date < today, not archived/finalized)
///   4. Info-level alerts (rain summaries, etc.)
///
/// Each row deep-links to the relevant area. Compact — does NOT duplicate
/// the full Alerts Centre.
struct HomeWatchlistCard: View {
    @Binding var selectedTab: Int
    @Environment(MigratedDataStore.self) private var store
    @Environment(AlertService.self) private var alertService

    private let maxAlertRows = 3

    var body: some View {
        VineyardCard {
            VStack(spacing: 0) {
                let items = watchlistItems
                if items.isEmpty {
                    emptyRow
                } else {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                        if idx > 0 { Divider().padding(.leading, 44) }
                        row(for: item)
                    }
                    Divider().padding(.leading, 44)
                    viewAllRow
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Items

    private enum WatchKind {
        case alert(AlertWithStatus)
        case repairPins(Int)
        case overdueTasks(Int)
    }

    private struct WatchItem: Identifiable {
        let id: String
        let kind: WatchKind
        let priority: Int  // lower = more urgent
    }

    private var openRepairPins: Int {
        store.pins.filter { !$0.isCompleted && $0.mode == .repairs }.count
    }

    private var overdueWorkTasks: Int {
        let startToday = Calendar.current.startOfDay(for: Date())
        return store.workTasks.filter { task in
            guard !task.isArchived, !task.isFinalized else { return false }
            return task.date < startToday
        }.count
    }

    private var watchlistItems: [WatchItem] {
        var items: [WatchItem] = []

        for alert in alertService.activeAlerts {
            let sev = alert.alert.typedSeverity
            let p: Int
            switch sev {
            case .critical: p = 0
            case .warning: p = 1
            case .info: p = 3
            }
            items.append(WatchItem(
                id: "alert-\(alert.id.uuidString)",
                kind: .alert(alert),
                priority: p
            ))
        }

        if openRepairPins > 0 {
            items.append(WatchItem(
                id: "repair-pins",
                kind: .repairPins(openRepairPins),
                priority: 2
            ))
        }

        if overdueWorkTasks > 0 {
            items.append(WatchItem(
                id: "overdue-tasks",
                kind: .overdueTasks(overdueWorkTasks),
                priority: 2
            ))
        }

        items.sort { $0.priority < $1.priority }
        return Array(items.prefix(maxAlertRows))
    }

    // MARK: - Rows

    @ViewBuilder
    private func row(for item: WatchItem) -> some View {
        switch item.kind {
        case .alert(let alert):
            alertRow(alert)
        case .repairPins(let count):
            NavigationLink {
                PinsView(initialViewMode: .list)
            } label: {
                rowContent(
                    icon: "wrench.fill",
                    tint: .orange,
                    title: "\(count) open repair pin\(count == 1 ? "" : "s")",
                    subtitle: "Tap to review"
                )
            }
            .buttonStyle(.plain)
        case .overdueTasks(let count):
            NavigationLink {
                WorkTasksHubView()
            } label: {
                rowContent(
                    icon: "clock.badge.exclamationmark.fill",
                    tint: .red,
                    title: "\(count) overdue work task\(count == 1 ? "" : "s")",
                    subtitle: "Past due — review or finalize"
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func alertRow(_ alert: AlertWithStatus) -> some View {
        Button {
            handleAlertTap(alert)
        } label: {
            rowContent(
                icon: iconFor(alert: alert),
                tint: tintFor(severity: alert.alert.typedSeverity),
                title: alert.alert.title,
                subtitle: alert.alert.message
            )
        }
        .buttonStyle(.plain)
    }

    private var emptyRow: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: "checkmark.seal.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.green)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Nothing on the watchlist")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("All alerts cleared and no overdue items")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
    }

    private var viewAllRow: some View {
        NavigationLink {
            AlertsCentreView()
        } label: {
            HStack {
                Text("View all alerts")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(VineyardTheme.info)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func rowContent(icon: String, tint: Color, title: String, subtitle: String?) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(0.18))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let s = subtitle, !s.isEmpty {
                    Text(s)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    // MARK: - Helpers

    private func tintFor(severity: AlertSeverity) -> Color {
        switch severity {
        case .critical: return .red
        case .warning: return .orange
        case .info: return .blue
        }
    }

    private func iconFor(alert: AlertWithStatus) -> String {
        switch alert.alert.typedAlertType {
        case .rainStarted, .rain24hSummary: return "cloud.rain.fill"
        case .weatherRisk: return "exclamationmark.triangle.fill"
        case .irrigationNeeded: return "drop.fill"
        case .agedPins: return "mappin.and.ellipse"
        case .sprayJobDue: return "sprinkler.and.droplets.fill"
        case .diseaseDownyMildew, .diseasePowderyMildew, .diseaseBotrytis:
            return "leaf.arrow.triangle.circlepath"
        case .syncIssue: return "arrow.triangle.2.circlepath"
        case .none: return "bell.fill"
        }
    }

    private func handleAlertTap(_ alert: AlertWithStatus) {
        switch alert.alert.typedAction {
        case .openPins:
            selectedTab = 1
        case .openSprayProgram, .openSprayRecord:
            selectedTab = 3
        default:
            // Fall through to Alerts Centre for context-specific deep links
            // that the centre handles via push.
            alertService.pendingNavigation = alert.alert.typedAction
        }
    }
}
