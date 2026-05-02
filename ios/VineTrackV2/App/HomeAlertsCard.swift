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
        if active == 0 { return "No active alerts" }
        return "\(active) active alert\(active == 1 ? "" : "s")"
    }

    private var subText: String {
        if let top = alertService.activeAlerts.first {
            return top.alert.title
        }
        return "Tap to open the Alerts Centre"
    }
}
