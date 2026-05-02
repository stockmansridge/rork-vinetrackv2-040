import SwiftUI

struct HomeAlertsCard: View {
    @Environment(AlertService.self) private var alertService

    var body: some View {
        NavigationLink {
            AlertsCentreView()
        } label: {
            VineyardCard {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(tint.opacity(0.15))
                            .frame(width: 48, height: 48)
                        Image(systemName: "bell.badge.fill")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(tint)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(headlineText)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(subText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .accessibilityElement(children: .combine)
                    Spacer()
                    if alertService.unreadAlerts.count > 0 {
                        Text("\(alertService.unreadAlerts.count)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.red, in: Capsule())
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }

    private var tint: Color {
        switch alertService.highestSeverity {
        case .critical: return .red
        case .warning: return .orange
        case .info: return .blue
        case .none: return .gray
        }
    }

    private var headlineText: String {
        let active = alertService.activeAlerts.count
        if active == 0 { return "Your vineyard is up to date" }
        if active == 1 { return "1 vineyard alert needs attention" }
        return "\(active) vineyard alerts need attention"
    }

    private var subText: String {
        let active = alertService.activeAlerts
        if active.isEmpty {
            return "We'll flag irrigation, pins, spray jobs and weather risks here."
        }
        // Group by severity & dedupe weather risks for the same day.
        let summary = summaryByType(active)
        if summary.count == 1, let only = summary.first {
            return only
        }
        return summary.prefix(2).joined(separator: " • ")
    }

    private func summaryByType(_ items: [AlertWithStatus]) -> [String] {
        var counts: [AlertType: Int] = [:]
        for item in items {
            guard let t = item.alert.typedAlertType else { continue }
            counts[t, default: 0] += 1
        }
        let order: [AlertType] = [.weatherRisk, .irrigationNeeded, .agedPins, .sprayJobDue, .syncIssue]
        return order.compactMap { type in
            guard let n = counts[type], n > 0 else { return nil }
            switch type {
            case .weatherRisk: return "Weather risk"
            case .irrigationNeeded: return "Irrigation needed"
            case .agedPins: return n == 1 ? "1 aged pin" : "\(n) aged pins"
            case .sprayJobDue: return n == 1 ? "1 spray job due" : "\(n) spray jobs due"
            case .syncIssue: return "Sync issue"
            }
        }
    }
}
