import SwiftUI

struct OperationsHubView: View {
    @Environment(MigratedDataStore.self) private var store

    var body: some View {
        List {
            Section {
                NavigationLink {
                    WorkTasksHubView()
                } label: {
                    operationRow(
                        title: "Work Tasks",
                        subtitle: "Plan and log vineyard work",
                        icon: "checklist",
                        tint: VineyardTheme.olive,
                        count: store.workTasks.count
                    )
                }
                NavigationLink {
                    MaintenanceLogListView()
                } label: {
                    operationRow(
                        title: "Maintenance",
                        subtitle: "Equipment & tractor logs",
                        icon: "wrench.and.screwdriver.fill",
                        tint: VineyardTheme.earthBrown,
                        count: store.maintenanceLogs.count
                    )
                }
                NavigationLink {
                    YieldHubView()
                } label: {
                    operationRow(
                        title: "Yield & Damage",
                        subtitle: "Estimates, harvest, damage records",
                        icon: "scalemass.fill",
                        tint: VineyardTheme.vineRed,
                        count: nil
                    )
                }
            } header: {
                SettingsSectionHeader(title: "Operations", symbol: "rectangle.stack.fill", color: .orange)
            }

            Section {
                NavigationLink {
                    IrrigationRecommendationView()
                } label: {
                    operationRow(
                        title: "Irrigation Advisor",
                        subtitle: "5-day forecast & water planning",
                        icon: "drop.fill",
                        tint: .cyan,
                        count: nil
                    )
                }
            } header: {
                SettingsSectionHeader(title: "Irrigation", symbol: "drop.fill", color: .cyan)
            }

            Section {
                NavigationLink {
                    GrowthStageReportView()
                } label: {
                    operationRow(
                        title: "Growth Stage Report",
                        subtitle: "Phenology & E-L stages",
                        icon: "leaf.arrow.triangle.circlepath",
                        tint: VineyardTheme.leafGreen,
                        count: nil
                    )
                }
                NavigationLink {
                    GrowthStageImagesSettingsView()
                } label: {
                    operationRow(
                        title: "E-L Stage Images",
                        subtitle: "Reference photos",
                        icon: "photo.on.rectangle.angled",
                        tint: VineyardTheme.leafGreen,
                        count: nil
                    )
                }
            } header: {
                SettingsSectionHeader(title: "Phenology", symbol: "leaf.fill", color: VineyardTheme.leafGreen)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Operations")
    }

    private func operationRow(title: String, subtitle: String, icon: String, tint: Color, count: Int?) -> some View {
        HStack(spacing: 12) {
            SettingsIconTile(symbol: icon, color: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let count {
                Text("\(count)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
