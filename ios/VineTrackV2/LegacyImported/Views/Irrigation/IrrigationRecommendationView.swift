import SwiftUI

struct IrrigationRecommendationView: View {
    @Environment(MigratedDataStore.self) private var store

    @State private var selectedPaddockId: UUID?
    @State private var forecastService = IrrigationForecastService()

    @State private var applicationRateText: String = ""
    @State private var kcText: String = "0.65"
    @State private var efficiencyText: String = "90"
    @State private var rainEffText: String = "80"
    @State private var replacementText: String = "100"
    @State private var bufferText: String = "0"
    @State private var didLoadFromSettings: Bool = false

    @State private var manualEToOverrides: [Date: String] = [:]
    @State private var manualRainOverrides: [Date: String] = [:]
    @State private var useManualInputs: Bool = false
    @State private var forecastDuration: Int = 5
    @State private var lastUpdated: Date?
    @State private var didAutoLoad: Bool = false

    // Recent actual rainfall (preferring Davis WeatherLink when configured).
    @State private var recentRainResult: RainfallHistoryResult?
    @State private var recentRainDays: Int = 7
    @State private var includeRecentActualRain: Bool = true
    @State private var isLoadingRecentRain: Bool = false

    private let durationOptions: [Int] = [3, 5, 7, 14]

    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case appRate, kc, efficiency, rainEff, replacement, buffer
        case manualEto(Date), manualRain(Date)
    }

    private var vineyardPaddocks: [Paddock] {
        guard let vid = store.selectedVineyard?.id else { return store.paddocks }
        return store.paddocks.filter { $0.vineyardId == vid }
    }

    private var selectedPaddock: Paddock? {
        guard let id = selectedPaddockId else { return nil }
        return store.paddocks.first(where: { $0.id == id })
    }

    private var latitude: Double? {
        store.settings.vineyardLatitude ?? store.paddockCentroidLatitude
    }

    private var longitude: Double? {
        store.settings.vineyardLongitude ?? store.paddockCentroidLongitude
    }

    private var settings: IrrigationSettings {
        IrrigationSettings(
            irrigationApplicationRateMmPerHour: parse(applicationRateText),
            cropCoefficientKc: parse(kcText, default: 0.65),
            irrigationEfficiencyPercent: parse(efficiencyText, default: 90),
            rainfallEffectivenessPercent: parse(rainEffText, default: 80),
            replacementPercent: parse(replacementText, default: 100),
            soilMoistureBufferMm: parse(bufferText)
        )
    }

    private var forecastDays: [ForecastDay] {
        guard let base = forecastService.forecast?.days, !base.isEmpty else { return [] }
        return base.map { day in
            let eto = manualEToOverrides[day.date].flatMap { Double($0) } ?? day.forecastEToMm
            let rain = manualRainOverrides[day.date].flatMap { Double($0) } ?? day.forecastRainMm
            return ForecastDay(date: day.date, forecastEToMm: eto, forecastRainMm: rain)
        }
    }

    /// Total recent actual rainfall (mm) eligible to offset the deficit.
    /// Only counts when the toggle is on and we actually have data.
    private var recentActualRainOffsetMm: Double {
        guard includeRecentActualRain, let r = recentRainResult else { return 0 }
        return r.dailyMm.values.reduce(0, +)
    }

    private var result: IrrigationRecommendationResult? {
        IrrigationCalculator.calculate(
            forecastDays: forecastDays,
            settings: settings,
            recentActualRainMm: recentActualRainOffsetMm
        )
    }

    private var missingItems: [String] {
        var items: [String] = []
        if latitude == nil || longitude == nil {
            items.append("Vineyard coordinates / weather source")
        }
        if settings.irrigationApplicationRateMmPerHour <= 0 {
            items.append("Irrigation application rate (mm/hr)")
        }
        if vineyardPaddocks.isEmpty {
            items.append("At least one block")
        }
        return items
    }

    var body: some View {
        Form {
            statusSection
            if !missingItems.isEmpty {
                missingSetupSection
            }
            recommendationSection
            recentRainSection
            rainfallCalendarSection
            blockSection
            forecastControlSection
            forecastDetailsSection
            dailyBreakdownDisclosure
            settingsSection
        }
        .navigationTitle("Irrigation Advisor")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
            }
        }
        .onAppear {
            if !didLoadFromSettings {
                loadParametersFromSettings()
                didLoadFromSettings = true
            }
            if selectedPaddockId == nil {
                selectedPaddockId = store.settings.irrigationAlertPaddockId ?? vineyardPaddocks.first?.id
            }
            applyPaddockDefaults()
            if !didAutoLoad {
                didAutoLoad = true
                if forecastService.forecast == nil, latitude != nil, longitude != nil {
                    Task { await loadForecast() }
                }
                if recentRainResult == nil, latitude != nil, longitude != nil {
                    Task { await loadRecentRainfall() }
                }
            }
        }
        .onChange(of: kcText) { _, _ in persistParameters() }
        .onChange(of: efficiencyText) { _, _ in persistParameters() }
        .onChange(of: rainEffText) { _, _ in persistParameters() }
        .onChange(of: replacementText) { _, _ in persistParameters() }
        .onChange(of: bufferText) { _, _ in persistParameters() }
        .onChange(of: selectedPaddockId) { _, _ in
            applyPaddockDefaults()
        }
        .onChange(of: forecastDuration) { _, newValue in
            persistForecastDuration(newValue)
            if latitude != nil, longitude != nil {
                Task { await loadForecast() }
            }
        }
        .onChange(of: recentRainDays) { _, _ in
            if latitude != nil, longitude != nil {
                Task { await loadRecentRainfall() }
            }
        }
    }

    // MARK: - Top status

    private var statusSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(.tint)
                    Text("Weather sources")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    if let updated = lastUpdated {
                        Text("Updated \(updated.formatted(.relative(presentation: .named)))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else if forecastService.isLoading {
                        Text("Loading…")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    sourceRow(
                        label: "Forecast",
                        value: forecastService.forecast?.source ?? "Open-Meteo Forecast",
                        icon: "cloud.sun.fill",
                        tint: Color.accentColor
                    )
                    sourceRow(
                        label: "Actual rain",
                        value: actualRainSourceValue,
                        icon: (recentRainResult?.isMeasured ?? false)
                            ? "sensor.tag.radiowaves.forward.fill"
                            : "externaldrive.connected.to.line.below.fill",
                        tint: (recentRainResult?.isMeasured ?? false) ? VineyardTheme.leafGreen : .secondary
                    )
                }

                if let r = recentRainResult, r.fallbackUsed {
                    Label("Using archive fallback for actual rainfall.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func sourceRow(label: String, value: String, icon: String, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(tint)
                .frame(width: 18)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 86, alignment: .leading)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
    }

    /// User-facing text shown on the right of the "Actual rain" row.
    /// Strips the "Source: " prefix produced by RainfallHistoryService so the
    /// label sits naturally beside "Actual rain:".
    private var actualRainSourceValue: String {
        guard let r = recentRainResult else {
            if isLoadingRecentRain { return "Loading…" }
            return "Automatic Historical Weather"
        }
        let raw = r.providerLabel
        if raw.hasPrefix("Source: ") {
            return String(raw.dropFirst("Source: ".count))
        }
        return raw
    }

    /// Short tag used inside the recommendation card sentence.
    private var actualRainShortSource: String {
        guard let r = recentRainResult else { return "Archive" }
        switch r.effectiveProvider {
        case .davis: return "Davis WeatherLink"
        case .wunderground: return "Weather Underground"
        case .automatic: return "Archive"
        }
    }

    private var missingSetupSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("Complete irrigation settings to calculate recommendations.", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                ForEach(missingItems, id: \.self) { item in
                    HStack(spacing: 6) {
                        Image(systemName: "circle")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(item)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Recent actual rainfall

    @ViewBuilder
    private var recentRainSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: (recentRainResult?.isMeasured ?? false)
                                      ? "sensor.tag.radiowaves.forward.fill"
                                      : "cloud.rain.fill")
                        .foregroundStyle((recentRainResult?.isMeasured ?? false) ? VineyardTheme.leafGreen : Color.accentColor)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(recentRainHeading)
                            .font(.subheadline.weight(.semibold))
                        Text(recentRainSourceLabel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    if isLoadingRecentRain {
                        ProgressView()
                    } else {
                        Button {
                            Task { await loadRecentRainfall() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                Picker("Window", selection: $recentRainDays) {
                    Text("24h").tag(1)
                    Text("48h").tag(2)
                    Text("7d").tag(7)
                    Text("14d").tag(14)
                }
                .pickerStyle(.segmented)

                if let warn = recentRainResult?.fallbackReason, recentRainResult?.fallbackUsed == true {
                    Text(warn)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }

                Toggle(isOn: $includeRecentActualRain) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Include recent actual rain")
                            .font(.subheadline)
                        Text(includeRecentActualRain
                             ? "Subtracted from forecast deficit (after rainfall effectiveness)."
                             : "Recent actual rain is shown but not used in the calculation.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(VineyardTheme.leafGreen)
            }
            .padding(.vertical, 4)
        } header: {
            Text("Recent Actual Rainfall")
        }
    }

    private var recentRainHeading: String {
        guard let r = recentRainResult else {
            return isLoadingRecentRain ? "Loading recent rainfall…" : "Recent rainfall: —"
        }
        let mm = r.dailyMm.values.reduce(0, +)
        let label = recentRainDays == 1 ? "24h" : (recentRainDays == 2 ? "48h" : "\(recentRainDays) days")
        return String(format: "Recent rainfall: %.1f mm over last \(label)", mm)
    }

    private var recentRainSourceLabel: String {
        guard let r = recentRainResult else { return "Source: —" }
        return r.providerLabel
    }

    // MARK: - Rainfall calendar entry

    private var rainfallCalendarSection: some View {
        Section {
            NavigationLink {
                RainfallCalendarView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "calendar")
                        .foregroundStyle(.tint)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Rainfall Calendar")
                            .font(.subheadline.weight(.semibold))
                        Text("Daily rainfall by month for the year")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Recommendation card

    @ViewBuilder
    private var recommendationSection: some View {
        Section("Recommendation") {
            if forecastService.isLoading && forecastService.forecast == nil {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Calculating recommendation…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } else if let error = forecastService.errorMessage, forecastService.forecast == nil {
                VStack(alignment: .leading, spacing: 8) {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                    Button {
                        Task { await loadForecast() }
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(.vertical, 4)
            } else if let result {
                recommendationCard(result)
            } else if latitude == nil || longitude == nil {
                Text("Set your vineyard location in Settings → Vineyard Setup, then return here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Recommendation will appear once the forecast loads.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func recommendationCard(_ result: IrrigationRecommendationResult) -> some View {
        let needsIrrigation = result.netDeficitMm > 0 && settings.irrigationApplicationRateMmPerHour > 0
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: needsIrrigation ? "drop.fill" : "checkmark.seal.fill")
                    .foregroundStyle(needsIrrigation ? VineyardTheme.vineRed : VineyardTheme.leafGreen)
                Text(needsIrrigation ? "Irrigation recommended" : "No irrigation needed")
                    .font(.headline)
                Spacer()
            }

            if needsIrrigation {
                Text(String(format: "%.1f hours", result.recommendedIrrigationHours))
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(VineyardTheme.leafGreen)
                    .monospacedDigit()
                Text(hoursMinutesString(result.recommendedIrrigationHours))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text(String(format: "Apply %.1f mm over the next %d days", result.grossIrrigationMm, result.dailyBreakdown.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Forecast rainfall meets vine demand for the next \(result.dailyBreakdown.count) days.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack(spacing: 14) {
                summaryStat("Crop use", String(format: "%.1f mm", result.forecastCropUseMm))
                summaryStat("Eff. rain", String(format: "%.1f mm", result.forecastEffectiveRainMm))
                summaryStat("Net deficit", String(format: "%.1f mm", result.netDeficitMm))
            }

            if result.recentActualRainMm > 0 {
                Text(String(format: "Includes %.1f mm recent actual rain from %@.",
                            result.recentActualRainMm,
                            actualRainShortSource))
                    .font(.caption2)
                    .foregroundStyle(VineyardTheme.leafGreen)
            }

            if let paddock = selectedPaddock,
               let lPerHaHr = paddock.litresPerHaPerHour,
               let mmHr = paddock.mmPerHour, mmHr > 0, needsIrrigation {
                let totalLitres = (result.grossIrrigationMm / mmHr) * lPerHaHr * paddock.areaHectares
                Text(String(format: "≈ %.0f L total for %@", totalLitres, paddock.name))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    private func summaryStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Block

    private var blockSection: some View {
        Section("Block") {
            if vineyardPaddocks.isEmpty {
                Text("No paddocks available")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Paddock", selection: $selectedPaddockId) {
                    Text("Select…").tag(UUID?.none)
                    ForEach(vineyardPaddocks) { paddock in
                        Text(paddock.name).tag(Optional(paddock.id))
                    }
                }
                .pickerStyle(.menu)

                if let paddock = selectedPaddock {
                    LabeledContent("Area") {
                        Text(String(format: "%.2f ha", paddock.areaHectares))
                            .foregroundStyle(.secondary)
                    }
                    if let mmHr = paddock.mmPerHour {
                        LabeledContent("System rate") {
                            Text(String(format: "%.2f mm/hr", mmHr))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Forecast controls

    private var forecastControlSection: some View {
        Section {
            Picker("Forecast duration", selection: $forecastDuration) {
                ForEach(durationOptions, id: \.self) { days in
                    Text("\(days) days").tag(days)
                }
            }
            .pickerStyle(.segmented)

            Button {
                Task { await loadForecast() }
            } label: {
                if forecastService.isLoading {
                    HStack {
                        ProgressView()
                        Text("Refreshing…")
                    }
                } else {
                    Label("Refresh Recommendation", systemImage: "arrow.clockwise")
                }
            }
            .disabled(forecastService.isLoading || latitude == nil || longitude == nil)
        } header: {
            Text("Forecast")
        } footer: {
            if latitude == nil || longitude == nil {
                Text("Set your vineyard location in Settings → Vineyard Setup to load a forecast.")
            } else {
                Text("Recommendation refreshes automatically when you change duration.")
            }
        }
    }

    // MARK: - Forecast details (collapsible)

    @ViewBuilder
    private var forecastDetailsSection: some View {
        if let forecast = forecastService.forecast {
            Section {
                DisclosureGroup("Forecast details") {
                    LabeledContent("Source") {
                        Text(forecast.source).foregroundStyle(.secondary)
                    }
                    if let vid = store.selectedVineyardId {
                        let status = WeatherProviderResolver.resolve(
                            for: vid,
                            weatherStationId: store.settings.weatherStationId
                        )
                        LabeledContent("Provider") {
                            Text(status.compactLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    LabeledContent("Days") {
                        Text("\(forecast.days.count)").foregroundStyle(.secondary)
                    }
                    Toggle("Override forecast values", isOn: $useManualInputs)
                }
            }
        }
    }

    @ViewBuilder
    private var dailyBreakdownDisclosure: some View {
        if let result {
            Section {
                DisclosureGroup("Daily breakdown") {
                    ForEach(result.dailyBreakdown) { day in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(day.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(String(format: "%.1f mm deficit", day.dailyDeficitMm))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(day.dailyDeficitMm > 0 ? VineyardTheme.vineRed : VineyardTheme.leafGreen)
                                    .monospacedDigit()
                            }

                            if useManualInputs {
                                HStack(spacing: 8) {
                                    manualField(label: "ETo", value: day.forecastEToMm, field: .manualEto(day.date), binding: etoBinding(for: day.date))
                                    manualField(label: "Rain", value: day.forecastRainMm, field: .manualRain(day.date), binding: rainBinding(for: day.date))
                                }
                            } else {
                                HStack {
                                    metric("ETo", String(format: "%.1f", day.forecastEToMm), suffix: "mm")
                                    Divider().frame(height: 20)
                                    metric("Rain", String(format: "%.1f", day.forecastRainMm), suffix: "mm")
                                    Divider().frame(height: 20)
                                    metric("Crop use", String(format: "%.1f", day.cropUseMm), suffix: "mm")
                                    Divider().frame(height: 20)
                                    metric("Eff. rain", String(format: "%.1f", day.effectiveRainMm), suffix: "mm")
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    // MARK: - Settings (collapsible)

    private var appRateIsSiteData: Bool {
        (selectedPaddock?.mmPerHour ?? 0) > 0
    }

    private var settingsSection: some View {
        Section {
            DisclosureGroup("Calculation assumptions & block settings") {
                settingRow(
                    label: "Application rate (mm/hr)",
                    text: $applicationRateText,
                    field: .appRate,
                    help: "How many millimetres of water your irrigation system applies to this block in one hour.",
                    isSiteData: appRateIsSiteData,
                    siteDataNote: "Pre-filled from this paddock's system rate."
                )
                settingRow(
                    label: "Crop coefficient (Kc)",
                    text: $kcText,
                    field: .kc,
                    help: "Vine water demand vs reference grass. 0.65 is a typical mid-season value.",
                    isSiteData: false,
                    siteDataNote: nil
                )
                settingRow(
                    label: "Irrigation efficiency (%)",
                    text: $efficiencyText,
                    field: .efficiency,
                    help: "How much pumped water reaches vine roots. Drip systems ~90%.",
                    isSiteData: false,
                    siteDataNote: nil
                )
                settingRow(
                    label: "Rainfall effectiveness (%)",
                    text: $rainEffText,
                    field: .rainEff,
                    help: "Fraction of forecast rainfall available to the vines. Typically ~80%.",
                    isSiteData: false,
                    siteDataNote: nil
                )
                settingRow(
                    label: "Replacement (%)",
                    text: $replacementText,
                    field: .replacement,
                    help: "How much vine water use to replace. Lower for deficit irrigation.",
                    isSiteData: false,
                    siteDataNote: nil
                )
                settingRow(
                    label: "Soil buffer (mm)",
                    text: $bufferText,
                    field: .buffer,
                    help: "Extra water already stored in the soil. Subtracted from the deficit.",
                    isSiteData: false,
                    siteDataNote: nil
                )
            }
        } footer: {
            Text("Fields marked \u{2728} are pre-filled with site-specific data from the selected paddock.")
        }
    }

    private func settingRow(
        label: String,
        text: Binding<String>,
        field: Field,
        help: String,
        isSiteData: Bool,
        siteDataNote: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 4) {
                    Text(label)
                    if isSiteData {
                        Image(systemName: "sparkles")
                            .font(.caption)
                            .foregroundStyle(VineyardTheme.leafGreen)
                    }
                }
                Spacer()
                TextField("0", text: text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .focused($focusedField, equals: field)
                    .frame(maxWidth: 120)
            }
            Text(help)
                .font(.caption)
                .foregroundStyle(.secondary)
            if isSiteData, let note = siteDataNote {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(VineyardTheme.leafGreen)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Helpers

    private func metric(_ label: String, _ value: String, suffix: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(value) \(suffix)")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func manualField(label: String, value: Double, field: Field, binding: Binding<String>) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(String(format: "%.1f", value), text: binding)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .focused($focusedField, equals: field)
                .font(.caption.weight(.semibold))
                .textFieldStyle(.roundedBorder)
        }
        .frame(maxWidth: .infinity)
    }

    private func etoBinding(for date: Date) -> Binding<String> {
        Binding(
            get: { manualEToOverrides[date] ?? "" },
            set: { newValue in
                if newValue.isEmpty {
                    manualEToOverrides.removeValue(forKey: date)
                } else {
                    manualEToOverrides[date] = newValue
                }
            }
        )
    }

    private func rainBinding(for date: Date) -> Binding<String> {
        Binding(
            get: { manualRainOverrides[date] ?? "" },
            set: { newValue in
                if newValue.isEmpty {
                    manualRainOverrides.removeValue(forKey: date)
                } else {
                    manualRainOverrides[date] = newValue
                }
            }
        )
    }

    private func hoursMinutesString(_ hours: Double) -> String {
        let totalMinutes = Int((hours * 60.0).rounded())
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        return "\(h) hr \(m) min"
    }

    private func loadForecast() async {
        guard let lat = latitude, let lon = longitude else { return }
        await forecastService.fetchForecast(latitude: lat, longitude: lon, days: forecastDuration)
        if forecastService.forecast != nil {
            lastUpdated = Date()
        }
    }

    private func loadRecentRainfall() async {
        guard let lat = latitude, let lon = longitude else { return }
        isLoadingRecentRain = true
        let result = await RainfallHistoryService.fetchRecentRainfall(
            vineyardId: store.selectedVineyardId,
            latitude: lat,
            longitude: lon,
            days: recentRainDays,
            weatherStationId: store.settings.weatherStationId
        )
        recentRainResult = result
        isLoadingRecentRain = false
    }

    private func applyPaddockDefaults() {
        guard let paddock = selectedPaddock else { return }
        if let mmHr = paddock.mmPerHour, mmHr > 0 {
            applicationRateText = String(format: "%.2f", mmHr)
        }
    }

    private func loadParametersFromSettings() {
        let s = store.settings
        kcText = String(format: "%.2f", s.irrigationKc)
        efficiencyText = String(format: "%.0f", s.irrigationEfficiencyPercent)
        rainEffText = String(format: "%.0f", s.irrigationRainfallEffectivenessPercent)
        replacementText = String(format: "%.0f", s.irrigationReplacementPercent)
        bufferText = String(format: "%.0f", s.irrigationSoilBufferMm)
        let saved = s.irrigationForecastDays
        forecastDuration = durationOptions.contains(saved) ? saved : 5
    }

    private func persistParameters() {
        guard didLoadFromSettings else { return }
        var s = store.settings
        s.irrigationKc = parse(kcText, default: 0.65)
        s.irrigationEfficiencyPercent = parse(efficiencyText, default: 90)
        s.irrigationRainfallEffectivenessPercent = parse(rainEffText, default: 80)
        s.irrigationReplacementPercent = parse(replacementText, default: 100)
        s.irrigationSoilBufferMm = parse(bufferText)
        store.updateSettings(s)
    }

    private func persistForecastDuration(_ days: Int) {
        guard didLoadFromSettings else { return }
        var s = store.settings
        s.irrigationForecastDays = days
        store.updateSettings(s)
    }

    private func parse(_ text: String, default defaultValue: Double = 0) -> Double {
        let cleaned = text.replacingOccurrences(of: ",", with: ".")
        if cleaned.isEmpty { return defaultValue }
        return Double(cleaned) ?? defaultValue
    }
}
