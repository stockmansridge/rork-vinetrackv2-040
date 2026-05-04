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
    @State private var showClearDavisCacheConfirm: Bool = false
    @State private var davisCacheClearedMessage: String?
    @State private var vineyardIntegration: VineyardWeatherIntegration?
    @State private var isLoadingVineyardIntegration: Bool = false
    @State private var vineyardIntegrationError: String?
    @State private var showMigratePrompt: Bool = false
    @State private var isMigrating: Bool = false
    @State private var migrationMessage: String?

    private let integrationRepository: any VineyardWeatherIntegrationRepositoryProtocol
        = SupabaseVineyardWeatherIntegrationRepository()

    private var canEdit: Bool { accessControl.canChangeSettings }
    private var isOperator: Bool { !canEdit }

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
                return "The API Secret authorises access to your Davis WeatherLink data. VineTrack stores it as part of this vineyard's shared weather integration so every member uses the same station for rainfall, current conditions and disease risk. Only owners and managers can view or change credentials; operators see the configured station and status without secrets.\n\nGenerate the secret alongside the API Key from Account Settings → Generate v2 Key on weatherlink.com."
            case .stationId:
                return "VineTrack loads stations directly from WeatherLink after a successful Test Connection. If your account has more than one station, you can pick the correct vineyard station from the list. The Station ID is read from the API — you don't need to enter it manually."
            }
        }
    }

    private var vineyardId: UUID? { store.selectedVineyardId }

    var body: some View {
        Form {
            headerSection
            if showMigratePrompt && canEdit { migrationPromptSection }
            if let msg = migrationMessage, !msg.isEmpty {
                Section { Text(msg).font(.caption).foregroundStyle(.secondary) }
            }
            currentSourceSection

            forecastSourceSection

            localObservationSection

            if config.localObservationProvider == .wunderground {
                weatherUndergroundSection
            }

            if config.localObservationProvider == .davis {
                davisSection
                davisHelpSection
            }

            historicalFallbackSection

            usageSection

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
        .confirmationDialog(
            "Clear cached Davis rainfall data?",
            isPresented: $showClearDavisCacheConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear Cache", role: .destructive) {
                clearDavisRainfallCache()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove saved rainfall totals from this device. The Rainfall Calendar will refetch local station data next time it loads.")
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

    private var migrationPromptSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "icloud.and.arrow.up")
                        .font(.title3)
                        .foregroundStyle(.orange)
                        .frame(width: 32, height: 32)
                        .background(Color.orange.opacity(0.15), in: .rect(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Move Davis WeatherLink setup to this vineyard?")
                            .font(.subheadline.weight(.semibold))
                        Text("This device has Davis credentials, but they are not yet shared with other vineyard members. Move them to the vineyard so every member sees the same rainfall, station and disease-risk data.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                HStack {
                    Button {
                        Task { await runMigrationToVineyard() }
                    } label: {
                        HStack {
                            if isMigrating { ProgressView().controlSize(.small) }
                            Text(isMigrating ? "Moving…" : "Move to vineyard")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(.orange)
                    .disabled(isMigrating)

                    Button("Not now") { showMigratePrompt = false }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Vineyard sharing")
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

    // MARK: - Forecast Source (read-only role)

    private var forecastSourceSection: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                SettingsIconTile(symbol: ForecastProvider.openMeteo.symbol, color: .blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text(config.forecastProvider.displayName)
                        .font(.subheadline.weight(.semibold))
                    Text(config.forecastProvider.helpCopy)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("No setup required.")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green)
                        .padding(.top, 2)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 2)
        } header: {
            Text("Forecast Source")
        } footer: {
            Text("Davis and Weather Underground are used for actual observations. Forecasts always come from Open-Meteo.")
        }
    }

    // MARK: - Local Observation Source (user-selectable role)

    private var localObservationSection: some View {
        Section {
            ForEach(LocalObservationProvider.allCases) { provider in
                Button {
                    guard canEdit else { return }
                    var c = config
                    c.localObservationProvider = provider
                    config = c
                    persist()
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        SettingsIconTile(symbol: provider.symbol, color: localProviderColor(provider))
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(provider.displayName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                if provider == .none {
                                    Text("Default")
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
                        if config.localObservationProvider == provider {
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
            Text("Local Observation Source")
        } footer: {
            Text("Used for actual rainfall, local station readings and measured leaf wetness where available. Forecasts still use Open-Meteo regardless of this choice.")
        }
    }

    // MARK: - Historical Fallback (read-only role)

    private var historicalFallbackSection: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                SettingsIconTile(symbol: HistoricalFallbackProvider.openMeteoArchive.symbol, color: .gray)
                VStack(alignment: .leading, spacing: 4) {
                    Text(config.historicalFallbackProvider.displayName)
                        .font(.subheadline.weight(.semibold))
                    Text(config.historicalFallbackProvider.helpCopy)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("No setup required.")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green)
                        .padding(.top, 2)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 2)
        } header: {
            Text("Historical Fallback")
        } footer: {
            Text("Used for the Rainfall Calendar's older periods and as a fallback when local station history is unavailable.")
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
        let hasOrphanStation = !config.davisHasCredentials
            && ((config.davisStationName?.isEmpty == false)
                || (config.davisStationId?.isEmpty == false))

        // TODO: Vineyard-shared weather station connections can be added later
        // using encrypted/server-side credential storage. For now Davis API
        // Key & API Secret live only in this device's iOS Keychain and are
        // never written to Supabase or vineyard settings.

        return Section {
            // Privacy / per-device notice
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "iphone.and.arrow.forward")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                Text(canEdit
                    ? "Davis WeatherLink is configured for this vineyard. Owners and managers can manage the station connection. All vineyard users use the same weather source for consistent rainfall and disease-risk data."
                    : "Davis WeatherLink is managed by your vineyard owner or manager. You can see the selected station and source status, but cannot view or change credentials.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }

            // Orphan station — station metadata exists but no credentials on
            // this device (e.g. signed in on a new device, or another team
            // member). Surface a clear, actionable state.
            if hasOrphanStation {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "key.slash")
                            .font(.title3)
                            .foregroundStyle(.orange)
                            .frame(width: 32, height: 32)
                            .background(Color.orange.opacity(0.15), in: .rect(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Davis station was previously selected, but credentials are not saved on this device.")
                                .font(.subheadline.weight(.semibold))
                            if let name = config.davisStationName, !name.isEmpty {
                                Text("Last station: \(name)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text("Enter your Davis API Key and Secret below to reconnect on this device.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    Button {
                        isEditingDavisCredentials = true
                    } label: {
                        Label("Enter Davis credentials", systemImage: "key.fill")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(.orange)
                    .disabled(!canEdit)
                }
                .padding(.vertical, 4)
            }

            // 1. Saved status card on top
            if savedAndNotEditing && canEdit {
                savedStatusCard
            }

            // For operators, surface the configured station and basic
            // status only — never the API key/secret or test/edit
            // controls. Reads still go through the davis-proxy edge
            // function under the hood.
            if !canEdit {
                operatorReadOnlyDavisCard
            } else {
                ownerEditableDavisControls
            }
        } header: {
            Text("Davis WeatherLink")
        } footer: {
            Text(canEdit
                ? "Credentials are stored as part of this vineyard's shared weather integration. All members use the same station; only owners and managers can change them."
                : "All vineyard members use the same Davis station via a secure server-side connection. Owners and managers can change credentials.")
        }
    }

    @ViewBuilder
    private var operatorReadOnlyDavisCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "person.badge.shield.checkmark.fill")
                    .font(.title3)
                    .foregroundStyle(.indigo)
                    .frame(width: 32, height: 32)
                    .background(Color.indigo.opacity(0.12), in: .rect(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Davis WeatherLink is configured for this vineyard.")
                        .font(.subheadline.weight(.semibold))
                    Text("Managed by your owner or manager.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            if let name = config.davisStationName, !name.isEmpty {
                LabeledContent("Station") {
                    Text(name).foregroundStyle(.secondary).lineLimit(1)
                }
            } else if let sid = config.davisStationId, !sid.isEmpty {
                LabeledContent("Station") {
                    Text("Station \(sid)").foregroundStyle(.secondary)
                }
            }
            if !config.davisDetectedSensors.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Detected sensors")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(config.davisDetectedSensors, id: \.self) { sensor in
                        Label(sensor, systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }
            if config.davisHasLeafWetnessSensor {
                Label("Measured leaf wetness available", systemImage: "drop.fill")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
            Text("Actual rainfall source: Davis WeatherLink\((config.davisStationName?.isEmpty == false) ? " — \(config.davisStationName!)" : "")")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var ownerEditableDavisControls: some View {
        let savedAndNotEditing = config.davisHasCredentials && !isEditingDavisCredentials
        Group {
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
            } else if config.davisHasCredentials, config.davisConnectionTested {
                // Connection tested but no station picked yet — emphasise.
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label("Selected station", systemImage: "antenna.radiowaves.left.and.right")
                        infoButton(.stationId)
                        Spacer()
                        Text("Station required")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.orange.opacity(0.18), in: .capsule)
                            .foregroundStyle(.orange)
                    }
                    Text("Choose which Davis station VineTrack should use for rainfall, current conditions and leaf wetness.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Button {
                        showDavisStationPicker = true
                    } label: {
                        Label("Choose station", systemImage: "chevron.right")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(.orange)
                    .disabled(!canEdit || (config.davisAvailableStations.isEmpty && davisStations.isEmpty))
                }
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
                    let needsStation = davisTestSucceeded
                        && config.davisConnectionTested
                        && (config.davisStationId ?? "").isEmpty
                    Text(msg)
                        .font(.caption2)
                        .foregroundStyle(needsStation ? .orange : (davisTestSucceeded ? .green : .secondary))
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Verifies your WeatherLink account and loads available stations.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if config.davisHasCredentials {
                Button {
                    showClearDavisCacheConfirm = true
                } label: {
                    Label("Clear Davis rainfall cache", systemImage: "arrow.clockwise.icloud")
                }
                .disabled(!canEdit)
                if let msg = davisCacheClearedMessage, !msg.isEmpty {
                    Text(msg)
                        .font(.caption2)
                        .foregroundStyle(.green)
                }

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
                Label("Your API Secret is encrypted and stored as part of this vineyard's shared weather integration.", systemImage: "lock.shield")
                Label("All vineyard members see the same station and rainfall data.", systemImage: "person.3.fill")
                Label("Only owners and managers can view or replace credentials.", systemImage: "person.badge.key")
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

    private func localProviderColor(_ p: LocalObservationProvider) -> Color {
        switch p {
        case .none: return .blue
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
        // Reconcile local keychain state for owner/manager direct fetches.
        c.davisHasCredentials = WeatherKeychain.hasCredentials
        if !c.davisHasCredentials {
            c.davisConnectionTested = false
        }
        config = c
        davisStations = c.davisAvailableStations
        Task { await loadVineyardIntegration(for: vid) }
    }

    private func loadVineyardIntegration(for vineyardId: UUID) async {
        isLoadingVineyardIntegration = true
        defer { isLoadingVineyardIntegration = false }
        do {
            let integ = try await integrationRepository.fetch(
                vineyardId: vineyardId,
                provider: "davis_weatherlink"
            )
            vineyardIntegration = integ
            vineyardIntegrationError = nil
            applyIntegrationToConfig(integ)
            // Offer the migration prompt if this device has Keychain creds
            // but the vineyard has none yet, and the caller may write.
            if canEdit,
               WeatherKeychain.hasCredentials,
               (integ?.hasApiSecret != true) {
                showMigratePrompt = true
            }
        } catch {
            vineyardIntegration = nil
            vineyardIntegrationError = error.localizedDescription
        }
    }

    private func applyIntegrationToConfig(_ integ: VineyardWeatherIntegration?) {
        guard let vid = vineyardId else { return }
        var c = config
        if let integ {
            c.davisIsVineyardShared = true
            c.davisVineyardHasServerCredentials = integ.hasApiSecret
            c.davisVineyardConfiguredBy = integ.configuredBy
            c.davisVineyardUpdatedAt = integ.updatedAt
            // Shared station / sensor metadata is the source of truth
            // for every member.
            if let sid = integ.stationId, !sid.isEmpty {
                c.davisStationId = sid
                c.davisStationName = integ.stationName
                c.davisHasLeafWetnessSensor = integ.hasLeafWetness
                c.davisDetectedSensors = integ.detectedSensors
                c.davisConnectionTested = integ.lastTestStatus == "ok"
                    || integ.lastTestStatus == nil ? true : c.davisConnectionTested
            }
            // Operators have no local creds but should still see the source
            // as configured for read-only display.
            if isOperator { c.davisHasCredentials = false }
        } else {
            c.davisIsVineyardShared = false
            c.davisVineyardHasServerCredentials = false
            c.davisVineyardConfiguredBy = nil
            c.davisVineyardUpdatedAt = nil
        }
        config = c
        WeatherProviderStore.shared.save(c, for: vid)
    }

    /// Pushes the latest station + detected sensor state to the vineyard
    /// integration so every member sees the same source. No-op if the
    /// caller doesn't have edit rights or there's no Davis station yet.
    private func pushStationStateToVineyard() async {
        guard canEdit, let vid = vineyardId,
              let sid = config.davisStationId, !sid.isEmpty else { return }
        do {
            let payload = VineyardWeatherIntegrationSave(
                p_vineyard_id: vid,
                p_provider: "davis_weatherlink",
                p_api_key: nil,
                p_api_secret: nil,
                p_station_id: sid,
                p_station_name: config.davisStationName,
                p_station_latitude: nil,
                p_station_longitude: nil,
                p_has_leaf_wetness: config.davisHasLeafWetnessSensor,
                p_has_rain: true,
                p_has_wind: nil,
                p_has_temperature_humidity: nil,
                p_detected_sensors: config.davisDetectedSensors,
                p_last_tested_at: config.davisLastTestSuccess,
                p_last_test_status: "ok",
                p_is_active: true
            )
            try await integrationRepository.save(payload)
            VineyardWeatherIntegrationCache.shared.invalidate(vid)
            // Refresh the local snapshot.
            if let integ = try? await integrationRepository.fetch(
                vineyardId: vid, provider: "davis_weatherlink"
            ) {
                vineyardIntegration = integ
                applyIntegrationToConfig(integ)
            }
        } catch {
            // Don't surface a hard error — local fetch path still works.
        }
    }

    private func runMigrationToVineyard() async {
        guard canEdit, let vid = vineyardId,
              let apiKey = WeatherKeychain.get(.apiKey),
              let apiSecret = WeatherKeychain.get(.apiSecret),
              !apiKey.isEmpty, !apiSecret.isEmpty else { return }
        isMigrating = true
        defer { isMigrating = false }
        do {
            let payload = VineyardWeatherIntegrationSave(
                p_vineyard_id: vid,
                p_provider: "davis_weatherlink",
                p_api_key: apiKey,
                p_api_secret: apiSecret,
                p_station_id: config.davisStationId,
                p_station_name: config.davisStationName,
                p_station_latitude: nil,
                p_station_longitude: nil,
                p_has_leaf_wetness: config.davisHasLeafWetnessSensor,
                p_has_rain: true,
                p_has_wind: nil,
                p_has_temperature_humidity: nil,
                p_detected_sensors: config.davisDetectedSensors,
                p_last_tested_at: config.davisLastTestSuccess,
                p_last_test_status: config.davisConnectionTested ? "ok" : nil,
                p_is_active: true
            )
            try await integrationRepository.save(payload)
            VineyardWeatherIntegrationCache.shared.invalidate(vid)
            migrationMessage = "Davis setup moved to this vineyard. All members now use the same station."
            showMigratePrompt = false
            await loadVineyardIntegration(for: vid)
        } catch {
            migrationMessage = "Could not save vineyard integration — \(error.localizedDescription)"
        }
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

    private func clearDavisRainfallCache() {
        guard canEdit else { return }
        if let sid = config.davisStationId, !sid.isEmpty {
            DavisRainfallCache.clearAll(stationId: sid)
        } else {
            DavisRainfallCache.clearAll()
        }
        davisCacheClearedMessage = "Davis rainfall cache cleared."
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            davisCacheClearedMessage = nil
        }
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
            await pushStationStateToVineyard()
            davisTestSucceeded = true
            if stations.count == 1 {
                davisTestMessage = c.davisHasLeafWetnessSensor
                    ? "Connected to WeatherLink. Measured leaf wetness available."
                    : "Connected to WeatherLink. No leaf wetness sensor detected — using estimated wetness."
            } else if c.davisStationId == nil {
                davisTestMessage = "Connected. Select a station to finish setup."
                // Auto-present the picker so the next step is obvious.
                showDavisStationPicker = true
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
            await pushStationStateToVineyard()
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
