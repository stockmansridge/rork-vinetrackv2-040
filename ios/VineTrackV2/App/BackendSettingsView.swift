import SwiftUI

struct BackendSettingsView: View {
    @Environment(NewBackendAuthService.self) private var auth
    @Environment(MigratedDataStore.self) private var store
    @Environment(BackendAccessControl.self) private var accessControl
    @Environment(SubscriptionService.self) private var subscription
    @Environment(PinSyncService.self) private var pinSync
    @Environment(PaddockSyncService.self) private var paddockSync
    @Environment(TripSyncService.self) private var tripSync
    @Environment(SprayRecordSyncService.self) private var sprayRecordSync
    @Environment(ButtonConfigSyncService.self) private var buttonConfigSync

    @State private var showVineyardSwitcher: Bool = false
    @State private var showVineyardDetail: Bool = false
    @State private var isRefreshing: Bool = false
    @State private var refreshMessage: String?

    #if DEBUG
    @State private var showBackendDiagnostic: Bool = false
    @State private var showStoreDiagnostic: Bool = false
    #endif

    private let vineyardRepository: any VineyardRepositoryProtocol = SupabaseVineyardRepository()

    private static let adminEmails: Set<String> = ["jonathan@stockmansridge.com.au"]

    private var isAdminUser: Bool {
        guard let email = auth.userEmail?.lowercased() else { return false }
        return Self.adminEmails.contains(email)
    }

    private var pendingInvitationCount: Int {
        let userEmail = (auth.userEmail ?? "").lowercased()
        let memberIds = Set(store.vineyards.map { $0.id })
        return auth.pendingInvitations
            .filter { $0.status.lowercased() == "pending" }
            .filter { userEmail.isEmpty || $0.email.lowercased() == userEmail }
            .filter { !memberIds.contains($0.vineyardId) }
            .count
    }

    var body: some View {
        NavigationStack {
            Form {
                accountSection
                vineyardSection
                operationsSection
                if let vineyard = store.selectedVineyard {
                    teamSection(vineyard: vineyard)
                }

                Section {
                    NavigationLink {
                        SubscriptionSettingsView()
                    } label: {
                        SettingsRow(
                            title: "Subscription",
                            subtitle: subscriptionSubtitle,
                            symbol: "creditcard.fill",
                            color: .pink
                        )
                    }
                    NavigationLink {
                        PreferencesHubView()
                    } label: {
                        SettingsRow(
                            title: "Preferences",
                            subtitle: "Appearance, season, tracking & photos",
                            symbol: "slider.horizontal.3",
                            color: .indigo
                        )
                    }
                    NavigationLink {
                        AlertSettingsView()
                    } label: {
                        SettingsRow(
                            title: "Alerts & Notifications",
                            subtitle: "Irrigation, pins, weather & spray reminders",
                            symbol: "bell.badge.fill",
                            color: .red
                        )
                    }
                    NavigationLink {
                        WeatherDataSettingsView()
                    } label: {
                        SettingsRow(
                            title: "Weather Data & Forecasting",
                            subtitle: "Forecast source, station & sensors",
                            symbol: "cloud.sun.fill",
                            color: .orange
                        )
                    }
                    NavigationLink {
                        SyncSettingsView()
                    } label: {
                        SettingsRow(
                            title: "Sync",
                            subtitle: "Cloud sync for pins, paddocks & trips",
                            symbol: "icloud.and.arrow.up",
                            color: .blue
                        )
                    }
                    NavigationLink {
                        SyncDiagnosticsView()
                    } label: {
                        SettingsRow(
                            title: "Sync Diagnostics",
                            subtitle: "Pending uploads, last sync & status",
                            symbol: "stethoscope",
                            color: .teal
                        )
                    }
                } header: {
                    SettingsSectionHeader(title: "Preferences & Data", symbol: "gearshape.fill", color: .indigo)
                }

                if isAdminUser {
                    adminSection
                }

                accountPrivacySection
                aboutSection

                #if DEBUG
                debugSection
                #endif

                signOutSection
            }
            .navigationTitle("Settings")
            .refreshable { await refreshVineyards() }
            .sheet(isPresented: $showVineyardSwitcher) {
                BackendVineyardListView()
            }
            .sheet(isPresented: $showVineyardDetail) {
                if let vineyard = store.selectedVineyard {
                    BackendVineyardDetailSheet(vineyard: vineyard)
                }
            }
            #if DEBUG
            .sheet(isPresented: $showBackendDiagnostic) {
                BackendDiagnosticHostView()
            }
            .sheet(isPresented: $showStoreDiagnostic) {
                MigratedDataStoreDiagnosticView()
            }
            #endif
        }
    }

    // MARK: - Sections

    private var accountSection: some View {
        Section {
            NavigationLink {
                EditDisplayNameView()
            } label: {
                SettingsRow(
                    title: "Name",
                    subtitle: auth.userName ?? "—",
                    symbol: "person.crop.circle.fill",
                    color: .gray
                )
            }
            HStack(spacing: 12) {
                SettingsIconTile(symbol: "envelope.fill", color: .blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Email")
                        .font(.subheadline.weight(.medium))
                    Text(auth.userEmail ?? "—")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            SettingsSectionHeader(title: "Account", symbol: "person.fill", color: .gray)
        }
    }

    private var vineyardSection: some View {
        Section {
            if let vineyard = store.selectedVineyard {
                Button {
                    showVineyardDetail = true
                } label: {
                    HStack(spacing: 12) {
                        vineyardThumbnail(vineyard)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(vineyard.name)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                if vineyard.id == auth.defaultVineyardId {
                                    Label("Default", systemImage: "star.fill")
                                        .labelStyle(.titleAndIcon)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.orange)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.15), in: Capsule())
                                }
                            }
                            if !vineyard.country.isEmpty {
                                Text(vineyard.country)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                if let defaultId = auth.defaultVineyardId,
                   let defaultVineyard = store.vineyards.first(where: { $0.id == defaultId }),
                   defaultId != vineyard.id {
                    HStack(spacing: 12) {
                        SettingsIconTile(symbol: "star.fill", color: .orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Default Vineyard")
                                .font(.subheadline.weight(.medium))
                            Text(defaultVineyard.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                } else if auth.defaultVineyardId == nil {
                    Button {
                        Task { await auth.setDefaultVineyard(vineyard.id) }
                    } label: {
                        Label("Make this vineyard default", systemImage: "star")
                            .foregroundStyle(.orange)
                    }
                }
            } else {
                Text("No vineyard selected")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button {
                showVineyardSwitcher = true
            } label: {
                HStack {
                    Label("Change Vineyard", systemImage: "arrow.triangle.swap")
                        .foregroundStyle(.primary)
                    Spacer()
                    let count = pendingInvitationCount
                    if count > 0 {
                        Text("\(count)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.red, in: Capsule())
                            .accessibilityLabel("\(count) pending invitations")
                    }
                }
            }
        } header: {
            SettingsSectionHeader(title: "Vineyard", symbol: "building.2.fill", color: VineyardTheme.leafGreen)
        }
    }

    @ViewBuilder
    private func vineyardThumbnail(_ vineyard: Vineyard) -> some View {
        if let data = vineyard.logoData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 40, height: 40)
                .clipShape(.rect(cornerRadius: 8))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(VineyardTheme.leafGreen.gradient)
                    .frame(width: 40, height: 40)
                GrapeLeafIcon(size: 20, color: .white)
            }
        }
    }

    private var operationsSection: some View {
        Section {
            NavigationLink {
                VineyardSetupHubView()
            } label: {
                SettingsRow(
                    title: "Vineyard Setup",
                    subtitle: "Blocks, Buttons & Growth Stages",
                    symbol: "square.grid.2x2.fill",
                    color: VineyardTheme.leafGreen
                )
            }
            NavigationLink {
                SprayEquipmentHubView()
            } label: {
                SettingsRow(
                    title: "Spray & Equipment",
                    subtitle: "Spray Management, Equipment & Tractors, Chemicals",
                    symbol: "drop.fill",
                    color: .teal
                )
            }
            NavigationLink {
                TeamOperationsHubView()
            } label: {
                SettingsRow(
                    title: "Team Operations",
                    subtitle: "Operator Categories",
                    symbol: "person.2.fill",
                    color: .blue
                )
            }
            NavigationLink {
                TripFunctionsSettingsView()
            } label: {
                SettingsRow(
                    title: "Trip Functions",
                    subtitle: "Built-ins and custom vineyard trip functions",
                    symbol: "wrench.and.screwdriver.fill",
                    color: VineyardTheme.earthBrown
                )
            }
            NavigationLink {
                OperationPreferencesView()
            } label: {
                SettingsRow(
                    title: "Operation Preferences",
                    subtitle: "Season E-L, spray/tank, yield",
                    symbol: "slider.horizontal.3",
                    color: .orange
                )
            }
        } header: {
            SettingsSectionHeader(title: "Operations", symbol: "wrench.adjustable.fill", color: .orange)
        }
    }

    private func teamSection(vineyard: Vineyard) -> some View {
        Section {
            NavigationLink {
                BackendTeamAccessView(vineyardId: vineyard.id, vineyardName: vineyard.name)
            } label: {
                SettingsRow(
                    title: "Team & Access",
                    subtitle: "Manage members and invitations",
                    symbol: "person.2.fill",
                    color: .teal
                )
            }
            NavigationLink {
                RolesPermissionsInfoView()
            } label: {
                SettingsRow(
                    title: "Roles & Permissions",
                    subtitle: "How access works for your team",
                    symbol: "person.badge.shield.checkmark.fill",
                    color: .purple
                )
            }
        } header: {
            SettingsSectionHeader(title: "Team", symbol: "person.2.fill", color: .teal)
        }
    }

    private var adminSection: some View {
        Section {
            NavigationLink {
                AdminDashboardView()
            } label: {
                SettingsRow(
                    title: "Admin Dashboard",
                    subtitle: "Engagement summary & user support",
                    symbol: "shield.lefthalf.filled",
                    color: .purple
                )
            }
        } header: {
            SettingsSectionHeader(title: "Admin", symbol: "shield.lefthalf.filled", color: .purple)
        } footer: {
            Text("Visible only to authorized admin accounts.")
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: "\(appVersion) (\(appBuild))")
            LabeledContent("Disclaimer", value: "v\(DisclaimerInfo.version)")
            LabeledContent("Backend", value: SupabaseClientProvider.shared.isConfigured ? "Connected" : "Not configured")
        } header: {
            SettingsSectionHeader(title: "About", symbol: "info.circle.fill", color: .gray)
        }
    }

    private var accountPrivacySection: some View {
        Section {
            if let url = URL(string: "https://vinetrack.com.au/privacy") {
                Link(destination: url) {
                    SettingsRow(
                        title: "Privacy Policy",
                        subtitle: "How we handle your data",
                        symbol: "hand.raised.fill",
                        color: .blue
                    )
                }
            }
            if let url = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/") {
                Link(destination: url) {
                    SettingsRow(
                        title: "Terms of Use (EULA)",
                        subtitle: "Apple standard end-user license",
                        symbol: "doc.text.fill",
                        color: .gray
                    )
                }
            }
            NavigationLink {
                DisclaimerInfoView()
            } label: {
                SettingsRow(
                    title: "Disclaimer",
                    subtitle: "Important usage notes",
                    symbol: "exclamationmark.shield.fill",
                    color: .orange
                )
            }
            NavigationLink {
                AccountDeletionRequestView()
            } label: {
                SettingsRow(
                    title: "Request Account Deletion",
                    subtitle: "Permanently remove your account",
                    symbol: "person.crop.circle.badge.xmark",
                    color: .red
                )
            }
        } header: {
            SettingsSectionHeader(title: "Account & Privacy", symbol: "lock.shield.fill", color: .blue)
        }
    }

    #if DEBUG
    private var debugSection: some View {
        Section {
            Button {
                showBackendDiagnostic = true
            } label: {
                Label("Backend Diagnostic", systemImage: "stethoscope")
            }
            Button {
                showStoreDiagnostic = true
            } label: {
                Label("MigratedDataStore Diagnostic", systemImage: "tray.full")
            }
        } header: {
            Text("Diagnostics")
        }
    }
    #endif

    private var signOutSection: some View {
        Section {
            Button(role: .destructive) {
                Task {
                    await auth.signOut()
                    store.clearInMemoryState()
                }
            } label: {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
            }
        }
    }

    // MARK: - Helpers

    private var subscriptionSubtitle: String {
        if subscription.isSubscribed { return "Vineyard Tracker Pro — active" }
        if subscription.isInInitialFreeAccessPeriod {
            if let freeAccessEndsAt = subscription.freeAccessEndsAt {
                return "Free access until \(freeAccessEndsAt.formatted(date: .abbreviated, time: .omitted))"
            }
            return "Free access active"
        }
        switch subscription.status {
        case .loading, .unknown: return "Checking…"
        default: return "Manage your plan"
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    private func refreshVineyards() async {
        isRefreshing = true
        refreshMessage = nil
        defer { isRefreshing = false }
        do {
            let backendVineyards = try await vineyardRepository.listMyVineyards()
            store.mapBackendVineyardsIntoLocal(backendVineyards)
            refreshMessage = "Loaded \(backendVineyards.count) vineyard\(backendVineyards.count == 1 ? "" : "s")."
        } catch {
            refreshMessage = error.localizedDescription
        }
    }
}

// MARK: - Sync Settings (extracted)

struct SyncSettingsView: View {
    @Environment(PinSyncService.self) private var pinSync
    @Environment(PaddockSyncService.self) private var paddockSync
    @Environment(TripSyncService.self) private var tripSync
    @Environment(SprayRecordSyncService.self) private var sprayRecordSync
    @Environment(ButtonConfigSyncService.self) private var buttonConfigSync
    @Environment(SavedChemicalSyncService.self) private var savedChemicalSync
    @Environment(SavedSprayPresetSyncService.self) private var savedSprayPresetSync
    @Environment(SprayEquipmentSyncService.self) private var sprayEquipmentSync
    @Environment(TractorSyncService.self) private var tractorSync
    @Environment(FuelPurchaseSyncService.self) private var fuelPurchaseSync
    @Environment(OperatorCategorySyncService.self) private var operatorCategorySync
    @Environment(GrowthStageImageSyncService.self) private var growthStageImageSync
    @Environment(WorkTaskSyncService.self) private var workTaskSync
    @Environment(WorkTaskLabourLineSyncService.self) private var workTaskLabourLineSync
    @Environment(WorkTaskPaddockSyncService.self) private var workTaskPaddockSync
    @Environment(MaintenanceLogSyncService.self) private var maintenanceLogSync
    @Environment(YieldEstimationSessionSyncService.self) private var yieldSessionSync
    @Environment(DamageRecordSyncService.self) private var damageRecordSync
    @Environment(HistoricalYieldRecordSyncService.self) private var historicalYieldSync

    var body: some View {
        Form {
            Section {
                Button {
                    Task { await pinSync.syncPinsForSelectedVineyard() }
                } label: {
                    syncButtonLabel(title: "Sync Pins", icon: "mappin.and.ellipse", isSyncing: isSyncing(pinSync.syncStatus))
                }
                .disabled(isSyncing(pinSync.syncStatus))
                VineyardSyncStatusRow(label: "pins", state: pinStateFrom(pinSync.syncStatus, lastSync: pinSync.lastSyncDate))

                Button {
                    Task { await paddockSync.syncPaddocksForSelectedVineyard() }
                } label: {
                    syncButtonLabel(title: "Sync Paddocks", icon: "square.grid.2x2", isSyncing: isSyncing(paddockSync.syncStatus))
                }
                .disabled(isSyncing(paddockSync.syncStatus))
                VineyardSyncStatusRow(label: "paddocks", state: paddockStateFrom(paddockSync.syncStatus, lastSync: paddockSync.lastSyncDate))

                Button {
                    Task { await tripSync.syncTripsForSelectedVineyard() }
                } label: {
                    syncButtonLabel(title: "Sync Trips", icon: "map", isSyncing: isSyncing(tripSync.syncStatus))
                }
                .disabled(isSyncing(tripSync.syncStatus))
                VineyardSyncStatusRow(label: "trips", state: tripStateFrom(tripSync.syncStatus, lastSync: tripSync.lastSyncDate))

                Button {
                    Task { await sprayRecordSync.syncSprayRecordsForSelectedVineyard() }
                } label: {
                    syncButtonLabel(title: "Sync Spray Records", icon: "drop.fill", isSyncing: isSyncing(sprayRecordSync.syncStatus))
                }
                .disabled(isSyncing(sprayRecordSync.syncStatus))
                VineyardSyncStatusRow(label: "spray records", state: sprayStateFrom(sprayRecordSync.syncStatus, lastSync: sprayRecordSync.lastSyncDate))

                Button {
                    Task { await buttonConfigSync.syncButtonConfigForSelectedVineyard() }
                } label: {
                    syncButtonLabel(title: "Sync Button Config", icon: "square.grid.2x2", isSyncing: isSyncing(buttonConfigSync.syncStatus))
                }
                .disabled(isSyncing(buttonConfigSync.syncStatus))
                VineyardSyncStatusRow(label: "button config", state: buttonConfigStateFrom(buttonConfigSync.syncStatus, lastSync: buttonConfigSync.lastSyncDate))
            } footer: {
                Text("Pins, paddocks, trips, spray records, and button config sync to Supabase.")
            }

            Section {
                Button {
                    Task { await savedChemicalSync.syncForSelectedVineyard() }
                } label: {
                    syncButtonLabel(title: "Sync Saved Chemicals", icon: "flask.fill", isSyncing: isSyncingMgmt(savedChemicalSync.syncStatus))
                }
                .disabled(isSyncingMgmt(savedChemicalSync.syncStatus))
                VineyardSyncStatusRow(label: "saved chemicals", state: mgmtStateFrom(savedChemicalSync.syncStatus, lastSync: savedChemicalSync.lastSyncDate))

                Button {
                    Task { await savedSprayPresetSync.syncForSelectedVineyard() }
                } label: {
                    syncButtonLabel(title: "Sync Spray Presets", icon: "slider.horizontal.3", isSyncing: isSyncingMgmt(savedSprayPresetSync.syncStatus))
                }
                .disabled(isSyncingMgmt(savedSprayPresetSync.syncStatus))
                VineyardSyncStatusRow(label: "spray presets", state: mgmtStateFrom(savedSprayPresetSync.syncStatus, lastSync: savedSprayPresetSync.lastSyncDate))

                Button {
                    Task { await sprayEquipmentSync.syncForSelectedVineyard() }
                } label: {
                    syncButtonLabel(title: "Sync Spray Equipment", icon: "sprinkler.and.droplets.fill", isSyncing: isSyncingMgmt(sprayEquipmentSync.syncStatus))
                }
                .disabled(isSyncingMgmt(sprayEquipmentSync.syncStatus))
                VineyardSyncStatusRow(label: "spray equipment", state: mgmtStateFrom(sprayEquipmentSync.syncStatus, lastSync: sprayEquipmentSync.lastSyncDate))

                Button {
                    Task { await tractorSync.syncForSelectedVineyard() }
                } label: {
                    syncButtonLabel(title: "Sync Tractors", icon: "car.fill", isSyncing: isSyncingMgmt(tractorSync.syncStatus))
                }
                .disabled(isSyncingMgmt(tractorSync.syncStatus))
                VineyardSyncStatusRow(label: "tractors", state: mgmtStateFrom(tractorSync.syncStatus, lastSync: tractorSync.lastSyncDate))

                Button {
                    Task { await fuelPurchaseSync.syncForSelectedVineyard() }
                } label: {
                    syncButtonLabel(title: "Sync Fuel Purchases", icon: "fuelpump.fill", isSyncing: isSyncingMgmt(fuelPurchaseSync.syncStatus))
                }
                .disabled(isSyncingMgmt(fuelPurchaseSync.syncStatus))
                VineyardSyncStatusRow(label: "fuel purchases", state: mgmtStateFrom(fuelPurchaseSync.syncStatus, lastSync: fuelPurchaseSync.lastSyncDate))

                Button {
                    Task { await operatorCategorySync.syncForSelectedVineyard() }
                } label: {
                    syncButtonLabel(title: "Sync Operator Categories", icon: "person.2.fill", isSyncing: isSyncingMgmt(operatorCategorySync.syncStatus))
                }
                .disabled(isSyncingMgmt(operatorCategorySync.syncStatus))
                VineyardSyncStatusRow(label: "operator categories", state: mgmtStateFrom(operatorCategorySync.syncStatus, lastSync: operatorCategorySync.lastSyncDate))
            } header: {
                Text("Spray Management")
            } footer: {
                Text("Saved chemicals, presets, equipment, tractors, fuel and operator categories sync across vineyard members.")
            }

            Section {
                Button {
                    Task { await workTaskSync.syncForSelectedVineyard() }
                } label: {
                    syncButtonLabel(title: "Sync Work Tasks", icon: "person.2.badge.gearshape.fill", isSyncing: isSyncingOps(workTaskSync.syncStatus))
                }
                .disabled(isSyncingOps(workTaskSync.syncStatus))
                VineyardSyncStatusRow(label: "work tasks", state: opsStateFrom(workTaskSync.syncStatus, lastSync: workTaskSync.lastSyncDate))

                Button {
                    Task { await workTaskLabourLineSync.syncForSelectedVineyard() }
                } label: {
                    syncButtonLabel(title: "Sync Work Task Labour Lines", icon: "clock.badge.checkmark.fill", isSyncing: isSyncingOps(workTaskLabourLineSync.syncStatus))
                }
                .disabled(isSyncingOps(workTaskLabourLineSync.syncStatus))
                VineyardSyncStatusRow(label: "work task labour lines", state: opsStateFrom(workTaskLabourLineSync.syncStatus, lastSync: workTaskLabourLineSync.lastSyncDate))

                Button {
                    Task { await workTaskPaddockSync.syncForSelectedVineyard() }
                } label: {
                    syncButtonLabel(title: "Sync Work Task Paddocks", icon: "square.grid.2x2", isSyncing: isSyncingOps(workTaskPaddockSync.syncStatus))
                }
                .disabled(isSyncingOps(workTaskPaddockSync.syncStatus))
                VineyardSyncStatusRow(label: "work task paddocks", state: opsStateFrom(workTaskPaddockSync.syncStatus, lastSync: workTaskPaddockSync.lastSyncDate))

                Button {
                    Task { await maintenanceLogSync.syncForSelectedVineyard() }
                } label: {
                    syncButtonLabel(title: "Sync Maintenance Logs", icon: "wrench.and.screwdriver.fill", isSyncing: isSyncingOps(maintenanceLogSync.syncStatus))
                }
                .disabled(isSyncingOps(maintenanceLogSync.syncStatus))
                VineyardSyncStatusRow(label: "maintenance logs", state: opsStateFrom(maintenanceLogSync.syncStatus, lastSync: maintenanceLogSync.lastSyncDate))

                Button {
                    Task { await yieldSessionSync.syncForSelectedVineyard() }
                } label: {
                    syncButtonLabel(title: "Sync Yield Sessions", icon: "chart.bar.fill", isSyncing: isSyncingOps(yieldSessionSync.syncStatus))
                }
                .disabled(isSyncingOps(yieldSessionSync.syncStatus))
                VineyardSyncStatusRow(label: "yield sessions", state: opsStateFrom(yieldSessionSync.syncStatus, lastSync: yieldSessionSync.lastSyncDate))

                Button {
                    Task { await damageRecordSync.syncForSelectedVineyard() }
                } label: {
                    syncButtonLabel(title: "Sync Damage Records", icon: "exclamationmark.triangle.fill", isSyncing: isSyncingOps(damageRecordSync.syncStatus))
                }
                .disabled(isSyncingOps(damageRecordSync.syncStatus))
                VineyardSyncStatusRow(label: "damage records", state: opsStateFrom(damageRecordSync.syncStatus, lastSync: damageRecordSync.lastSyncDate))

                Button {
                    Task { await historicalYieldSync.syncForSelectedVineyard() }
                } label: {
                    syncButtonLabel(title: "Sync Historical Yields", icon: "calendar.badge.clock", isSyncing: isSyncingOps(historicalYieldSync.syncStatus))
                }
                .disabled(isSyncingOps(historicalYieldSync.syncStatus))
                VineyardSyncStatusRow(label: "historical yields", state: opsStateFrom(historicalYieldSync.syncStatus, lastSync: historicalYieldSync.lastSyncDate))
            } header: {
                Text("Operations")
            } footer: {
                Text("Work tasks, maintenance logs, yield sessions, damage records and historical yields sync across vineyard members.")
            }

            Section {
                Button {
                    Task { await growthStageImageSync.syncForSelectedVineyard() }
                } label: {
                    syncButtonLabel(title: "Sync Growth Stage Images", icon: "photo.on.rectangle", isSyncing: isSyncingMgmt(growthStageImageSync.syncStatus))
                }
                .disabled(isSyncingMgmt(growthStageImageSync.syncStatus))
                VineyardSyncStatusRow(label: "E-L stage images", state: mgmtStateFrom(growthStageImageSync.syncStatus, lastSync: growthStageImageSync.lastSyncDate))
            } header: {
                Text("Reference Images")
            } footer: {
                Text("Custom E-L growth stage reference images are shared with all vineyard members. Pin photos sync automatically with each pin.")
            }
        }
        .navigationTitle("Sync")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func syncButtonLabel(title: String, icon: String, isSyncing: Bool) -> some View {
        HStack {
            Label(title, systemImage: icon)
                .foregroundStyle(.primary)
            Spacer()
            if isSyncing { ProgressView() }
        }
    }

    private func isSyncing(_ status: PinSyncService.Status) -> Bool { if case .syncing = status { return true }; return false }
    private func isSyncing(_ status: PaddockSyncService.Status) -> Bool { if case .syncing = status { return true }; return false }
    private func isSyncing(_ status: TripSyncService.Status) -> Bool { if case .syncing = status { return true }; return false }
    private func isSyncing(_ status: SprayRecordSyncService.Status) -> Bool { if case .syncing = status { return true }; return false }
    private func isSyncing(_ status: ButtonConfigSyncService.Status) -> Bool { if case .syncing = status { return true }; return false }

    private func pinStateFrom(_ status: PinSyncService.Status, lastSync: Date?) -> VineyardSyncState {
        switch status {
        case .idle: return .idle
        case .syncing: return .syncing
        case .success: return .success(lastSync)
        case .failure(let m): return .failure(m)
        }
    }
    private func tripStateFrom(_ status: TripSyncService.Status, lastSync: Date?) -> VineyardSyncState {
        switch status {
        case .idle: return .idle
        case .syncing: return .syncing
        case .success: return .success(lastSync)
        case .failure(let m): return .failure(m)
        }
    }
    private func paddockStateFrom(_ status: PaddockSyncService.Status, lastSync: Date?) -> VineyardSyncState {
        switch status {
        case .idle: return .idle
        case .syncing: return .syncing
        case .success: return .success(lastSync)
        case .failure(let m): return .failure(m)
        }
    }
    private func sprayStateFrom(_ status: SprayRecordSyncService.Status, lastSync: Date?) -> VineyardSyncState {
        switch status {
        case .idle: return .idle
        case .syncing: return .syncing
        case .success: return .success(lastSync)
        case .failure(let m): return .failure(m)
        }
    }
    private func buttonConfigStateFrom(_ status: ButtonConfigSyncService.Status, lastSync: Date?) -> VineyardSyncState {
        switch status {
        case .idle: return .idle
        case .syncing: return .syncing
        case .success: return .success(lastSync)
        case .failure(let m): return .failure(m)
        }
    }

    private func isSyncingMgmt(_ status: ManagementSyncStatus) -> Bool {
        if case .syncing = status { return true }
        return false
    }

    private func mgmtStateFrom(_ status: ManagementSyncStatus, lastSync: Date?) -> VineyardSyncState {
        switch status {
        case .idle: return .idle
        case .syncing: return .syncing
        case .success: return .success(lastSync)
        case .failure(let m): return .failure(m)
        }
    }

    private func isSyncingOps(_ status: OperationsSyncStatus) -> Bool {
        if case .syncing = status { return true }
        return false
    }

    private func opsStateFrom(_ status: OperationsSyncStatus, lastSync: Date?) -> VineyardSyncState {
        switch status {
        case .idle: return .idle
        case .syncing: return .syncing
        case .success: return .success(lastSync)
        case .failure(let m): return .failure(m)
        }
    }
}
