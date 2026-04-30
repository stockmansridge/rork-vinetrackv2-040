import SwiftUI

struct PreferencesHubView: View {
    @Environment(MigratedDataStore.self) private var store
    @Environment(LocationService.self) private var locationService

    @State private var samplesPerHectareText: String = ""
    @State private var fillTimerEnabled: Bool = true
    @State private var elConfirmationEnabled: Bool = true
    @State private var seasonFuelCostText: String = ""
    @State private var rowTrackingEnabled: Bool = true
    @State private var rowTrackingInterval: Double = 1.0
    @State private var autoPhotoPrompt: Bool = false
    @State private var appearance: AppAppearance = .system
    @State private var seasonStartMonth: Int = 7
    @State private var seasonStartDay: Int = 1
    @State private var timezoneIdentifier: String = TimeZone.current.identifier
    @State private var aiSuggestionsEnabled: Bool = true

    @State private var showGrowthStages: Bool = false
    @State private var showWeatherStationPicker: Bool = false
    @State private var showTimezonePicker: Bool = false

    var body: some View {
        Form {
            appearanceSection
            seasonSection
            tripTrackingSection
            spraySection
            yieldSection
            photosSection
            aiSection
            regionalSection
        }
        .navigationTitle("Preferences")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showGrowthStages) {
            GrowthStageConfigSheet()
        }
        .sheet(isPresented: $showWeatherStationPicker) {
            WeatherStationPickerSheet()
        }
        .sheet(isPresented: $showTimezonePicker) {
            TimezonePickerSheet(selected: $timezoneIdentifier) { id in
                var s = store.settings
                s.timezone = id
                store.updateSettings(s)
            }
        }
        .onAppear { loadSettings() }
    }

    // MARK: - Sections

    private var appearanceSection: some View {
        Section {
            Picker("Display Mode", selection: $appearance) {
                ForEach(AppAppearance.allCases, id: \.self) { mode in
                    Label(mode.displayName, systemImage: mode.iconName).tag(mode)
                }
            }
            .onChange(of: appearance) { _, newValue in
                var s = store.settings
                s.appearance = newValue
                store.updateSettings(s)
            }
        } header: {
            Text("Appearance")
        }
    }

    private var seasonSection: some View {
        Section {
            Picker("Season Start Month", selection: $seasonStartMonth) {
                ForEach(1...12, id: \.self) { m in
                    Text(monthName(m)).tag(m)
                }
            }
            .onChange(of: seasonStartMonth) { _, newValue in
                var s = store.settings
                s.seasonStartMonth = newValue
                store.updateSettings(s)
            }

            Stepper(value: $seasonStartDay, in: 1...maxDay(for: seasonStartMonth)) {
                HStack {
                    Text("Season Start Day")
                    Spacer()
                    Text("\(seasonStartDay)")
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: seasonStartDay) { _, newValue in
                var s = store.settings
                s.seasonStartDay = newValue
                store.updateSettings(s)
            }

            Toggle("Confirm E-L Stage", isOn: $elConfirmationEnabled)
                .onChange(of: elConfirmationEnabled) { _, newValue in
                    var s = store.settings
                    s.elConfirmationEnabled = newValue
                    store.updateSettings(s)
                }
        } header: {
            Text("Growing Season & E-L")
        } footer: {
            Text("Season boundaries are used by the E-L growth stage report.")
        }
    }

    private var tripTrackingSection: some View {
        Section {
            Toggle("Row Tracking", isOn: $rowTrackingEnabled)
                .onChange(of: rowTrackingEnabled) { _, newValue in
                    var s = store.settings
                    s.rowTrackingEnabled = newValue
                    store.updateSettings(s)
                }

            HStack {
                Text("Tracking Interval")
                Spacer()
                Text(String(format: "%.1f s", rowTrackingInterval))
                    .foregroundStyle(.secondary)
            }
            Slider(value: $rowTrackingInterval, in: 0.5...10.0, step: 0.5)
                .onChange(of: rowTrackingInterval) { _, newValue in
                    var s = store.settings
                    s.rowTrackingInterval = newValue
                    store.updateSettings(s)
                }
        } header: {
            Text("Trip & Row Tracking")
        } footer: {
            Text("Controls how often GPS samples are recorded during an active trip and whether row guidance is shown in-field.")
        }
    }

    private var spraySection: some View {
        Section {
            Toggle("Tank Fill Timer", isOn: $fillTimerEnabled)
                .onChange(of: fillTimerEnabled) { _, newValue in
                    var s = store.settings
                    s.fillTimerEnabled = newValue
                    store.updateSettings(s)
                }
            HStack {
                Text("Fuel Cost (per L)")
                Spacer()
                TextField("0", text: $seasonFuelCostText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .onSubmit { saveFuelCost() }
            }
        } header: {
            Text("Spray / Tank")
        }
    }

    private var yieldSection: some View {
        Section {
            HStack {
                Text("Samples per Hectare")
                Spacer()
                TextField("0", text: $samplesPerHectareText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .onSubmit { saveSamples() }
            }
        } header: {
            Text("Yield Estimation")
        }
    }

    private var photosSection: some View {
        Section {
            Toggle("Auto Photo Prompt", isOn: $autoPhotoPrompt)
                .onChange(of: autoPhotoPrompt) { _, newValue in
                    var s = store.settings
                    s.autoPhotoPrompt = newValue
                    store.updateSettings(s)
                }
        } header: {
            Text("Photos")
        } footer: {
            Text("When enabled, the app will prompt to attach a photo after dropping repair or growth pins.")
        }
    }

    private var aiSection: some View {
        Section {
            Toggle("Enable AI Suggestions", isOn: $aiSuggestionsEnabled)
                .onChange(of: aiSuggestionsEnabled) { _, newValue in
                    var s = store.settings
                    s.aiSuggestionsEnabled = newValue
                    store.updateSettings(s)
                }
        } header: {
            Text("AI Suggestions")
        } footer: {
            Text("AI suggestions are optional and must be checked against current product labels, permits, SDS, and local regulations before use.")
        }
    }

    private var regionalSection: some View {
        Section {
            Button {
                showTimezonePicker = true
            } label: {
                HStack {
                    Label("Timezone", systemImage: "globe")
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(timezoneIdentifier)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        } header: {
            Text("Regional")
        }
    }

    // MARK: - Helpers

    private func loadSettings() {
        let s = store.settings
        samplesPerHectareText = String(s.samplesPerHectare)
        fillTimerEnabled = s.fillTimerEnabled
        elConfirmationEnabled = s.elConfirmationEnabled
        seasonFuelCostText = String(format: "%.2f", s.seasonFuelCostPerLitre)
        rowTrackingEnabled = s.rowTrackingEnabled
        rowTrackingInterval = s.rowTrackingInterval
        autoPhotoPrompt = s.autoPhotoPrompt
        appearance = s.appearance
        seasonStartMonth = s.seasonStartMonth
        seasonStartDay = s.seasonStartDay
        timezoneIdentifier = s.timezone
        aiSuggestionsEnabled = s.aiSuggestionsEnabled
    }

    private func saveSamples() {
        guard let v = Int(samplesPerHectareText), v > 0 else { return }
        var s = store.settings
        s.samplesPerHectare = v
        store.updateSettings(s)
    }

    private func saveFuelCost() {
        guard let v = Double(seasonFuelCostText), v >= 0 else { return }
        var s = store.settings
        s.seasonFuelCostPerLitre = v
        store.updateSettings(s)
    }

    private func monthName(_ m: Int) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        return df.standaloneMonthSymbols[max(0, min(11, m - 1))]
    }

    private func maxDay(for month: Int) -> Int {
        switch month {
        case 1, 3, 5, 7, 8, 10, 12: return 31
        case 4, 6, 9, 11: return 30
        case 2: return 29
        default: return 31
        }
    }
}

// MARK: - Timezone picker

private struct TimezonePickerSheet: View {
    @Binding var selected: String
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""

    private var identifiers: [String] {
        let all = TimeZone.knownTimeZoneIdentifiers
        guard !query.isEmpty else { return all }
        return all.filter { $0.localizedStandardContains(query) }
    }

    var body: some View {
        NavigationStack {
            List(identifiers, id: \.self) { id in
                Button {
                    selected = id
                    onSelect(id)
                    dismiss()
                } label: {
                    HStack {
                        Text(id)
                            .foregroundStyle(.primary)
                        Spacer()
                        if id == selected {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Search timezones")
            .navigationTitle("Timezone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
