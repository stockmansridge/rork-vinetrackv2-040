import SwiftUI

/// Lightweight ripeness surfaces shown outside the dedicated
/// Optimal Ripeness hub:
///
/// 1. `BlockRipenessChip` — compact per-block/per-variety chip used in
///    the block detail editor so growers can see how close that
///    specific block is to its target GDD without leaving the form.
/// 2. `RipenessWatchTile` — Home dashboard summary tile that highlights
///    the variety closest to its optimal GDD, linking through to the
///    full Optimal Ripeness hub.
///
/// All maths reuse `DegreeDayService` + `GrapeVariety.optimalGDD` +
/// per-block phenology — no new schema, no changes to the underlying
/// GDD calculation.

// MARK: - Shared math helpers

private enum RipenessMath {
    static func seasonStartDate(settings: AppSettings) -> Date {
        let cal = Calendar.current
        let now = Date()
        let month = settings.seasonStartMonth
        let day = settings.seasonStartDay
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

    struct BlockTotal {
        let total: Double
        let series: [(date: Date, daily: Double, cumulative: Double, interpolated: Bool)]
    }

    @MainActor
    static func blockTotal(
        block: Paddock,
        store: MigratedDataStore,
        degreeDayService: DegreeDayService
    ) -> BlockTotal? {
        guard let stationId = store.settings.weatherStationId, !stationId.isEmpty else { return nil }
        let cal = Calendar.current
        let now = Date()
        let oneYearAgo = cal.date(byAdding: .year, value: -1, to: now) ?? now
        let seasonStart = seasonStartDate(settings: store.settings)
        let resetDefault = store.settings.resetMode
        let modeDefault = store.settings.calculationMode
        let resetMode = block.effectiveResetMode(defaultMode: resetDefault)
        guard let resetDate = block.resetDate(for: resetMode, seasonStart: seasonStart),
              resetDate <= now, resetDate >= oneYearAgo else { return nil }
        let calcMode = block.effectiveCalculationMode(defaultMode: modeDefault)
        let latitude = store.settings.vineyardLatitude ?? store.paddockCentroidLatitude
        let series = degreeDayService.dailyGDDSeries(
            stationId: stationId,
            from: cal.startOfDay(for: resetDate),
            to: cal.startOfDay(for: now),
            latitude: latitude,
            useBEDD: calcMode.useBEDD
        )
        let total = series.last?.cumulative ?? 0
        return BlockTotal(total: total, series: series)
    }

    static func daysToTarget(total: Double, target: Double, series: [(date: Date, daily: Double, cumulative: Double, interpolated: Bool)]) -> Int? {
        if total >= target { return 0 }
        guard series.count >= 14 else { return nil }
        let recent = Array(series.suffix(14))
        let gained = (recent.last?.cumulative ?? 0) - (recent.first?.cumulative ?? 0)
        let perDay = gained / Double(max(recent.count - 1, 1))
        guard perDay > 0 else { return nil }
        let remaining = target - total
        return Int((remaining / perDay).rounded(.up))
    }

    static func progressColor(progress: Double) -> Color {
        switch progress {
        case 0.98...: return VineyardTheme.leafGreen
        case 0.9..<0.98: return .orange
        default: return .blue
        }
    }
}

// MARK: - Block detail chip

/// Compact ripeness chip for a single (block, variety) pair. Drops
/// into the block editor's variety list so growers can see how close
/// the block is to that variety's optimal GDD.
struct BlockRipenessChip: View {
    @Environment(MigratedDataStore.self) private var store
    @Environment(DegreeDayService.self) private var degreeDayService

    let paddockId: UUID
    let varietyId: UUID

    private var paddock: Paddock? { store.paddocks.first(where: { $0.id == paddockId }) }
    private var variety: GrapeVariety? { store.grapeVariety(for: varietyId) }
    private var hasWeatherStation: Bool {
        if let id = store.settings.weatherStationId, !id.isEmpty { return true }
        return false
    }

    private var resetMode: GDDResetMode? {
        guard let paddock else { return nil }
        return paddock.effectiveResetMode(defaultMode: store.settings.resetMode)
    }

    private var hasResetData: Bool {
        guard let paddock, let mode = resetMode else { return false }
        switch mode {
        case .seasonStart: return true
        case .budburst: return paddock.budburstDate != nil
        case .flowering: return paddock.floweringDate != nil
        case .veraison: return paddock.veraisonDate != nil
        }
    }

    private var blockTotal: RipenessMath.BlockTotal? {
        guard let paddock else { return nil }
        return RipenessMath.blockTotal(block: paddock, store: store, degreeDayService: degreeDayService)
    }

    private var progress: Double {
        guard let target = variety?.optimalGDD, target > 0, let total = blockTotal?.total else { return 0 }
        return min(1.0, max(0, total / target))
    }

    private var caveatMessage: String? {
        if !hasWeatherStation {
            return "Add a weather station to project ripeness"
        }
        if !hasResetData, let mode = resetMode {
            switch mode {
            case .budburst: return "Set budburst date to project ripeness"
            case .flowering: return "Set flowering date to project ripeness"
            case .veraison: return "Set veraison date to project ripeness"
            case .seasonStart: return "Insufficient season data"
            }
        }
        return nil
    }

    var body: some View {
        NavigationLink {
            VarietyGDDDetailView(varietyId: varietyId)
        } label: {
            content
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        if let caveat = caveatMessage {
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Ripeness: \(caveat)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        } else if let total = blockTotal?.total, let target = variety?.optimalGDD, target > 0 {
            let color = RipenessMath.progressColor(progress: progress)
            let series = blockTotal?.series ?? []
            let days = RipenessMath.daysToTarget(total: total, target: target, series: series)
            let projected: Date? = {
                guard let d = days, d > 0 else { return nil }
                return Calendar.current.date(byAdding: .day, value: d, to: Date())
            }()

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "thermometer.sun.fill")
                        .font(.caption)
                        .foregroundStyle(color)
                    Text("Ripeness")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    if progress >= 1.0 {
                        Label("Ready", systemImage: "checkmark.seal.fill")
                            .font(.caption2.weight(.semibold))
                            .labelStyle(.titleAndIcon)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(VineyardTheme.leafGreen.opacity(0.18), in: .capsule)
                            .foregroundStyle(VineyardTheme.leafGreen)
                    } else {
                        Text("\(Int(progress * 100))% of optimal")
                            .font(.caption2.monospacedDigit().weight(.semibold))
                            .foregroundStyle(color)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(.tertiarySystemFill))
                        Capsule().fill(color.gradient)
                            .frame(width: max(4, geo.size.width * progress))
                    }
                }
                .frame(height: 5)

                HStack(spacing: 6) {
                    Text("\(Int(total)) / \(Int(target)) GDD")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    if let days, days > 0, let projected {
                        Image(systemName: "calendar.badge.clock")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                        Text("~\(days)d • \(projected.formatted(.dateTime.day().month(.abbreviated)))")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    } else if days == nil && progress < 1.0 {
                        Text("Not enough data to project")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        } else {
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Ripeness: insufficient recent data")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Home dashboard tile

/// Home dashboard "Ripeness Watch" tile — surfaces the variety closest
/// to its optimal GDD across allocated blocks. Tapping opens the full
/// Optimal Ripeness hub.
struct RipenessWatchTile: View {
    @Environment(MigratedDataStore.self) private var store
    @Environment(DegreeDayService.self) private var degreeDayService

    private var hasWeatherStation: Bool {
        if let id = store.settings.weatherStationId, !id.isEmpty { return true }
        return false
    }

    private struct VarietyStatus {
        let variety: GrapeVariety
        let total: Double
        let target: Double
        let progress: Double
        let days: Int?
        let blockCount: Int
    }

    private var allocatedVarieties: [GrapeVariety] {
        store.grapeVarieties.filter { variety in
            store.orderedPaddocks.contains(where: { p in
                p.varietyAllocations.contains(where: { $0.varietyId == variety.id })
            })
        }
    }

    private var topVariety: VarietyStatus? {
        guard hasWeatherStation else { return nil }
        var results: [VarietyStatus] = []
        for variety in allocatedVarieties {
            let blocks = store.orderedPaddocks.filter { p in
                p.varietyAllocations.contains(where: { $0.varietyId == variety.id })
            }
            var totals: [RipenessMath.BlockTotal] = []
            for block in blocks {
                if let bt = RipenessMath.blockTotal(block: block, store: store, degreeDayService: degreeDayService) {
                    totals.append(bt)
                }
            }
            guard !totals.isEmpty else { continue }
            let avg = totals.map(\.total).reduce(0, +) / Double(totals.count)
            let target = variety.optimalGDD
            guard target > 0 else { continue }
            let progress = min(1.0, max(0, avg / target))
            let longest = totals.max(by: { $0.series.count < $1.series.count })?.series ?? []
            let days = RipenessMath.daysToTarget(total: avg, target: target, series: longest)
            results.append(VarietyStatus(
                variety: variety,
                total: avg,
                target: target,
                progress: progress,
                days: days,
                blockCount: blocks.count
            ))
        }
        return results.max(by: { $0.progress < $1.progress })
    }

    var body: some View {
        NavigationLink {
            OptimalRipenessHubView()
        } label: {
            VineyardCard {
                content
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }

    @ViewBuilder
    private var content: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 48, height: 48)
                Image(systemName: "thermometer.sun.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.orange)
            }

            if let status = topVariety {
                let color = RipenessMath.progressColor(progress: status.progress)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("Ripeness Watch")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        if status.progress >= 1.0 {
                            Label("Ready", systemImage: "checkmark.seal.fill")
                                .font(.caption2.weight(.semibold))
                                .labelStyle(.titleAndIcon)
                                .foregroundStyle(VineyardTheme.leafGreen)
                        }
                    }
                    Text("\(status.variety.name) — \(Int(status.progress * 100))% of optimal")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color(.tertiarySystemFill))
                            Capsule().fill(color.gradient)
                                .frame(width: max(4, geo.size.width * status.progress))
                        }
                    }
                    .frame(height: 5)
                    HStack(spacing: 6) {
                        if let days = status.days, days > 0 {
                            Image(systemName: "calendar.badge.clock")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                            Text("Est. ripeness: \(days) day\(days == 1 ? "" : "s")")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        } else if status.progress >= 1.0 {
                            Text("Target reached — review harvest plan")
                                .font(.caption2)
                                .foregroundStyle(VineyardTheme.leafGreen)
                        } else {
                            Text("Not enough recent data to project")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer(minLength: 0)
                        Text("View Optimal Ripeness")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(VineyardTheme.info)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ripeness Watch")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(emptyTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(emptySubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }

    private var emptyTitle: String {
        if !hasWeatherStation { return "Weather station required" }
        if allocatedVarieties.isEmpty { return "No tracked varieties yet" }
        return "Awaiting season data"
    }

    private var emptySubtitle: String {
        if !hasWeatherStation {
            return "Connect a station in Setup to track GDD and harvest timing."
        }
        if allocatedVarieties.isEmpty {
            return "Allocate varieties to a block to track ripeness."
        }
        return "Set block budburst dates so we can project optimal ripeness."
    }
}
