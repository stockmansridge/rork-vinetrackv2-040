import SwiftUI
import CoreLocation

struct NewMainTabView: View {
    @Environment(NewBackendAuthService.self) private var auth
    @Environment(MigratedDataStore.self) private var store
    @Environment(LocationService.self) private var locationService
    @Environment(BackendAccessControl.self) private var accessControl
    @Environment(TripTrackingService.self) private var tripTracking
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
    @Environment(MaintenanceLogSyncService.self) private var maintenanceLogSync
    @Environment(YieldEstimationSessionSyncService.self) private var yieldSessionSync
    @Environment(DamageRecordSyncService.self) private var damageRecordSync
    @Environment(HistoricalYieldRecordSyncService.self) private var historicalYieldSync
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            NewHomeTabView(selectedTab: $selectedTab)
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(0)

            NavigationStack {
                PinsView()
            }
            .tabItem { Label("Pins", systemImage: "mappin.and.ellipse") }
            .tag(1)

            TripView()
                .tabItem { Label("Trip", systemImage: "steeringwheel") }
                .tag(2)

            NavigationStack {
                SprayProgramView()
            }
            .tabItem { Label("Program", systemImage: "sprinkler.and.droplets.fill") }
            .tag(3)

            BackendSettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(4)
        }
        .environment(\.accessControl, accessControl.legacyAccessControl)
        .onAppear {
            if locationService.authorizationStatus == .notDetermined {
                locationService.requestPermission()
            } else if locationService.authorizationStatus == .authorizedWhenInUse || locationService.authorizationStatus == .authorizedAlways {
                locationService.startUpdating()
            }
            tripTracking.configure(store: store, locationService: locationService)
            pinSync.configure(store: store, auth: auth)
            paddockSync.configure(store: store, auth: auth)
            tripSync.configure(store: store, auth: auth)
            sprayRecordSync.configure(store: store, auth: auth)
            buttonConfigSync.configure(store: store, auth: auth)
            savedChemicalSync.configure(store: store, auth: auth)
            savedSprayPresetSync.configure(store: store, auth: auth)
            sprayEquipmentSync.configure(store: store, auth: auth)
            tractorSync.configure(store: store, auth: auth)
            fuelPurchaseSync.configure(store: store, auth: auth)
            operatorCategorySync.configure(store: store, auth: auth)
            growthStageImageSync.configure(store: store, auth: auth)
            workTaskSync.configure(store: store, auth: auth)
            maintenanceLogSync.configure(store: store, auth: auth)
            yieldSessionSync.configure(store: store, auth: auth)
            damageRecordSync.configure(store: store, auth: auth)
            historicalYieldSync.configure(store: store, auth: auth)
        }
        .task(id: store.selectedVineyardId) {
            await accessControl.refresh(for: store.selectedVineyardId, auth: auth)
            await pinSync.syncPinsForSelectedVineyard()
            await paddockSync.syncPaddocksForSelectedVineyard()
            await tripSync.syncTripsForSelectedVineyard()
            await sprayRecordSync.syncSprayRecordsForSelectedVineyard()
            await buttonConfigSync.syncButtonConfigForSelectedVineyard()
            await savedChemicalSync.syncForSelectedVineyard()
            await savedSprayPresetSync.syncForSelectedVineyard()
            await sprayEquipmentSync.syncForSelectedVineyard()
            await tractorSync.syncForSelectedVineyard()
            await fuelPurchaseSync.syncForSelectedVineyard()
            await operatorCategorySync.syncForSelectedVineyard()
            await growthStageImageSync.syncForSelectedVineyard()
            await workTaskSync.syncForSelectedVineyard()
            await maintenanceLogSync.syncForSelectedVineyard()
            await yieldSessionSync.syncForSelectedVineyard()
            await damageRecordSync.syncForSelectedVineyard()
            await historicalYieldSync.syncForSelectedVineyard()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task {
                    await pinSync.syncPinsForSelectedVineyard()
                    await paddockSync.syncPaddocksForSelectedVineyard()
                    await tripSync.syncTripsForSelectedVineyard()
                    await sprayRecordSync.syncSprayRecordsForSelectedVineyard()
                    await buttonConfigSync.syncButtonConfigForSelectedVineyard()
                    await savedChemicalSync.syncForSelectedVineyard()
                    await savedSprayPresetSync.syncForSelectedVineyard()
                    await sprayEquipmentSync.syncForSelectedVineyard()
                    await tractorSync.syncForSelectedVineyard()
                    await fuelPurchaseSync.syncForSelectedVineyard()
                    await operatorCategorySync.syncForSelectedVineyard()
                    await growthStageImageSync.syncForSelectedVineyard()
                    await workTaskSync.syncForSelectedVineyard()
                    await maintenanceLogSync.syncForSelectedVineyard()
                    await yieldSessionSync.syncForSelectedVineyard()
                    await damageRecordSync.syncForSelectedVineyard()
                    await historicalYieldSync.syncForSelectedVineyard()
                }
            }
        }
    }
}

// MARK: - Home Tab

private struct NewHomeTabView: View {
    @Binding var selectedTab: Int
    @Environment(NewBackendAuthService.self) private var auth
    @Environment(MigratedDataStore.self) private var store
    @Environment(BackendAccessControl.self) private var accessControl
    @Environment(TripTrackingService.self) private var tripTracking

    @State private var showQuickPin: Bool = false
    @State private var showTripChoice: Bool = false
    @State private var showStartTrip: Bool = false
    @State private var showSpraySetup: Bool = false
    #if DEBUG
    @State private var showBackendDiagnostic: Bool = false
    @State private var showStoreDiagnostic: Bool = false
    #endif


    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    titleHeader
                    if tripTracking.activeTrip != nil {
                        Button {
                            selectedTab = 2
                        } label: {
                            ActiveTripCard()
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal)
                    }
                    todaySection
                    vineyardOverviewSection
                    if accessControl.canCreateOperationalRecords {
                        quickActionsSection
                    }
                    operationsSection
                    managementSection
                    summarySection
                    #if DEBUG
                    debugSection
                    #endif
                    Spacer(minLength: 24)
                }
                .padding(.vertical)
            }
            .background(VineyardTheme.appBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showQuickPin) {
                QuickPinSheet()
            }
            .sheet(isPresented: $showTripChoice) {
                TripTypeChoiceSheet { type in
                    showTripChoice = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        switch type {
                        case .maintenance:
                            showStartTrip = true
                        case .spray:
                            showSpraySetup = true
                        }
                    }
                }
            }
            .sheet(isPresented: $showStartTrip) {
                StartTripSheet()
            }
            .sheet(isPresented: $showSpraySetup) {
                SprayTripSetupSheet()
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

    // MARK: Header

    private var titleHeader: some View {
        HStack(spacing: 12) {
            if let data = store.selectedVineyard?.logoData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
            } else {
                ZStack {
                    Circle()
                        .fill(VineyardTheme.leafGreen.gradient)
                        .frame(width: 40, height: 40)
                    GrapeVineLeafShape()
                        .fill(.white)
                        .frame(width: 22, height: 22)
                }
            }
            Text(store.selectedVineyard?.name ?? "No Vineyard")
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
        .padding(.top, 4)
    }

    private func plainSectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.subheadline.weight(.semibold))
            .tracking(0.5)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
    }

    private func formattedNumber(_ value: Int) -> String {
        if value >= 1000 {
            let thousands = Double(value) / 1000.0
            if thousands >= 10 {
                return "\(Int(thousands))k"
            }
            return String(format: "%.1fk", thousands)
        }
        return "\(value)"
    }

    private func formattedHectares(_ value: Double) -> String {
        if value >= 100 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }

    // MARK: Today

    private var pinsNeedingAttention: Int {
        store.pins.filter { !$0.isCompleted }.count
    }

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            plainSectionHeader("Today")
            NavigationLink {
                PinsView()
            } label: {
                VineyardCard {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.orange.opacity(0.15))
                                .frame(width: 48, height: 48)
                            Image(systemName: "mappin.and.ellipse")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.orange)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(pinsNeedingAttention) pin\(pinsNeedingAttention == 1 ? "" : "s") need attention")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text(pinsNeedingAttention == 0 ? "All caught up" : "Open the Pins tab to review")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
        }
    }

    // MARK: Vineyard Overview

    private var totalHectares: Double {
        store.paddocks.reduce(0.0) { $0 + $1.areaHectares }
    }

    private var totalVines: Int {
        store.paddocks.reduce(0) { $0 + $1.effectiveVineCount }
    }

    private var vineyardOverviewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            plainSectionHeader("Vineyard Overview")
            NavigationLink {
                VineyardDetailsView()
            } label: {
                VineyardCard {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(VineyardTheme.leafGreen.opacity(0.15))
                                    .frame(width: 48, height: 48)
                                if let data = store.selectedVineyard?.logoData, let uiImage = UIImage(data: data) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 48, height: 48)
                                        .clipShape(.rect(cornerRadius: 12))
                                } else {
                                    Image(systemName: "map.fill")
                                        .font(.title3.weight(.semibold))
                                        .foregroundStyle(VineyardTheme.leafGreen)
                                }
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(store.selectedVineyard?.name ?? "No vineyard selected")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text("View map & summary")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        Divider()
                        HStack(spacing: 0) {
                            overviewStat(icon: "square.grid.2x2.fill", iconColor: VineyardTheme.leafGreen, value: "\(store.paddocks.count)", label: "Blocks")
                            Divider().frame(height: 44)
                            overviewStat(icon: "square.dashed", iconColor: .orange, value: formattedHectares(totalHectares), label: "Hectares")
                            Divider().frame(height: 44)
                            overviewStatCustom(value: formattedNumber(totalVines), label: "Vines") {
                                GrapeLeafIcon(size: 14, color: VineyardTheme.darkGreen)
                            }
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
        }
    }

    private func overviewStatCustom<Icon: View>(value: String, label: String, @ViewBuilder icon: () -> Icon) -> some View {
        VStack(spacing: 4) {
            icon()
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func overviewStat(icon: String, iconColor: Color, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(iconColor)
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Quick Actions

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            plainSectionHeader("Quick Actions")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                NavigationLink {
                    RepairsGrowthView(initial: .repairs)
                } label: {
                    quickActionTileLabel(title: "Repairs", systemIcon: "wrench.fill", colors: [.orange, Color.orange.opacity(0.75)])
                }
                .buttonStyle(.plain)
                NavigationLink {
                    RepairsGrowthView(initial: .growth)
                } label: {
                    quickActionTileLabel(title: "Growth", grapeLeaf: true, colors: [VineyardTheme.leafGreen, VineyardTheme.darkGreen])
                }
                .buttonStyle(.plain)
                Button {
                    showTripChoice = true
                } label: {
                    quickActionTileLabel(title: "Start Trip", systemIcon: "steeringwheel", colors: [.blue, Color.blue.opacity(0.75)])
                }
                .buttonStyle(.plain)
                NavigationLink {
                    SprayProgramView()
                } label: {
                    quickActionTileLabel(title: "Spray Program", systemIcon: "sprinkler.and.droplets.fill", colors: [.purple, Color.purple.opacity(0.75)])
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
        }
    }

    private func quickActionTileLabel(title: String, systemIcon: String? = nil, grapeLeaf: Bool = false, colors: [Color]) -> some View {
        VStack(spacing: 8) {
            Group {
                if grapeLeaf {
                    GrapeLeafIcon(size: 24, color: .white)
                } else if let systemIcon {
                    Image(systemName: systemIcon)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, minHeight: 76)
        .padding(12)
        .background(
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
            in: .rect(cornerRadius: 14)
        )
        .shadow(color: colors.first?.opacity(0.25) ?? .clear, radius: 4, y: 2)
    }

    // MARK: Operational Tools

    private var operationsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            plainSectionHeader("Operational Tools")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                NavigationLink {
                    WorkTasksHubView()
                } label: {
                    iconTile(title: "Work Tasks", icon: "person.2.badge.gearshape.fill", tint: .indigo)
                }
                .buttonStyle(.plain)
                NavigationLink {
                    MaintenanceLogListView()
                } label: {
                    iconTile(title: "Maintenance Log", icon: "wrench.and.screwdriver.fill", tint: VineyardTheme.earthBrown)
                }
                .buttonStyle(.plain)
                NavigationLink {
                    GrowthStageReportView()
                } label: {
                    iconTile(title: "Growth Stage Report", icon: "chart.line.uptrend.xyaxis", tint: VineyardTheme.leafGreen)
                }
                .buttonStyle(.plain)
                NavigationLink {
                    YieldHubView()
                } label: {
                    iconTile(title: "Yield Estimation", icon: "chart.bar.fill", tint: .orange)
                }
                .buttonStyle(.plain)
                NavigationLink {
                    IrrigationRecommendationView()
                } label: {
                    iconTile(title: "Irrigation Advisor", icon: "drop.fill", tint: .cyan)
                }
                .buttonStyle(.plain)
                NavigationLink {
                    YieldHubView()
                } label: {
                    iconTile(title: "Yield Determination", icon: "scalemass.fill", tint: .purple)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
        }
    }

    private func iconTile(title: String, icon: String, tint: Color) -> some View {
        operationalTile(title: title, subtitle: subtitleFor(title), icon: icon, tint: tint)
    }

    private func subtitleFor(_ title: String) -> String {
        switch title {
        case "Work Tasks": return "Log & calculate"
        case "Maintenance Log": return "Repairs & jobs"
        case "Growth Stage Report": return "E-L tracking"
        case "Yield Estimation": return "Forecast crop"
        case "Irrigation Advisor": return "Water planning"
        case "Yield Determination": return "Final weights"
        case "Manage Users": return "Team & roles"
        case "Vineyard Setup": return "Blocks & rows"
        case "Audit Log": return "Activity history"
        case "Full Overview": return "All metrics"
        default: return ""
        }
    }

    private func operationalTile(title: String, subtitle: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(tint.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
        .padding(14)
        .background(VineyardTheme.cardBackground, in: .rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(VineyardTheme.cardBorder, lineWidth: 0.5)
        )
    }

    // MARK: Management

    @ViewBuilder
    private var managementSection: some View {
        if accessControl.canChangeSettings {
            VStack(alignment: .leading, spacing: 10) {
                plainSectionHeader("Management")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    if let vineyard = store.selectedVineyard {
                        NavigationLink {
                            BackendTeamAccessView(vineyardId: vineyard.id, vineyardName: vineyard.name)
                        } label: {
                            iconTile(title: "Manage Users", icon: "person.2.fill", tint: .blue)
                        }
                        .buttonStyle(.plain)
                    }
                    NavigationLink {
                        BlocksHubView()
                    } label: {
                        iconTile(title: "Vineyard Setup", icon: "gearshape.2.fill", tint: .gray)
                    }
                    .buttonStyle(.plain)
                    NavigationLink {
                        OperationsHubView()
                    } label: {
                        iconTile(title: "Audit Log", icon: "doc.text.magnifyingglass", tint: .pink)
                    }
                    .buttonStyle(.plain)
                    NavigationLink {
                        OperationsHubView()
                    } label: {
                        iconTile(title: "Full Overview", icon: "chart.pie.fill", tint: VineyardTheme.leafGreen)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: Summary

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            plainSectionHeader("Recent")

            VineyardCard {
                VStack(spacing: 10) {
                    summaryRow("Pins", value: store.pins.count, icon: "mappin.circle.fill", tint: .red)
                    Divider()
                    summaryRow("Trips", value: store.trips.count, icon: "map.fill", tint: .blue)
                    Divider()
                    summaryRow("Spray records", value: store.sprayRecords.count, icon: "sprinkler.and.droplets.fill", tint: .purple)
                    Divider()
                    summaryRow("Paddocks", value: store.paddocks.count, icon: "square.grid.2x2.fill", tint: VineyardTheme.leafGreen)
                }
            }
            .padding(.horizontal)
        }
    }

    private func summaryRow(_ label: String, value: Int, icon: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 22)
            Text(label)
                .foregroundStyle(VineyardTheme.textPrimary)
            Spacer()
            Text("\(value)")
                .font(.body.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private func hubRow(title: String, subtitle: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(tint.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(VineyardTheme.textPrimary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    #if DEBUG
    private var debugSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            plainSectionHeader("Debug")
            VineyardCard(padding: 0) {
                VStack(spacing: 0) {
                    Button {
                        showBackendDiagnostic = true
                    } label: {
                        hubRow(title: "Backend Diagnostic", subtitle: "Inspect Supabase state", icon: "stethoscope", tint: .gray)
                    }
                    .buttonStyle(.plain)
                    Divider().padding(.leading, 60)
                    Button {
                        showStoreDiagnostic = true
                    } label: {
                        hubRow(title: "MigratedDataStore", subtitle: "Local storage", icon: "tray.full", tint: .gray)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }
    #endif
}
