import SwiftUI

/// Hub showing every tracked block with its current GDD progress
/// toward the allocated variety's optimal harvest target, plus a
/// compact setup checklist that highlights anything missing for an
/// accurate prediction.
///
/// All maths come from `DegreeDayService` + `GrapeVariety.optimalGDD`
/// + per-block phenology (budburst/flowering/veraison). The view also
/// cascades through the configured GDD sources (Davis WeatherLink ->
/// Weather Underground -> Open-Meteo Archive), surfacing the actual
/// source that produced the numbers on screen.
struct OptimalRipenessHubView: View {
    @Environment(MigratedDataStore.self) private var store
    @Environment(DegreeDayService.self) private var degreeDayService

    private var candidates: [RipenessSourceCandidate] {
        RipenessMath.candidates(store: store)
    }

    private var activeSource: GDDSource? {
        if let resolved = degreeDayService.lastSource,
           candidates.contains(where: { $0.source == resolved }) {
            return resolved
        }
        return candidates.first?.source
    }

    fileprivate struct BlockRow: Identifiable {
        let id: UUID
        let block: Paddock
        let variety: GrapeVariety?
        let resetDate: Date?
        let total: Double
        let target: Double
        let series: [(date: Date, daily: Double, cumulative: Double, interpolated: Bool)]
    }

    private var blockRows: [BlockRow] {
        guard let source = activeSource else { return [] }
        let cal = Calendar.current
        let now = Date()
        let oneYearAgo = cal.date(byAdding: .year, value: -1, to: now) ?? now
        let seasonStart = RipenessMath.seasonStartDate(settings: store.settings)
        let resetDefault = store.settings.resetMode
        let modeDefault = store.settings.calculationMode
        let latitude = store.settings.vineyardLatitude ?? store.paddockCentroidLatitude
        var rows: [BlockRow] = []
        for block in store.orderedPaddocks {
            // Pick the primary allocated variety (highest area share).
            let alloc = block.varietyAllocations
                .max(by: { $0.percent < $1.percent })
            let variety: GrapeVariety? = alloc.flatMap { store.grapeVariety(for: $0.varietyId) }
            let resetMode = block.effectiveResetMode(defaultMode: resetDefault)
            let resetDate = block.resetDate(for: resetMode, seasonStart: seasonStart)
            let calcMode = block.effectiveCalculationMode(defaultMode: modeDefault)
            var series: [(date: Date, daily: Double, cumulative: Double, interpolated: Bool)] = []
            var total: Double = 0
            if let r = resetDate, r <= now, r >= oneYearAgo {
                series = degreeDayService.dailyGDDSeries(
                    stationId: source.sourceKey,
                    from: cal.startOfDay(for: r),
                    to: cal.startOfDay(for: now),
                    latitude: latitude,
                    useBEDD: calcMode.useBEDD
                )
                total = series.last?.cumulative ?? 0
            }
            rows.append(BlockRow(
                id: block.id,
                block: block,
                variety: variety,
                resetDate: resetDate,
                total: total,
                target: variety?.optimalGDD ?? 0,
                series: series
            ))
        }
        return rows.sorted { a, b in
            let pa = a.target > 0 ? a.total / a.target : 0
            let pb = b.target > 0 ? b.total / b.target : 0
            return pa > pb
        }
    }

    private var checklist: SetupChecklist {
        SetupChecklist.build(store: store, candidates: candidates)
    }

    var body: some View {
        Group {
            if store.orderedPaddocks.isEmpty {
                ContentUnavailableView {
                    Label { Text("No Blocks") } icon: { GrapeLeafIcon(size: 44) }
                } description: {
                    Text("Add blocks under Setup > Blocks to track ripeness.")
                }
            } else {
                List {
                    if !checklist.items.isEmpty {
                        Section {
                            SetupChecklistCard(checklist: checklist)
                                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                                .listRowBackground(Color.clear)
                        }
                    }

                    if let source = activeSource {
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

                    if activeSource != nil {
                        Section {
                            ForEach(blockRows) { row in
                                if let variety = row.variety {
                                    NavigationLink {
                                        VarietyGDDDetailView(varietyId: variety.id)
                                    } label: {
                                        BlockRipenessRow(row: row)
                                    }
                                } else {
                                    BlockRipenessRow(row: row)
                                }
                            }
                        } header: {
                            Text("Blocks")
                        } footer: {
                            Text("Status uses the block's reset date (season start, budburst, flowering or veraison) and the allocated variety's optimal GDD target. Days to target is projected from the last 14 days of accumulation.")
                                .font(.caption)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Optimal Ripeness")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: candidatesKey) {
            await loadGDDIfNeeded()
        }
    }

    private var candidatesKey: String {
        candidates.map(\.source.sourceKey).joined(separator: "|")
    }

    private func loadGDDIfNeeded() async {
        let cands = candidates
        guard !cands.isEmpty else { return }
        let seasonStart = RipenessMath.fetchRangeStart(settings: store.settings)
        let useBEDD = store.settings.calculationMode.useBEDD
        // If the current `lastSource` is one of the configured candidates
        // and we don't need a daily refresh yet, skip refetching.
        if let last = degreeDayService.lastSource,
           cands.contains(where: { $0.source == last }),
           !degreeDayService.needsDailyRefresh(for: last.sourceKey) {
            return
        }
        for candidate in cands {
            switch candidate.source {
            case .davisWeatherLink(let stationId):
                await degreeDayService.fetchSeasonDavis(
                    stationId: stationId,
                    vineyardId: store.selectedVineyardId,
                    useProxy: candidate.usesProxy,
                    latitude: store.settings.vineyardLatitude ?? store.paddockCentroidLatitude,
                    seasonStart: seasonStart,
                    useBEDD: useBEDD
                )
            case .weatherUnderground, .openMeteoArchive:
                await degreeDayService.fetchSeason(
                    source: candidate.source,
                    seasonStart: seasonStart,
                    useBEDD: useBEDD
                )
            }
            if degreeDayService.lastSource == candidate.source,
               degreeDayService.hasUsableData(for: candidate.source) {
                return // success, stop cascading
            }
        }
    }
}

// MARK: - Block row

private struct BlockRipenessRow: View {
    let row: OptimalRipenessHubView.BlockRow

    private var progress: Double {
        guard row.target > 0 else { return 0 }
        return min(1.0, max(0, row.total / row.target))
    }

    private var status: (label: String, color: Color, icon: String) {
        if row.target <= 0 {
            return ("No target", .secondary, "questionmark.circle")
        }
        if row.resetDate == nil {
            return ("No reset", .secondary, "calendar.badge.exclamationmark")
        }
        switch progress {
        case 1.05...: return ("Past optimal", .red, "exclamationmark.triangle.fill")
        case 0.98...: return ("In optimal window", VineyardTheme.leafGreen, "checkmark.seal.fill")
        case 0.85..<0.98: return ("Approaching optimal", .orange, "thermometer.sun.fill")
        case 0.4..<0.85: return ("Tracking", .blue, "chart.line.uptrend.xyaxis")
        default: return ("Early", .secondary, "leaf")
        }
    }

    private var progressColor: Color { status.color }

    private var daysToTarget: Int? {
        guard row.target > 0 else { return nil }
        if row.total >= row.target { return 0 }
        guard row.series.count >= 14 else { return nil }
        let recent = Array(row.series.suffix(14))
        let gained = (recent.last?.cumulative ?? 0) - (recent.first?.cumulative ?? 0)
        let perDay = gained / Double(max(recent.count - 1, 1))
        guard perDay > 0 else { return nil }
        let remaining = row.target - row.total
        return Int((remaining / perDay).rounded(.up))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.block.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        if let variety = row.variety {
                            Text(variety.name)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        } else {
                            Text("No variety")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.orange)
                        }
                        if let r = row.resetDate {
                            Text("\u{2022} since \(r.formatted(.dateTime.day().month(.abbreviated)))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                if row.target > 0 {
                    VStack(alignment: .trailing, spacing: 1) {
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text("\(Int(row.total))")
                                .font(.subheadline.weight(.bold).monospacedDigit())
                                .foregroundStyle(progressColor)
                            Text("/ \(Int(row.target))")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Text("\(Int(progress * 100))%")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(progressColor)
                    }
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
                Image(systemName: status.icon)
                    .font(.caption2)
                    .foregroundStyle(progressColor)
                Text(status.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(progressColor)
                Spacer()
                if let days = daysToTarget, days > 0 {
                    Image(systemName: "calendar.badge.clock")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Text("\u{2248}\(days) day\(days == 1 ? "" : "s")")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Setup checklist

private struct SetupChecklistItem: Identifiable {
    let id = UUID()
    let title: String
    let detail: String?
    let ok: Bool
    /// Friendly hint shown when not satisfied. `nil` when no action surface
    /// exists yet for this item.
    let action: String?
}

private struct SetupChecklist {
    let items: [SetupChecklistItem]

    @MainActor
    static func build(store: MigratedDataStore, candidates: [RipenessSourceCandidate]) -> SetupChecklist {
        var items: [SetupChecklistItem] = []

        // 1. Weather source
        let weatherOK = !candidates.isEmpty
        let weatherDetail: String? = candidates.first.map { c in
            switch c.source {
            case .davisWeatherLink: return "Davis WeatherLink"
            case .weatherUnderground: return "Weather Underground"
            case .openMeteoArchive: return "Open-Meteo Archive"
            }
        }
        items.append(SetupChecklistItem(
            title: "Weather source",
            detail: weatherDetail,
            ok: weatherOK,
            action: weatherOK ? nil : "Configure a weather source"
        ))

        // 2. Block varieties
        let blocks = store.orderedPaddocks
        let blocksWithoutVariety = blocks.filter { $0.varietyAllocations.isEmpty }
        items.append(SetupChecklistItem(
            title: "Block varieties",
            detail: blocksWithoutVariety.isEmpty
                ? "All blocks have a variety"
                : "\(blocksWithoutVariety.count) block\(blocksWithoutVariety.count == 1 ? "" : "s") missing a variety",
            ok: blocksWithoutVariety.isEmpty && !blocks.isEmpty,
            action: blocksWithoutVariety.isEmpty ? nil : "Add a variety to each block"
        ))

        // 3. Season start date
        let s = store.settings
        let monthName = Calendar.current.standaloneMonthSymbols[max(0, min(11, s.seasonStartMonth - 1))]
        items.append(SetupChecklistItem(
            title: "Season start date",
            detail: "\(s.seasonStartDay) \(monthName)",
            ok: true,
            action: nil
        ))

        // 4. Variety GDD targets
        let allocatedVarietyIds = Set(blocks.flatMap { $0.varietyAllocations.map(\.varietyId) })
        let allocatedVarieties = store.grapeVarieties.filter { allocatedVarietyIds.contains($0.id) }
        let missingTargets = allocatedVarieties.filter { $0.optimalGDD <= 0 }
        items.append(SetupChecklistItem(
            title: "Variety GDD targets",
            detail: missingTargets.isEmpty
                ? "\(allocatedVarieties.count) variet\(allocatedVarieties.count == 1 ? "y" : "ies") set"
                : "Missing: \(missingTargets.map(\.name).joined(separator: ", "))",
            ok: missingTargets.isEmpty && !allocatedVarieties.isEmpty,
            action: missingTargets.isEmpty ? nil : "Set GDD target for each variety"
        ))

        // 5. Block location (for Open-Meteo fallback)
        let hasCoords = store.settings.vineyardLatitude != nil
            || store.paddockCentroidLatitude != nil
        items.append(SetupChecklistItem(
            title: "Block location",
            detail: hasCoords ? "Coordinates available" : "No coordinates",
            ok: hasCoords,
            action: hasCoords ? nil : "Add vineyard coordinates or paddock polygons"
        ))

        return SetupChecklist(items: items)
    }
}

private struct SetupChecklistCard: View {
    let checklist: SetupChecklist

    @State private var expanded: Bool = false

    private var pending: Int {
        checklist.items.filter { !$0.ok }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: pending == 0 ? "checkmark.seal.fill" : "list.bullet.clipboard")
                        .font(.callout)
                        .foregroundStyle(pending == 0 ? VineyardTheme.leafGreen : .orange)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Setup checklist")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(pending == 0
                             ? "All set for ripeness tracking"
                             : "\(pending) item\(pending == 1 ? "" : "s") need attention")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(checklist.items) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: item.ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                .font(.callout)
                                .foregroundStyle(item.ok ? VineyardTheme.leafGreen : .orange)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title)
                                    .font(.caption.weight(.semibold))
                                if let d = item.detail {
                                    Text(d)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                if !item.ok, let a = item.action {
                                    Text(a)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(VineyardTheme.info)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
    }
}
