import SwiftUI

struct YieldHubView: View {
    @Environment(MigratedDataStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerCard

                VStack(spacing: 12) {
                    NavigationLink {
                        YieldEstimationView()
                    } label: {
                        hubOption(
                            icon: "chart.bar.doc.horizontal",
                            iconGradient: [.purple, .indigo],
                            title: "Yield Estimation",
                            subtitle: "Bunch count sample sites & block estimates",
                            detail: yieldEstimationDetail
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        YieldReportsListView()
                    } label: {
                        hubOption(
                            icon: "list.clipboard.fill",
                            iconGradient: [.indigo, .blue],
                            title: "Yield Reports",
                            subtitle: "Block summaries & estimation jobs",
                            detail: yieldReportsDetail
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        DamageRecordsListView()
                    } label: {
                        hubOption(
                            icon: "exclamationmark.triangle.fill",
                            iconGradient: [.red, .orange],
                            title: "Record Damage",
                            subtitle: "Frost, hail, wind & more",
                            detail: damageDetail
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Yield & Damage")
        .navigationBarTitleDisplayMode(.large)
    }

    private var headerCard: some View {
        HStack(spacing: 0) {
            yieldStat(
                value: "\(store.yieldSessions.count)",
                label: "Sessions",
                icon: "chart.bar.fill",
                color: .purple
            )
            yieldStat(
                value: "\(estimatedBlockCount)",
                label: "Blocks Est.",
                icon: "square.grid.2x2",
                color: .indigo
            )
            yieldStat(
                value: "\(store.damageRecords.count)",
                label: "Damage",
                icon: "exclamationmark.triangle",
                color: .red
            )
        }
        .padding(.vertical, 16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
    }

    private func yieldStat(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(value)
                .font(.title2.weight(.bold).monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func hubOption(
        icon: String,
        iconGradient: [Color],
        title: String,
        subtitle: String,
        detail: String?
    ) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(colors: iconGradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
    }

    private var estimatedBlockCount: Int {
        Set(store.yieldSessions.flatMap(\.selectedPaddockIds)).count
    }

    private var yieldEstimationDetail: String? {
        let count = store.yieldSessions.count
        guard count > 0 else { return nil }
        return "\(count) session\(count == 1 ? "" : "s") recorded"
    }

    private var yieldReportsDetail: String? {
        let blocks = estimatedBlockCount
        guard blocks > 0 else { return nil }
        return "\(blocks) block\(blocks == 1 ? "" : "s") estimated"
    }

    private var damageDetail: String? {
        let count = store.damageRecords.count
        guard count > 0 else { return nil }
        return "\(count) damage record\(count == 1 ? "" : "s")"
    }
}
