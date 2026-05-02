import SwiftUI

struct HomeAlertsCard: View {
    @Environment(AlertService.self) private var alertService

    var body: some View {
        NavigationLink {
            AlertsCentreView()
        } label: {
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
                if alertService.unreadAlerts.count > 1 {
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
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: hasAlerts ? 64 : 48, alignment: .leading)
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
    }

    private var hasAlerts: Bool { alertService.activeAlerts.count > 0 }

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
        if active.isEmpty { return "Vineyard up to date" }
        if active.count == 1 {
            return active.first?.alert.title ?? "1 alert needs attention"
        }
        return "\(active.count) alerts need attention"
    }

    private var secondaryText: String? {
        let active = alertService.activeAlerts
        if active.isEmpty { return nil }
        let summary = summaryByType(active)
        if active.count == 1 { return nil }
        if summary.isEmpty { return nil }
        return summary.prefix(2).joined(separator: " · ")
    }

    private func summaryByType(_ items: [AlertWithStatus]) -> [String] {
        var counts: [AlertType: Int] = [:]
        for item in items {
            guard let t = item.alert.typedAlertType else { continue }
            counts[t, default: 0] += 1
        }
        let order: [AlertType] = [
            .weatherRisk, .irrigationNeeded, .agedPins, .sprayJobDue,
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
            }
        }
    }
}
