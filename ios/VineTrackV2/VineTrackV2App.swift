//
//  VineTrackV2App.swift
//  VineTrackV2
//
//  Created by Rork on April 27, 2026.
//

import SwiftUI
import SwiftData

@main
struct VineTrackV2App: App {
    @State private var auth = NewBackendAuthService()
    @State private var migratedStore = MigratedDataStore()
    @State private var locationService = LocationService()
    @State private var degreeDayService = DegreeDayService()
    @State private var backendAccessControl = BackendAccessControl()
    @State private var tripTrackingService = TripTrackingService()
    @State private var pinSyncService = PinSyncService()
    @State private var paddockSyncService = PaddockSyncService()
    @State private var tripSyncService = TripSyncService()
    @State private var sprayRecordSyncService = SprayRecordSyncService()
    @State private var buttonConfigSyncService = ButtonConfigSyncService()
    @State private var savedChemicalSyncService = SavedChemicalSyncService()
    @State private var savedSprayPresetSyncService = SavedSprayPresetSyncService()
    @State private var sprayEquipmentSyncService = SprayEquipmentSyncService()
    @State private var tractorSyncService = TractorSyncService()
    @State private var fuelPurchaseSyncService = FuelPurchaseSyncService()
    @State private var operatorCategorySyncService = OperatorCategorySyncService()
    @State private var growthStageImageSyncService = GrowthStageImageSyncService()
    @State private var workTaskSyncService = WorkTaskSyncService()
    @State private var maintenanceLogSyncService = MaintenanceLogSyncService()
    @State private var yieldEstimationSessionSyncService = YieldEstimationSessionSyncService()
    @State private var damageRecordSyncService = DamageRecordSyncService()
    @State private var historicalYieldRecordSyncService = HistoricalYieldRecordSyncService()
    @State private var subscriptionService = SubscriptionService()

    init() {
        VineyardTheme.applyGlobalAppearance()
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([Item.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            Group {
                if AppFeatureFlags.useNewBackendShell {
                    NewBackendRootView()
                        .environment(auth)
                        .environment(migratedStore)
                        .environment(locationService)
                        .environment(degreeDayService)
                        .environment(backendAccessControl)
                        .environment(tripTrackingService)
                        .environment(pinSyncService)
                        .environment(paddockSyncService)
                        .environment(tripSyncService)
                        .environment(sprayRecordSyncService)
                        .environment(buttonConfigSyncService)
                        .environment(savedChemicalSyncService)
                        .environment(savedSprayPresetSyncService)
                        .environment(sprayEquipmentSyncService)
                        .environment(tractorSyncService)
                        .environment(fuelPurchaseSyncService)
                        .environment(operatorCategorySyncService)
                        .environment(growthStageImageSyncService)
                        .environment(workTaskSyncService)
                        .environment(maintenanceLogSyncService)
                        .environment(yieldEstimationSessionSyncService)
                        .environment(damageRecordSyncService)
                        .environment(historicalYieldRecordSyncService)
                        .environment(subscriptionService)
                } else {
                    ContentView()
                }
            }
            .tint(VineyardTheme.olive)
            .preferredColorScheme(migratedStore.settings.appearance.colorScheme)
        }
        .modelContainer(sharedModelContainer)
    }
}
