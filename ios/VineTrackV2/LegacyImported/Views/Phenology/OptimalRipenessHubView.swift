import SwiftUI

/// Hub listing every grape variety with its current GDD progress
/// against the variety's optimal harvest target. Tapping a row drills
/// into `VarietyGDDDetailView` for the full chart + projection.
///
/// All maths come from existing `DegreeDayService` + `GrapeVariety.optimalGDD`
/// + per-block phenology dates (budburst/flowering/veraison). This view only
/// surfaces what was already computed but not exposed in V2 UI.
struct OptimalRipenessHubView: View {
    @Environment(MigratedDataStore.self) private var store
    @Environment(DegreeDayService.self) private var degreeDayService

    private var sortedVarieties: [GrapeVariety] {
        store.grapeVarieties
            .filter { variety in
                store.orderedPaddocks.contains(where: { p in
                    p.varietyAllocations.contains(where: { $0.varietyId == variety.id })
                })
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var unallocatedVarieties: [GrapeVariety] {
        store.grapeVarieties
            .filter { variety in
                !store.orderedPaddocks.contains(where: { p in
                    p.varietyAllocations.contains(where: { $0.varietyId == variety.id })
                })
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var weatherState: RipenessWeatherState {
        RipenessMath.weatherState(store: store)
    }

    var body: some View {
        Group {
            if store.grapeVarieties.isEmpty {
                ContentUnavailableView {
                    Label { Text("No Varieties") } icon: { GrapeLeafIcon(size: 44) }
                } description: {
                    Text("Add grape varieties under Setup → Grape Varieties to track ripeness.")
                }
            } else if case .notConfigured = weatherState {
                ContentUnavailableView {
                    Label("Weather Source Required", systemImage: "thermometer.sun")
                } description: {
                    Text("Add vineyard coordinates under Setup or connect a weather station to compute growing degree days for ripeness predictions.")
                }
            } else {
                List {
                    if case .ready(let source) = weatherState {
                        Section {
                            HStack(spacing: 8) {
                                Image(systemName: "thermometer.sun.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                Text("GDD source")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(source.displayName)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.primary)
                                if degreeDayService.isLoading {
                                    ProgressView().controlSize(.mini)
                                }
                            }
                        }
                    }
                    if !sortedVarieties.isEmpty {
                        Section {
                            ForEach(sortedVarieties) { variety in
                                NavigationLink {
                                    VarietyGDDDetailView(varietyId: variety.id)
                                } label: {
                                    VarietyRipenessRow(varietyId: variety.id)
                                }
                            }
                        } header: {
                            Text("Tracked Varieties")
                        } footer: {
                            Text("Progress is the average GDD across blocks allocated to each variety. Days to target uses the last 14 days of accumulation.")
                                .font(.caption)
                        }
                    }

                    if !unallocatedVarieties.isEmpty {
                        Section {
                            ForEach(unallocatedVarieties) { variety in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(variety.name)
                                            .font(.subheadline.weight(.semibold))
                                        Text("Optimal: \(Int(variety.optimalGDD)) GDD")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("No blocks")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color(.tertiarySystemFill), in: .capsule)
                                }
                            }
                        } header: {
                            Text("Unallocated Varieties")
                        } footer: {
                            Text("Allocate these varieties to a block to track their season GDD.")
                                .font(.caption)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Optimal Ripeness")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: weatherStateKey) {
            await loadGDDIfNeeded()
        }
    }

    private var weatherStateKey: String {
        switch weatherState {
        case .ready(let source): return source.sourceKey
        case .notConfigured: return "none"
        }
    }

    private func loadGDDIfNeeded() async {
        guard case .ready(let source) = weatherState else { return }
        if !degreeDayService.needsDailyRefresh(for: source.sourceKey),
           degreeDayService.lastSource == source {
            return
        }
        let start = RipenessMath.fetchRangeStart(settings: store.settings)
        await degreeDayService.fetchSeason(
            source: source,
            seasonStart: start,
            useBEDD: store.settings.calculationMode.useBEDD
        )
    }
}

/// Compact summary row for a single variety: current GDD,
/// optimal target, progress bar, and estimated days to ripeness.
private struct VarietyRipenessRow: View {
    @Environment(MigratedDataStore.self) private var store
    @Environment(DegreeDayService.self) private var degreeDayService

    let varietyId: UUID

    private var variety: GrapeVariety? { store.grapeVariety(for: varietyId) }

    private var allocatedBlocks: [Paddock] {
        store.orderedPaddocks.filter { p in
            p.varietyAllocations.contains(where: { $0.varietyId == varietyId })
        }
    }

    private var seasonStartDate: Date {
        let cal = Calendar.current
        let now = Date()
        let month = store.settings.seasonStartMonth
        let day = store.settings.seasonStartDay
        let currentMonth = cal.component(.month, from: now)
        let currentDay = cal.component(.day, from: now)
        let year = cal.component(.year, from: now)
        let startYear: Int
        if currentMonth > month || (currentMonth == month && currentDay >= day) {
            startYear = year
        } else {
            startYear = year - 1
        }
        return cal.date(from: DateComponents(year: startYear, month: month, day: day)) ?? now
    }

    private var effectiveLatitude: Double? {
        store.settings.vineyardLatitude ?? store.paddockCentroidLatitude
    }

    private struct BlockTotal {
        let total: Double
        let series: [(date: Date, daily: Double, cumulative: Double, interpolated: Bool)]
    }

    private var blockTotals: [BlockTotal] {
        guard let source = RipenessMath.weatherState(store: store).source else { return [] }
        let stationId = source.sourceKey
        let cal = Calendar.current
        let now = Date()
        let oneYearAgo = cal.date(byAdding: .year, value: -1, to: now) ?? now
        let seasonStart = seasonStartDate
        let resetDefault = store.settings.resetMode
        let modeDefault = store.settings.calculationMode
        var result: [BlockTotal] = []
        for block in allocatedBlocks {
            let resetMode = block.effectiveResetMode(defaultMode: resetDefault)
            guard let resetDate = block.resetDate(for: resetMode, seasonStart: seasonStart),
                  resetDate <= now, resetDate >= oneYearAgo else { continue }
            let calcMode = block.effectiveCalculationMode(defaultMode: modeDefault)
            let series = degreeDayService.dailyGDDSeries(
                stationId: stationId,
                from: cal.startOfDay(for: resetDate),
                to: cal.startOfDay(for: now),
                latitude: effectiveLatitude,
                useBEDD: calcMode.useBEDD
            )
            let total = series.last?.cumulative ?? 0
            result.append(BlockTotal(total: total, series: series))
        }
        return result
    }

    private var averageTotal: Double {
        let totals = blockTotals
        guard !totals.isEmpty else { return 0 }
        return totals.map(\.total).reduce(0, +) / Double(totals.count)
    }

    private var progress: Double {
        guard let target = variety?.optimalGDD, target > 0 else { return 0 }
        return min(1.0, max(0, averageTotal / target))
    }

    private var progressColor: Color {
        switch progress {
        case 0.98...: return VineyardTheme.leafGreen
        case 0.9..<0.98: return .orange
        default: return .blue
        }
    }

    private var daysToTarget: Int? {
        guard let target = variety?.optimalGDD else { return nil }
        if averageTotal >= target { return 0 }
        let totals = blockTotals
        guard let longest = totals.max(by: { $0.series.count < $1.series.count })?.series,
              longest.count >= 14 else { return nil }
        let recent = Array(longest.suffix(14))
        let gained = (recent.last?.cumulative ?? 0) - (recent.first?.cumulative ?? 0)
        let perDay = gained / Double(max(recent.count - 1, 1))
        guard perDay > 0 else { return nil }
        let remaining = target - averageTotal
        return Int((remaining / perDay).rounded(.up))
    }

    private var projectedDate: Date? {
        guard let days = daysToTarget, days > 0 else { return nil }
        return Calendar.current.date(byAdding: .day, value: days, to: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(variety?.name ?? "—")
                        .font(.subheadline.weight(.semibold))
                    Text("\(allocatedBlocks.count) block\(allocatedBlocks.count == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(Int(averageTotal))")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(progressColor)
                        Text("/ \(Int(variety?.optimalGDD ?? 0))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Text("\(Int(progress * 100))%")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(progressColor)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.tertiarySystemFill))
                    Capsule().fill(progressColor.gradient)
                        .frame(width: max(4, geo.size.width * progress))
                }
            }
            .frame(height: 6)

            HStack(spacing: 6) {
                if let days = daysToTarget {
                    if days == 0 {
                        Label("Ready to harvest", systemImage: "checkmark.seal.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(VineyardTheme.leafGreen)
                    } else if let projected = projectedDate {
                        Image(systemName: "calendar.badge.clock")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                        Text("~\(days) day\(days == 1 ? "" : "s") • \(projected.formatted(.dateTime.day().month(.abbreviated)))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                } else if blockTotals.isEmpty {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Set block budburst date to project ripeness")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Not enough data to project")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .padding(.vertical, 4)
    }
}
