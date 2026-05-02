import SwiftUI

struct WeatherDataSettingsView: View {
    @Environment(MigratedDataStore.self) private var store
    @Environment(BackendAccessControl.self) private var accessControl

    @State private var config: WeatherProviderConfig = .default
    @State private var showStationPicker: Bool = false
    @State private var davisApiKey: String = ""
    @State private var davisApiSecret: String = ""
    @State private var davisStationIdInput: String = ""
    @State private var isTestingDavis: Bool = false
    @State private var davisTestMessage: String?
    @State private var showSecret: Bool = false

    private var canEdit: Bool { accessControl.canChangeSettings }

    private var vineyardId: UUID? { store.selectedVineyardId }

    var body: some View {
        Form {
            headerSection
            currentSourceSection
            providerSelectionSection

            if config.provider == .wunderground {
                weatherUndergroundSection
            }

            if config.provider == .davis {
                davisSection
            }

            usageSection
            fallbackSection

            if !canEdit {
                Section {
                    Text("Only the vineyard owner or manager can change weather data settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Weather Data & Forecasting")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadConfig() }
        .sheet(isPresented: $showStationPicker) {
            WeatherStationPickerSheet()
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        Section {
            Text("VineTrack uses weather data for irrigation advice, spray records, disease risk alerts and weather warnings. The app works automatically using forecast data, but you can connect a local weather station for more accurate vineyard conditions.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var currentSourceSection: some View {
        let status = currentStatus
        return Section {
            HStack(spacing: 12) {
                SettingsIconTile(symbol: status.provider.symbol, color: providerColor(status.provider))
                VStack(alignment: .leading, spacing: 2) {
                    Text(status.primaryLabel)
                        .font(.subheadline.weight(.semibold))
                    Text(status.detailLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            LabeledContent("Data quality") {
                Text(status.quality.displayName)
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Last update") {
                Text(status.lastUpdated?.formatted(date: .abbreviated, time: .shortened) ?? "—")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Current Data Source")
        } footer: {
            Text("If this source is unavailable, VineTrack will use the default forecast.")
        }
    }

    private var providerSelectionSection: some View {
        Section {
            ForEach(WeatherProvider.allCases) { provider in
                Button {
                    guard canEdit else { return }
                    var c = config
                    c.provider = provider
                    config = c
                    persist()
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        SettingsIconTile(symbol: provider.symbol, color: providerColor(provider))
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(provider.displayName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                if provider == .automatic {
                                    Text("Recommended")
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.green.opacity(0.15), in: .capsule)
                                        .foregroundStyle(.green)
                                }
                            }
                            Text(provider.helpCopy)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 8)
                        if config.provider == provider {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canEdit)
            }
        } header: {
            Text("Data Source")
        } footer: {
            Text("Choose where VineTrack pulls current weather observations from. Forecasts always fall back to the default service if a local source is unavailable.")
        }
    }

    private var weatherUndergroundSection: some View {
        Section {
            HStack(spacing: 12) {
                SettingsIconTile(symbol: "antenna.radiowaves.left.and.right", color: .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Selected station")
                        .font(.subheadline.weight(.medium))
                    Text(store.settings.weatherStationId?.isEmpty == false ? store.settings.weatherStationId! : "Auto / nearest")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            Button {
                showStationPicker = true
            } label: {
                Label("Select Nearby Station", systemImage: "location.magnifyingglass")
            }
            .disabled(!canEdit)

            if store.settings.weatherStationId?.isEmpty == false {
                Button(role: .destructive) {
                    var s = store.settings
                    s.weatherStationId = nil
                    store.updateSettings(s)
                } label: {
                    Label("Clear / Use Nearest", systemImage: "xmark.circle")
                }
                .disabled(!canEdit)
            }
        } header: {
            Text("Weather Underground")
        } footer: {
            Text("Pick a Personal Weather Station near your vineyard. If the station is offline, VineTrack falls back to the default forecast.")
        }
    }

    private var davisSection: some View {
        Section {
            HStack {
                Text("API Key")
                Spacer()
                TextField("Davis API Key", text: $davisApiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 220)
            }
            HStack {
                Text("API Secret")
                Spacer()
                Group {
                    if showSecret {
                        TextField("Davis API Secret", text: $davisApiSecret)
                    } else {
                        SecureField("Davis API Secret", text: $davisApiSecret)
                    }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 220)
                Button {
                    showSecret.toggle()
                } label: {
                    Image(systemName: showSecret ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            HStack {
                Text("Station ID")
                Spacer()
                TextField("Optional", text: $davisStationIdInput)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 220)
            }

            Button {
                saveDavisCredentials()
            } label: {
                Label("Save Credentials", systemImage: "lock.shield")
            }
            .disabled(!canEdit || davisApiKey.isEmpty || davisApiSecret.isEmpty)

            Button {
                Task { await testDavisConnection() }
            } label: {
                HStack {
                    Label("Test Connection", systemImage: "checkmark.seal")
                    Spacer()
                    if isTestingDavis { ProgressView() }
                }
            }
            .disabled(!canEdit || isTestingDavis || !config.davisHasCredentials)

            if let msg = davisTestMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if config.davisHasCredentials {
                Button(role: .destructive) {
                    clearDavisCredentials()
                } label: {
                    Label("Remove Credentials", systemImage: "trash")
                }
                .disabled(!canEdit)
            }

            // Detected sensors
            VStack(alignment: .leading, spacing: 8) {
                Text("Detected sensors")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if config.davisDetectedSensors.isEmpty {
                    Text("No sensor data yet. Run Test Connection to detect available sensors.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(config.davisDetectedSensors, id: \.self) { sensor in
                        Label(sensor, systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
                if config.davisHasCredentials {
                    if config.davisHasLeafWetnessSensor {
                        Label("Measured leaf wetness available", systemImage: "drop.fill")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    } else {
                        Label("No leaf wetness sensor detected — using estimated wetness", systemImage: "drop")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Davis WeatherLink")
        } footer: {
            Text("Credentials are stored securely on this device using the iOS Keychain and are not shared with other vineyard members.")
        }
    }

    private var usageSection: some View {
        Section {
            usageRow(symbol: "drop.fill", color: .teal, text: "Spray records — wind, temp, humidity at job time")
            usageRow(symbol: "leaf.fill", color: .green, text: "Irrigation Advisor — forecast ETo, rainfall")
            usageRow(symbol: "cloud.bolt.rain.fill", color: .orange, text: "Weather alerts — rain, wind, frost, heat")
            usageRow(symbol: "ladybug.fill", color: .red, text: "Disease risk alerts — humidity, dew point, wetness")
            usageRow(symbol: "thermometer.sun.fill", color: .pink, text: "Degree-day / BEDD calculations")
        } header: {
            Text("How weather data is used")
        } footer: {
            Text("When a configured local source has the required data, VineTrack uses it. If not, it falls back to the default forecast so core features continue working.")
        }
    }

    private var fallbackSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                fallbackRow(rank: "A", title: "Davis WeatherLink", detail: "Uses Davis observations and history when configured. Measured leaf wetness when sensor is present.")
                fallbackRow(rank: "B", title: "Weather Underground PWS", detail: "Uses your selected PWS for current/local observations.")
                fallbackRow(rank: "C", title: "Automatic Forecast", detail: "Default forecast based on vineyard location.")
            }
            .padding(.vertical, 4)
        } header: {
            Text("Data priority / fallback")
        } footer: {
            Text("VineTrack falls back through this priority list automatically if a higher-priority source is unavailable. Disease risk continues with estimated wetness when measured wetness isn't available.")
        }
    }

    // MARK: - Helpers

    private var currentStatus: WeatherSourceStatus {
        guard let vid = vineyardId else {
            return WeatherSourceStatus(
                provider: .automatic,
                quality: .forecastOnly,
                primaryLabel: "Automatic Forecast",
                detailLabel: "Based on vineyard location",
                lastUpdated: nil
            )
        }
        return WeatherProviderResolver.resolve(for: vid, weatherStationId: store.settings.weatherStationId)
    }

    private func providerColor(_ p: WeatherProvider) -> Color {
        switch p {
        case .automatic: return .blue
        case .wunderground: return .orange
        case .davis: return .indigo
        }
    }

    private func usageRow(symbol: String, color: Color, text: String) -> some View {
        HStack(spacing: 12) {
            SettingsIconTile(symbol: symbol, color: color, size: 28)
            Text(text)
                .font(.subheadline)
            Spacer()
        }
    }

    private func fallbackRow(rank: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(rank)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.accentColor, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func loadConfig() {
        guard let vid = vineyardId else { return }
        var c = WeatherProviderStore.shared.config(for: vid)
        // Reconcile keychain state.
        c.davisHasCredentials = WeatherKeychain.hasCredentials
        config = c
        davisStationIdInput = c.davisStationId ?? ""
    }

    private func persist() {
        guard let vid = vineyardId else { return }
        WeatherProviderStore.shared.save(config, for: vid)
    }

    private func saveDavisCredentials() {
        guard canEdit else { return }
        WeatherKeychain.set(davisApiKey, for: .apiKey)
        WeatherKeychain.set(davisApiSecret, for: .apiSecret)
        var c = config
        c.davisHasCredentials = WeatherKeychain.hasCredentials
        let trimmed = davisStationIdInput.trimmingCharacters(in: .whitespacesAndNewlines)
        c.davisStationId = trimmed.isEmpty ? nil : trimmed
        config = c
        persist()
        davisApiKey = ""
        davisApiSecret = ""
        davisTestMessage = "Credentials saved. Run Test Connection to detect sensors."
    }

    private func clearDavisCredentials() {
        WeatherKeychain.clearAll()
        var c = config
        c.davisHasCredentials = false
        c.davisDetectedSensors = []
        c.davisHasLeafWetnessSensor = false
        c.davisLastTestSuccess = nil
        c.davisLastTestError = nil
        config = c
        persist()
        davisTestMessage = "Davis credentials removed."
    }

    private func testDavisConnection() async {
        guard config.davisHasCredentials else { return }
        isTestingDavis = true
        defer { isTestingDavis = false }
        davisTestMessage = "Testing Davis WeatherLink…"
        // Davis WeatherLink direct integration is not implemented yet. We
        // record a non-blocking placeholder result so the UI reflects that
        // credentials were saved but live data is not yet wired up.
        try? await Task.sleep(for: .milliseconds(600))
        var c = config
        c.davisLastTestError = "Live Davis integration is coming soon. Credentials are saved and will be used automatically once enabled."
        c.davisDetectedSensors = []
        c.davisHasLeafWetnessSensor = false
        config = c
        persist()
        davisTestMessage = c.davisLastTestError
    }
}
