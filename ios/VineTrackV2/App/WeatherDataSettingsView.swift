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
    @State private var davisInfoTopic: DavisInfoTopic?

    private var canEdit: Bool { accessControl.canChangeSettings }

    enum DavisStatus: Equatable {
        case notConfigured
        case credentialsSavedNotTested
        case testing
        case connectedNoLeafWetness
        case connectedWithLeafWetness
        case connectionFailed(String)
        case liveIntegrationNotAvailable

        var headline: String {
            switch self {
            case .notConfigured: return "Not configured"
            case .credentialsSavedNotTested: return "Davis WeatherLink credentials saved."
            case .testing: return "Testing Davis WeatherLink…"
            case .connectedNoLeafWetness: return "Connected — no leaf wetness sensor detected."
            case .connectedWithLeafWetness: return "Connected — measured leaf wetness available."
            case .connectionFailed(let msg): return msg
            case .liveIntegrationNotAvailable: return "Davis WeatherLink credentials saved. Live station detection is not enabled yet."
            }
        }

        var sensorsDetail: String {
            switch self {
            case .notConfigured:
                return "Save Davis credentials to begin."
            case .credentialsSavedNotTested:
                return "Sensor detection will run once you tap Test Connection."
            case .testing:
                return "Detecting available sensors…"
            case .connectedNoLeafWetness, .connectedWithLeafWetness:
                return ""
            case .connectionFailed:
                return "Sensor detection unavailable until the connection succeeds."
            case .liveIntegrationNotAvailable:
                return "Sensor detection will be available once Davis WeatherLink live integration is enabled."
            }
        }
    }

    private enum DavisInfoTopic: String, Identifiable {
        case apiKey, apiSecret, stationId
        var id: String { rawValue }
        var title: String {
            switch self {
            case .apiKey: return "Davis API Key"
            case .apiSecret: return "Davis API Secret"
            case .stationId: return "Davis Station ID"
            }
        }
        var body: String {
            switch self {
            case .apiKey:
                return "Davis WeatherLink v2 API details are created from your WeatherLink account page. The API Key identifies your account connection and is safe to display after saving.\n\nTo generate one:\n1. Sign in to weatherlink.com.\n2. Open Account Settings.\n3. Tap ‘Generate v2 Key’.\n4. Copy the API Key into VineTrack."
            case .apiSecret:
                return "The API Secret authorises access to your Davis WeatherLink data and should be kept private. VineTrack stores it securely on this device using the iOS Keychain — it is never shared with other vineyard members or uploaded in plain text.\n\nGenerate it alongside the API Key from Account Settings → Generate v2 Key on weatherlink.com."
            case .stationId:
                return "Station ID selection is not available yet. Once Davis WeatherLink live integration is enabled, VineTrack will load your available stations and select one automatically based on your saved credentials."
            }
        }
    }

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

            if config.provider == .davis {
                davisHelpSection
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
        .sheet(item: $davisInfoTopic) { topic in
            NavigationStack {
                ScrollView {
                    Text(topic.body)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .navigationTitle(topic.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { davisInfoTopic = nil }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private func infoButton(_ topic: DavisInfoTopic) -> some View {
        Button {
            davisInfoTopic = topic
        } label: {
            Image(systemName: "info.circle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("About \(topic.title)")
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
                infoButton(.apiKey)
                Spacer()
                TextField("Davis API Key", text: $davisApiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 220)
            }
            HStack {
                Text("API Secret")
                infoButton(.apiSecret)
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
                infoButton(.stationId)
                Spacer()
                Text("Available after Davis integration")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button {
                saveDavisCredentials()
            } label: {
                Label("Save Credentials", systemImage: "lock.shield")
            }
            .disabled(!canEdit || davisApiKey.isEmpty || davisApiSecret.isEmpty)

            // Live Davis integration is not implemented yet; show a disabled
            // "Coming soon" row so users don't expect a working test.
            HStack {
                Label("Test Connection", systemImage: "checkmark.seal")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Coming soon")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.15), in: .capsule)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Test Connection. Coming soon.")

            if let msg = davisTestMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if config.davisHasCredentials {
                Text("Credentials saved. Davis station detection will be available in a future update.")
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

                let status = davisStatus
                switch status {
                case .connectedNoLeafWetness, .connectedWithLeafWetness:
                    if config.davisDetectedSensors.isEmpty {
                        Text("No sensors detected.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(config.davisDetectedSensors, id: \.self) { sensor in
                            Label(sensor, systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                    if status == .connectedWithLeafWetness {
                        Label("Measured leaf wetness available", systemImage: "drop.fill")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    } else {
                        Label("No leaf wetness sensor detected — using estimated wetness", systemImage: "drop")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                default:
                    Text(status.sensorsDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Davis WeatherLink")
        } footer: {
            Text("Credentials are stored securely on this device using the iOS Keychain and are not shared with other vineyard members.")
        }
    }

    private var davisHelpSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                helpStep(number: 1, text: "Sign in to your WeatherLink account at weatherlink.com.")
                helpStep(number: 2, text: "Go to Account Settings.")
                helpStep(number: 3, text: "Look for ‘Generate v2 Key’.")
                helpStep(number: 4, text: "WeatherLink will provide an API Key and API Secret.")
                helpStep(number: 5, text: "Enter both here and tap Save Credentials.")
                helpStep(number: 6, text: "Live station detection and sensor discovery will be available in a future update.")
            }
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 6) {
                Label("Your API Secret is stored securely on this device using Keychain.", systemImage: "lock.shield")
                Label("It is not shared with other vineyard members.", systemImage: "person.2.slash")
                Label("Station ID is selected automatically after connection where possible.", systemImage: "antenna.radiowaves.left.and.right")
                Label("If your station has a leaf wetness sensor, VineTrack can use measured wetness for disease risk.", systemImage: "drop.fill")
                Label("If no leaf wetness sensor is detected, VineTrack will continue using estimated wetness.", systemImage: "drop")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
        } header: {
            Text("How to find your Davis API details")
        }
    }

    private func helpStep(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.accentColor, in: Circle())
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
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

    private var davisStatus: DavisStatus {
        if !config.davisHasCredentials { return .notConfigured }
        if isTestingDavis { return .testing }
        // Live integration not implemented yet — once credentials are saved,
        // surface this clearly instead of pretending we tested anything.
        return .liveIntegrationNotAvailable
    }

    private func saveDavisCredentials() {
        guard canEdit else { return }
        WeatherKeychain.set(davisApiKey, for: .apiKey)
        WeatherKeychain.set(davisApiSecret, for: .apiSecret)
        var c = config
        c.davisHasCredentials = WeatherKeychain.hasCredentials
        let trimmed = davisStationIdInput.trimmingCharacters(in: .whitespacesAndNewlines)
        c.davisStationId = trimmed.isEmpty ? nil : trimmed
        // Reset any stale detection state — live integration isn't wired up yet.
        c.davisDetectedSensors = []
        c.davisHasLeafWetnessSensor = false
        c.davisLastTestError = nil
        c.davisLastTestSuccess = nil
        config = c
        persist()
        davisApiKey = ""
        davisApiSecret = ""
        davisTestMessage = "Credentials saved. Davis station detection will be available in a future update."
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
        // Davis WeatherLink live API integration is not implemented yet, so
        // there's nothing to actually test. Surface that clearly rather than
        // running a fake spinner that ends in a misleading "no sensor" state.
        var c = config
        c.davisDetectedSensors = []
        c.davisHasLeafWetnessSensor = false
        c.davisLastTestError = nil
        c.davisLastTestSuccess = nil
        config = c
        persist()
        davisTestMessage = DavisStatus.liveIntegrationNotAvailable.headline
    }
}
