import SwiftUI

/// Compact alerts summary shown in the Home → Today section.
///
/// When there are active alerts, displays a header row with overall severity
/// and count plus an inline preview of the top 3 alerts (sorted by severity
/// then newest). When there are no alerts, shows a clear "All clear" empty
/// state so the user is never left wondering whether the system is running.
struct HomeAlertsCard: View {
    @Environment(AlertService.self) private var alertService

    private let maxPreviewRows: Int = 3

    var body: some View {
        NavigationLink {
            AlertsCentreView()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                headerRow
                if !previewAlerts.isEmpty {
                    Divider()
                    VStack(spacing: 8) {
                        ForEach(previewAlerts) { item in
                            alertPreviewRow(item)
                        }
                    }
                    if alertService.activeAlerts.count > previewAlerts.count {
                        Text("+ \(alertService.activeAlerts.count - previewAlerts.count) more")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(tint.opacity(hasAlerts ? 0.25 : 0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(0.15))
                    .frame(width: 30, height: 30)
                Image(systemName: iconName)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(primaryText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let secondary = secondaryText {
                    Text(secondary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if alertService.unreadAlerts.count > 0 && hasAlerts {
                Text("\(alertService.unreadAlerts.count)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(tint.opacity(0.15), in: Capsule())
            }
            Text("View")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Preview row

    private func alertPreviewRow(_ item: AlertWithStatus) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(severityColor(item.alert.typedSeverity))
                .frame(width: 6, height: 6)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.alert.title)
                    .font(.caption.weight(item.isRead ? .regular : .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(item.alert.message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Computed

    private var previewAlerts: [AlertWithStatus] {
        let sorted = alertService.activeAlerts.sorted { lhs, rhs in
            if lhs.alert.typedSeverity != rhs.alert.typedSeverity {
                return lhs.alert.typedSeverity > rhs.alert.typedSeverity
            }
            return (lhs.alert.createdAt ?? .distantPast) > (rhs.alert.createdAt ?? .distantPast)
        }
        return Array(sorted.prefix(maxPreviewRows))
    }

    private var hasAlerts: Bool { !alertService.activeAlerts.isEmpty }

    private var tint: Color {
        switch alertService.highestSeverity {
        case .critical: return .red
        case .warning: return .orange
        case .info: return .blue
        case .none: return .green
        }
    }

    private var iconName: String {
        hasAlerts ? "bell.badge.fill" : "checkmark.seal.fill"
    }

    private var primaryText: String {
        let active = alertService.activeAlerts
        if active.isEmpty { return "All clear" }
        if active.count == 1 { return "1 alert needs attention" }
        return "\(active.count) alerts need attention"
    }

    private var secondaryText: String? {
        let active = alertService.activeAlerts
        if active.isEmpty {
            return "No active alerts for this vineyard"
        }
        let summary = summaryByType(active)
        guard !summary.isEmpty else { return nil }
        return summary.prefix(2).joined(separator: " · ")
    }

    private var accessibilityLabel: String {
        let active = alertService.activeAlerts.count
        return active == 0 ? "All clear, no active alerts" : "\(active) alerts need attention"
    }

    private func severityColor(_ s: AlertSeverity) -> Color {
        switch s {
        case .critical: return .red
        case .warning: return .orange
        case .info: return .blue
        }
    }

    private func summaryByType(_ items: [AlertWithStatus]) -> [String] {
        var counts: [AlertType: Int] = [:]
        for item in items {
            guard let t = item.alert.typedAlertType else { continue }
            counts[t, default: 0] += 1
        }
        let order: [AlertType] = [
            .rainStarted, .rain24hSummary, .weatherRisk, .irrigationNeeded,
            .agedPins, .sprayJobDue,
            .diseaseDownyMildew, .diseasePowderyMildew, .diseaseBotrytis, .syncIssue
        ]
        return order.compactMap { type in
            guard let n = counts[type], n > 0 else { return nil }
            switch type {
            case .weatherRisk: return "Weather"
            case .irrigationNeeded: return "Irrigation"
            case .agedPins: return "Aged pins"
            case .sprayJobDue: return "Spray job"
            case .syncIssue: return "Sync"
            case .diseaseDownyMildew: return "Downy mildew"
            case .diseasePowderyMildew: return "Powdery mildew"
            case .diseaseBotrytis: return "Botrytis"
            case .rainStarted: return "Rain started"
            case .rain24hSummary: return "24h rain"
            }
        }
    }
}
