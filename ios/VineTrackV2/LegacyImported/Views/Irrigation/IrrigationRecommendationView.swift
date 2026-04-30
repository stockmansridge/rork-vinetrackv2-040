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

    private var result: IrrigationRecommendationResult? {
        IrrigationCalculator.calculate(forecastDays: forecastDays, settings: settings)
    }

    var body: some View {
        Form {
            blockSection
            forecastSection
            settingsSection
            if let result {
                resultSection(result)
                dailyBreakdownSection(result)
            } else if forecastService.forecast == nil, forecastService.errorMessage == nil, !forecastService.isLoading {
                Section {
                    Text("Load a 5-day forecast to see a recommendation.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else if settings.irrigationApplicationRateMmPerHour <= 0 {
                Section {
                    Label("Enter an application rate greater than 0 mm/hr to calculate.", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
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
        }
        .onChange(of: kcText) { _, _ in persistParameters() }
        .onChange(of: efficiencyText) { _, _ in persistParameters() }
        .onChange(of: rainEffText) { _, _ in persistParameters() }
        .onChange(of: replacementText) { _, _ in persistParameters() }
        .onChange(of: bufferText) { _, _ in persistParameters() }
        .onChange(of: selectedPaddockId) { _, _ in
            applyPaddockDefaults()
        }
    }

    // MARK: - Sections

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
                        LabeledContent("System Rate") {
                            Text(String(format: "%.2f mm/hr", mmHr))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var forecastSection: some View {
        Section {
            if forecastService.isLoading {
                HStack {
                    ProgressView()
                    Text("Loading 5-day forecast…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if let error = forecastService.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            } else if let forecast = forecastService.forecast {
                LabeledContent("Source") {
                    Text(forecast.source)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Days") {
                    Text("\(forecast.days.count)")
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                Task { await loadForecast() }
            } label: {
                Label(forecastService.forecast == nil ? "Load Forecast" : "Refresh Forecast", systemImage: "arrow.clockwise")
            }
            .disabled(forecastService.isLoading || latitude == nil || longitude == nil)

            if latitude == nil || longitude == nil {
                Text("Set your vineyard location in Settings → Vineyard Setup to load a forecast.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Toggle("Override forecast values", isOn: $useManualInputs)
        } header: {
            Text("5-Day Forecast")
        } footer: {
            Text("Evapotranspiration (ETo) and rainfall are fetched from Open-Meteo. You can override each day below if needed.")
        }
    }

    private var appRateIsSiteData: Bool {
        (selectedPaddock?.mmPerHour ?? 0) > 0
    }

    private var settingsSection: some View {
        Section {
            settingRow(
                label: "Application Rate (mm/hr)",
                text: $applicationRateText,
                field: .appRate,
                help: "How many millimetres of water your irrigation system applies to this block in one hour of running.",
                isSiteData: appRateIsSiteData,
                siteDataNote: "Pre-filled from this paddock's system rate."
            )
            settingRow(
                label: "Crop Coefficient (Kc)",
                text: $kcText,
                field: .kc,
                help: "How thirsty the vines are compared to a reference grass. 0.65 is a typical mid-season value for wine grapes.",
                isSiteData: false,
                siteDataNote: nil
            )
            settingRow(
                label: "Irrigation Efficiency (%)",
                text: $efficiencyText,
                field: .efficiency,
                help: "How much of the water you pump actually reaches the vine roots. Drip systems are typically around 90%.",
                isSiteData: false,
                siteDataNote: nil
            )
            settingRow(
                label: "Rainfall Effectiveness (%)",
                text: $rainEffText,
                field: .rainEff,
                help: "How much of the forecast rainfall actually soaks in and is available to the vines. Typically around 80%.",
                isSiteData: false,
                siteDataNote: nil
            )
            settingRow(
                label: "Replacement (%)",
                text: $replacementText,
                field: .replacement,
                help: "How much of the water the vines use that you want to replace. 100% fully replaces it, lower values apply deficit irrigation.",
                isSiteData: false,
                siteDataNote: nil
            )
            settingRow(
                label: "Soil Buffer (mm)",
                text: $bufferText,
                field: .buffer,
                help: "Extra water already stored in the soil from earlier rain or irrigation. Subtracted from the deficit. Leave at 0 if unsure.",
                isSiteData: false,
                siteDataNote: nil
            )
        } header: {
            Text("Irrigation Settings")
        } footer: {
            Text("Fields marked \u{2728} are pre-filled with site-specific data from the selected paddock. Other values use sensible defaults you can adjust.")
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

    private func resultSection(_ result: IrrigationRecommendationResult) -> some View {
        Section("Recommendation") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Recommended irrigation")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(String(format: "%.1f hours", result.recommendedIrrigationHours))
                    .font(.title.weight(.bold))
                    .foregroundStyle(VineyardTheme.leafGreen)
                    .monospacedDigit()
                Text(hoursMinutesString(result.recommendedIrrigationHours))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text("over the next 5 days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)

            LabeledContent("Forecast crop use") {
                Text(String(format: "%.1f mm", result.forecastCropUseMm))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            LabeledContent("Effective rainfall") {
                Text(String(format: "%.1f mm", result.forecastEffectiveRainMm))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            LabeledContent("Net deficit") {
                Text(String(format: "%.1f mm", result.netDeficitMm))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            LabeledContent("Gross to apply") {
                Text(String(format: "%.1f mm", result.grossIrrigationMm))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            LabeledContent("Rate") {
                Text(String(format: "%.2f mm/hr", settings.irrigationApplicationRateMmPerHour))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if let paddock = selectedPaddock,
               let lPerHaHr = paddock.litresPerHaPerHour,
               let mmHr = paddock.mmPerHour, mmHr > 0 {
                let totalLitres = (result.grossIrrigationMm / mmHr) * lPerHaHr * paddock.areaHectares
                LabeledContent("Total water") {
                    Text(String(format: "%.0f L", totalLitres))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    private func dailyBreakdownSection(_ result: IrrigationRecommendationResult) -> some View {
        Section("Daily Breakdown") {
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
                            metric("Crop Use", String(format: "%.1f", day.cropUseMm), suffix: "mm")
                            Divider().frame(height: 20)
                            metric("Eff. Rain", String(format: "%.1f", day.effectiveRainMm), suffix: "mm")
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
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
        await forecastService.fetchForecast(latitude: lat, longitude: lon)
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

    private func parse(_ text: String, default defaultValue: Double = 0) -> Double {
        let cleaned = text.replacingOccurrences(of: ",", with: ".")
        if cleaned.isEmpty { return defaultValue }
        return Double(cleaned) ?? defaultValue
    }
}
