import SwiftUI

struct WeatherDataSettingsView: View {
    @Environment(MigratedDataStore.self) private var store
    @Environment(BackendAccessControl.self) private var accessControl

    @State private var config: WeatherProviderConfig = .default
    @State private var showStationPicker: Bool = false
    @State private var davisApiKey: String = ""
    @State private var davisApiSecret: String = ""
    @State private var isTestingDavis: Bool = false
    @State private var davisTestMessage: String?
    @State private var davisTestSucceeded: Bool = false
    @State private var showSecret: Bool = false
    @State private var davisInfoTopic: DavisInfoTopic?
    @State private var isEditingDavisCredentials: Bool = false
    @State private var davisStations: [DavisStation] = []
    @State private var showDavisStationPicker: Bool = false

    private var canEdit: Bool { accessControl.canChangeSettings }

    enum DavisStatus: Equatable {
        case notConfigured
        case credentialsSavedNotTested
        case testing
        case connectedNoStationSelected
        case connectedNoLeafWetness
        case connectedWithLeafWetness
        case connectionFailed(String)

        var headline: String {
            switch self {
            case .notConfigured: return "Not configured"
            case .credentialsSavedNotTested: return "Credentials saved. Tap Test Connection to verify your WeatherLink account."
            case .testing: return "Testing Davis WeatherLink…"
            case .connectedNoStationSelected: return "Connected — select a station to load sensors."
            case .connectedNoLeafWetness: return "Connected — no leaf wetness sensor detected."
            case .connectedWithLeafWetness: return "Connected — measured leaf wetness available."
            case .connectionFailed(let msg): return msg
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
            case .connectedNoStationSelected:
                return "Pick a station to detect available sensors."
            case .connectedNoLeafWetness, .connectedWithLeafWetness:
                return ""
            case .connectionFailed:
                return "Sensor detection unavailable until the connection succeeds."
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
                return "VineTrack loads stations directly from WeatherLink after a successful Test Connection. If your account has more than one station, you can pick the correct vineyard station from the list. The Station ID is read from the API — you don't need to enter it manually."
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
        .sheet(isPresented: $showDavisStationPicker) {
            DavisStationPickerSheet(
                stations: davisStations,
                selectedStationId: config.davisStationId
            ) { station in
                showDavisStationPicker = false
                Task { await selectDavisStation(station) }
            }
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
        let savedAndNotEditing = config.davisHasCredentials && !isEditingDavisCredentials

        return Section {
            // 1. Saved status card on top
            if savedAndNotEditing {
                savedStatusCard
            }

            // API Key row
            HStack {
                Text("API Key")
                infoButton(.apiKey)
                Spacer()
                if savedAndNotEditing {
                    HStack(spacing: 6) {
                        Text("••••••••")
                            .font(.subheadline.monospaced())
                            .foregroundStyle(.secondary)
                        Text("Saved")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15), in: .capsule)
                            .foregroundStyle(.green)
                    }
                } else {
                    TextField("Davis API Key", text: $davisApiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 220)
                }
            }

            // API Secret row
            HStack {
                Text("API Secret")
                infoButton(.apiSecret)
                Spacer()
                if savedAndNotEditing {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Saved securely")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15), in: .capsule)
                            .foregroundStyle(.green)
                    }
                } else {
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
            }

            // Station selection — enabled once we've successfully tested
            // the connection and have at least one station available.
            if config.davisHasCredentials,
               config.davisConnectionTested,
               !(config.davisAvailableStations.isEmpty && davisStations.isEmpty) {
                Button {
                    showDavisStationPicker = true
                } label: {
                    HStack {
                        Label("Selected station", systemImage: "antenna.radiowaves.left.and.right")
                        Spacer()
                        Text(currentStationLabel)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .disabled(!canEdit)
            } else {
                HStack {
                    Text("Station selection")
                    infoButton(.stationId)
                    Spacer()
                    Text("Run Test Connection")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.15), in: .capsule)
                }
            }

            // Save / Replace / Cancel actions
            if savedAndNotEditing {
                Button {
                    beginReplaceCredentials()
                } label: {
                    Label("Replace Credentials", systemImage: "square.and.pencil")
                }
                .disabled(!canEdit)
            } else {
                Button {
                    saveDavisCredentials()
                } label: {
                    Label("Save Credentials", systemImage: "lock.shield")
                }
                .disabled(!canEdit || davisApiKey.isEmpty || davisApiSecret.isEmpty)

                if isEditingDavisCredentials {
                    Button {
                        cancelReplaceCredentials()
                    } label: {
                        Label("Cancel", systemImage: "xmark.circle")
                    }
                }
            }

            // Test Connection — live
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    Task { await testDavisConnection() }
                } label: {
                    HStack {
                        if isTestingDavis {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "checkmark.seal")
                        }
                        Text(isTestingDavis ? "Testing…" : "Test Connection")
                        Spacer()
                    }
                }
                .disabled(!canEdit || !config.davisHasCredentials || isTestingDavis)
                if let msg = davisTestMessage, !msg.isEmpty {
                    Text(msg)
                        .font(.caption2)
                        .foregroundStyle(davisTestSucceeded ? .green : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Verifies your WeatherLink account and loads available stations.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
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
                case .credentialsSavedNotTested:
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Not tested yet", systemImage: "questionmark.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Tap Test Connection to detect available sensors.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                case .connectedNoStationSelected:
                    Label("Select a station to detect sensors", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

    private var savedStatusCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.shield.fill")
                .font(.title3)
                .foregroundStyle(.green)
                .frame(width: 32, height: 32)
                .background(Color.green.opacity(0.12), in: .rect(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                Text("Credentials saved securely on this device")
                    .font(.subheadline.weight(.semibold))
                Text("Live WeatherLink connection is not enabled yet, so these credentials have not been tested.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private var davisHelpSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                helpStep(number: 1, text: "Sign in to your WeatherLink account at weatherlink.com.")
                helpStep(number: 2, text: "Go to Account Settings.")
                helpStep(number: 3, text: "Look for ‘Generate v2 Key’.")
                helpStep(number: 4, text: "WeatherLink will provide an API Key and API Secret.")
                helpStep(number: 5, text: "Enter both here and tap Save Credentials.")
                helpStep(number: 6, text: "Tap Test Connection to verify the account and load your stations.")
                helpStep(number: 7, text: "If you have more than one station, choose the one closest to the vineyard.")
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
        if !c.davisHasCredentials {
            c.davisConnectionTested = false
        }
        config = c
        davisStations = c.davisAvailableStations
    }

    private func persist() {
        guard let vid = vineyardId else { return }
        WeatherProviderStore.shared.save(config, for: vid)
    }

    private var davisStatus: DavisStatus {
        if !config.davisHasCredentials { return .notConfigured }
        if isTestingDavis { return .testing }
        if let err = config.davisLastTestError, !err.isEmpty {
            return .connectionFailed(err)
        }
        if !config.davisConnectionTested { return .credentialsSavedNotTested }
        guard let sid = config.davisStationId, !sid.isEmpty else {
            return .connectedNoStationSelected
        }
        return config.davisHasLeafWetnessSensor
            ? .connectedWithLeafWetness
            : .connectedNoLeafWetness
    }

    private func saveDavisCredentials() {
        guard canEdit else { return }
        WeatherKeychain.set(davisApiKey, for: .apiKey)
        WeatherKeychain.set(davisApiSecret, for: .apiSecret)
        var c = config
        c.davisHasCredentials = WeatherKeychain.hasCredentials
        // New credentials — invalidate prior test state.
        c.davisConnectionTested = false
        c.davisStationId = nil
        c.davisStationName = nil
        c.davisAvailableStations = []
        c.davisDetectedSensors = []
        c.davisHasLeafWetnessSensor = false
        c.davisLastTestError = nil
        c.davisLastTestSuccess = nil
        config = c
        persist()
        davisApiKey = ""
        davisApiSecret = ""
        davisStations = []
        showSecret = false
        isEditingDavisCredentials = false
        davisTestSucceeded = false
        davisTestMessage = "Credentials saved securely. Tap Test Connection to verify your WeatherLink account."
    }

    private func beginReplaceCredentials() {
        davisApiKey = ""
        davisApiSecret = ""
        showSecret = false
        isEditingDavisCredentials = true
        davisTestMessage = nil
    }

    private func cancelReplaceCredentials() {
        davisApiKey = ""
        davisApiSecret = ""
        showSecret = false
        isEditingDavisCredentials = false
    }

    private func clearDavisCredentials() {
        WeatherKeychain.clearAll()
        var c = config
        c.davisHasCredentials = false
        c.davisConnectionTested = false
        c.davisStationId = nil
        c.davisStationName = nil
        c.davisAvailableStations = []
        c.davisDetectedSensors = []
        c.davisHasLeafWetnessSensor = false
        c.davisLastTestSuccess = nil
        c.davisLastTestError = nil
        config = c
        persist()
        davisStations = []
        davisTestSucceeded = false
        isEditingDavisCredentials = false
        davisTestMessage = "Davis credentials removed."
    }

    private var currentStationLabel: String {
        if let name = config.davisStationName, !name.isEmpty { return name }
        if let sid = config.davisStationId, !sid.isEmpty { return "Station \(sid)" }
        return "Choose station"
    }

    private func testDavisConnection() async {
        guard config.davisHasCredentials else { return }
        guard let apiKey = WeatherKeychain.get(.apiKey),
              let apiSecret = WeatherKeychain.get(.apiSecret),
              !apiKey.isEmpty, !apiSecret.isEmpty else {
            davisTestSucceeded = false
            davisTestMessage = "Save credentials before testing."
            return
        }
        isTestingDavis = true
        davisTestMessage = nil
        davisTestSucceeded = false
        defer { isTestingDavis = false }

        do {
            let stations = try await DavisWeatherLinkService.fetchStations(
                apiKey: apiKey,
                apiSecret: apiSecret
            )
            davisStations = stations
            var c = config
            c.davisAvailableStations = stations
            c.davisConnectionTested = true
            c.davisLastTestSuccess = Date()
            c.davisLastTestError = nil

            // Auto-select if exactly one station, otherwise prompt user.
            if stations.count == 1 {
                c.davisStationId = stations[0].stationId
                c.davisStationName = stations[0].name
            } else if let existing = c.davisStationId,
                      stations.contains(where: { $0.stationId == existing }) {
                // Keep existing valid selection.
                if let match = stations.first(where: { $0.stationId == existing }) {
                    c.davisStationName = match.name
                }
            } else {
                c.davisStationId = nil
                c.davisStationName = nil
            }

            // If we have a selected station, fetch current to detect sensors.
            if let sid = c.davisStationId {
                do {
                    let cur = try await DavisWeatherLinkService.fetchCurrentConditions(
                        apiKey: apiKey,
                        apiSecret: apiSecret,
                        stationId: sid
                    )
                    c.davisDetectedSensors = cur.sensors.displayList
                    c.davisHasLeafWetnessSensor = cur.sensors.hasLeafWetness
                    c.lastSuccessfulUpdate = cur.generatedAt
                } catch {
                    // Station picked but current fetch failed — don't
                    // fail the whole test; just leave sensors unknown.
                    c.davisDetectedSensors = []
                    c.davisHasLeafWetnessSensor = false
                }
            } else {
                c.davisDetectedSensors = []
                c.davisHasLeafWetnessSensor = false
            }

            config = c
            persist()
            davisTestSucceeded = true
            if stations.count == 1 {
                davisTestMessage = c.davisHasLeafWetnessSensor
                    ? "Connected to WeatherLink. Measured leaf wetness available."
                    : "Connected to WeatherLink. No leaf wetness sensor detected — using estimated wetness."
            } else if c.davisStationId == nil {
                davisTestMessage = "Connected. Select a station to detect sensors."
            } else {
                davisTestMessage = "Connected to WeatherLink."
            }
        } catch let e as DavisWeatherLinkError {
            var c = config
            c.davisLastTestError = e.errorDescription
            c.davisLastTestSuccess = nil
            c.davisConnectionTested = false
            config = c
            persist()
            davisTestSucceeded = false
            davisTestMessage = e.errorDescription
        } catch {
            davisTestSucceeded = false
            davisTestMessage = "WeatherLink unavailable — \(error.localizedDescription)"
        }
    }

    private func selectDavisStation(_ station: DavisStation) async {
        guard let apiKey = WeatherKeychain.get(.apiKey),
              let apiSecret = WeatherKeychain.get(.apiSecret) else { return }
        var c = config
        c.davisStationId = station.stationId
        c.davisStationName = station.name
        config = c
        persist()

        do {
            let cur = try await DavisWeatherLinkService.fetchCurrentConditions(
                apiKey: apiKey,
                apiSecret: apiSecret,
                stationId: station.stationId
            )
            var c2 = config
            c2.davisDetectedSensors = cur.sensors.displayList
            c2.davisHasLeafWetnessSensor = cur.sensors.hasLeafWetness
            c2.lastSuccessfulUpdate = cur.generatedAt
            config = c2
            persist()
            davisTestSucceeded = true
            davisTestMessage = c2.davisHasLeafWetnessSensor
                ? "Station selected. Measured leaf wetness available."
                : "Station selected. No leaf wetness sensor detected — using estimated wetness."
        } catch let e as DavisWeatherLinkError {
            davisTestSucceeded = false
            davisTestMessage = e.errorDescription
        } catch {
            davisTestSucceeded = false
            davisTestMessage = "Could not load current conditions — \(error.localizedDescription)"
        }
    }
}
