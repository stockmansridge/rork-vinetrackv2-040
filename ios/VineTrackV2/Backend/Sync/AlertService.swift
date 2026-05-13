import Foundation
import Observation
import CoreLocation

/// Service responsible for generating, fetching, and updating vineyard alerts.
/// Generation runs locally based on the in-memory data store; the resulting
/// alerts are upserted to Supabase (deduplicated via dedup_key) so they sync
/// across devices and members. Per-user read/dismiss is tracked separately.
@Observable
@MainActor
final class AlertService {

    enum Status: Equatable, Sendable {
        case idle
        case loading
        case success
        case failure(String)
    }

    var status: Status = .idle
    var alerts: [AlertWithStatus] = []
    var preferences: BackendAlertPreferences?
    var lastRefresh: Date?
    /// Deep-link request from a tapped alert. Observed by the main tab view
    /// to switch tabs / present the relevant screen, then cleared.
    var pendingNavigation: AlertAction?

    private weak var store: MigratedDataStore?
    private weak var auth: NewBackendAuthService?
    private let repository: any AlertRepositoryProtocol
    private let forecastService: IrrigationForecastService
    private let hourlyService: WeatherHourlyService

    init(repository: (any AlertRepositoryProtocol)? = nil) {
        self.repository = repository ?? SupabaseAlertRepository()
        self.forecastService = IrrigationForecastService()
        self.hourlyService = WeatherHourlyService()
    }

    func configure(store: MigratedDataStore, auth: NewBackendAuthService) {
        self.store = store
        self.auth = auth
    }

    // MARK: - Derived

    var activeAlerts: [AlertWithStatus] {
        alerts.filter { !$0.isDismissed && !isExpired($0.alert) }
    }

    var unreadAlerts: [AlertWithStatus] {
        activeAlerts.filter { !$0.isRead }
    }

    var highestSeverity: AlertSeverity? {
        let severities = activeAlerts.map { $0.alert.typedSeverity }
        if severities.contains(.critical) { return .critical }
        if severities.contains(.warning) { return .warning }
        if severities.contains(.info) { return .info }
        return nil
    }

    private func isExpired(_ alert: BackendAlert) -> Bool {
        guard let exp = alert.expiresAt else { return false }
        return exp < Date()
    }

    // MARK: - Refresh

    /// Fetch alerts and preferences for the currently selected vineyard.
    /// Non-blocking; failures are surfaced via `status` but never thrown.
    func refresh() async {
        guard let store, let auth, auth.isSignedIn,
              let vineyardId = store.selectedVineyardId,
              SupabaseClientProvider.shared.isConfigured else {
            return
        }
        status = .loading
        do {
            let prefs: BackendAlertPreferences
            if let existing = try await repository.fetchPreferences(vineyardId: vineyardId) {
                prefs = existing
            } else {
                prefs = BackendAlertPreferences.defaults(for: vineyardId)
            }
            self.preferences = prefs

            let fetched = try await repository.fetchAlerts(vineyardId: vineyardId)
            let statuses = try await repository.fetchUserStatus(alertIds: fetched.map { $0.id })
            let statusByAlert = Dictionary(uniqueKeysWithValues: statuses.map { ($0.alertId, $0) })
            self.alerts = fetched.map { AlertWithStatus(alert: $0, status: statusByAlert[$0.id]) }
            self.lastRefresh = Date()
            self.status = .success
        } catch {
            self.status = .failure(error.localizedDescription)
        }
    }

    /// Run local alert generation for the selected vineyard, push generated
    /// alerts (deduped by dedup_key), then refresh from server.
    func generateAndRefresh() async {
        guard let store, let auth, auth.isSignedIn,
              let vineyardId = store.selectedVineyardId,
              SupabaseClientProvider.shared.isConfigured else {
            print("[AlertService] generateAndRefresh skipped — not signed in / no vineyard / supabase unconfigured")
            return
        }

        // Make sure we have preferences first.
        if preferences == nil {
            preferences = (try? await repository.fetchPreferences(vineyardId: vineyardId))
                ?? BackendAlertPreferences.defaults(for: vineyardId)
        }
        let prefs = preferences ?? BackendAlertPreferences.defaults(for: vineyardId)
        let userId = auth.userId

        print("[AlertService] generateAndRefresh vineyard=\(vineyardId.uuidString.prefix(8)) prefs: agedPins=\(prefs.agedPinAlertsEnabled)(>=\(prefs.agedPinDays)d) irrigation=\(prefs.irrigationAlertsEnabled)(\(prefs.irrigationDeficitThresholdMm)mm) weather=\(prefs.weatherAlertsEnabled)(rain\(prefs.rainAlertThresholdMm)/wind\(prefs.windAlertThresholdKmh)/frost\(prefs.frostAlertThresholdC)/heat\(prefs.heatAlertThresholdC)) spray=\(prefs.sprayJobRemindersEnabled) disease=\(prefs.diseaseAlertsEnabled)")

        var generated: [BackendAlertUpsert] = []
        var bySource: [String: Int] = [:]

        if prefs.agedPinAlertsEnabled {
            let items = generateAgedPinAlerts(
                store: store,
                vineyardId: vineyardId,
                prefs: prefs,
                userId: userId
            )
            bySource["agedPins"] = items.count
            generated.append(contentsOf: items)
        }
        if prefs.sprayJobRemindersEnabled {
            let items = generateSprayReminders(
                store: store,
                vineyardId: vineyardId,
                userId: userId
            )
            bySource["spray"] = items.count
            generated.append(contentsOf: items)
        }
        if prefs.irrigationAlertsEnabled {
            let items = await generateIrrigationAlerts(
                store: store,
                vineyardId: vineyardId,
                prefs: prefs,
                userId: userId
            )
            bySource["irrigation"] = items.count
            generated.append(contentsOf: items)
        } else if prefs.weatherAlertsEnabled {
            // Ensure we have a forecast even if irrigation alerts are disabled.
            await ensureForecast(store: store, vineyardId: vineyardId, prefs: prefs)
        }

        if prefs.weatherAlertsEnabled {
            let weather = generateWeatherAlertsFromForecast(
                forecastDays: forecastService.forecast?.days ?? [],
                vineyardId: vineyardId,
                prefs: prefs,
                userId: userId
            )
            bySource["weather"] = weather.count
            generated.append(contentsOf: weather)
            let rain = await generateRainAlertsFromDavis(
                store: store,
                vineyardId: vineyardId,
                userId: userId
            )
            bySource["rainDavis"] = rain.count
            generated.append(contentsOf: rain)
        }

        if prefs.diseaseAlertsEnabled {
            let items = await generateDiseaseAlerts(
                store: store,
                vineyardId: vineyardId,
                prefs: prefs,
                userId: userId
            )
            bySource["disease"] = items.count
            generated.append(contentsOf: items)
        }

        print("[AlertService] generated=\(generated.count) bySource=\(bySource)")

        if !generated.isEmpty {
            do {
                try await repository.upsertAlerts(generated)
                print("[AlertService] upserted \(generated.count) alerts to Supabase")
            } catch {
                print("[AlertService] upsert failed — \(error.localizedDescription)")
            }
        }

        await refresh()
        print("[AlertService] post-refresh fetched=\(alerts.count) active=\(activeAlerts.count) unread=\(unreadAlerts.count)")
    }

    // MARK: - Aged pins

    private func generateAgedPinAlerts(
        store: MigratedDataStore,
        vineyardId: UUID,
        prefs: BackendAlertPreferences,
        userId: UUID?
    ) -> [BackendAlertUpsert] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -prefs.agedPinDays, to: Date()) ?? Date()
        let aged = store.pins.filter {
            $0.vineyardId == vineyardId && !$0.isCompleted && $0.timestamp <= cutoff
        }
        guard !aged.isEmpty else { return [] }
        let count = aged.count
        let dedupKey = "aged_pins:\(prefs.agedPinDays)"
        let title = "\(count) aged pin\(count == 1 ? "" : "s")"
        let message = "\(count) unresolved pin\(count == 1 ? "" : "s") older than \(prefs.agedPinDays) days. Tap to review."
        let severity: AlertSeverity = count >= 10 ? .warning : .info
        let alertId = deterministicUUID(vineyardId: vineyardId, dedupKey: dedupKey)
        return [
            BackendAlertUpsert(
                id: alertId,
                vineyardId: vineyardId,
                alertType: AlertType.agedPins.rawValue,
                severity: severity.rawValue,
                title: title,
                message: message,
                relatedTable: "pins",
                relatedId: nil,
                paddockId: nil,
                action: AlertAction.openPins.rawValue,
                dedupKey: dedupKey,
                generatedForDate: today(),
                expiresAt: tomorrow(),
                createdBy: userId
            )
        ]
    }

    // MARK: - Spray reminders

    private func generateSprayReminders(
        store: MigratedDataStore,
        vineyardId: UUID,
        userId: UUID?
    ) -> [BackendAlertUpsert] {
        let cal = Calendar.current
        let now = Date()
        let tomorrowEnd = cal.date(byAdding: .day, value: 2, to: cal.startOfDay(for: now)) ?? now
        let recordsDue = store.sprayRecords.filter {
            $0.vineyardId == vineyardId && $0.date >= cal.startOfDay(for: now) && $0.date < tomorrowEnd
        }
        guard !recordsDue.isEmpty else { return [] }
        let count = recordsDue.count
        let dedupKey = "spray_due:\(yyyymmdd(now))"
        let title = "\(count) spray job\(count == 1 ? "" : "s") due"
        let message = "Scheduled spray work today or tomorrow. Tap to review the spray program."
        let alertId = deterministicUUID(vineyardId: vineyardId, dedupKey: dedupKey)
        return [
            BackendAlertUpsert(
                id: alertId,
                vineyardId: vineyardId,
                alertType: AlertType.sprayJobDue.rawValue,
                severity: AlertSeverity.warning.rawValue,
                title: title,
                message: message,
                relatedTable: "spray_records",
                relatedId: nil,
                paddockId: nil,
                action: AlertAction.openSprayProgram.rawValue,
                dedupKey: dedupKey,
                generatedForDate: today(),
                expiresAt: cal.date(byAdding: .day, value: 2, to: now),
                createdBy: userId
            )
        ]
    }

    // MARK: - Irrigation

    private func ensureForecast(
        store: MigratedDataStore,
        vineyardId: UUID,
        prefs: BackendAlertPreferences
    ) async {
        let paddocks = store.paddocks.filter { $0.vineyardId == vineyardId && !$0.polygonPoints.isEmpty }
        guard let firstPaddock = paddocks.first else { return }
        let lat = firstPaddock.polygonPoints.map(\.latitude).reduce(0, +) / Double(firstPaddock.polygonPoints.count)
        let lon = firstPaddock.polygonPoints.map(\.longitude).reduce(0, +) / Double(firstPaddock.polygonPoints.count)
        await forecastService.fetchForecast(latitude: lat, longitude: lon, days: prefs.irrigationForecastDays)
    }

    private func generateIrrigationAlerts(
        store: MigratedDataStore,
        vineyardId: UUID,
        prefs: BackendAlertPreferences,
        userId: UUID?
    ) async -> [BackendAlertUpsert] {
        // Use first paddock with a valid centroid as a proxy location.
        let paddocks = store.paddocks.filter { $0.vineyardId == vineyardId && !$0.polygonPoints.isEmpty }
        guard let firstPaddock = paddocks.first else { return [] }
        let lat = firstPaddock.polygonPoints.map(\.latitude).reduce(0, +) / Double(firstPaddock.polygonPoints.count)
        let lon = firstPaddock.polygonPoints.map(\.longitude).reduce(0, +) / Double(firstPaddock.polygonPoints.count)

        await forecastService.fetchForecast(latitude: lat, longitude: lon, days: prefs.irrigationForecastDays)
        guard let forecast = forecastService.forecast, !forecast.days.isEmpty else { return [] }

        let result = IrrigationCalculator.calculate(
            forecastDays: forecast.days,
            settings: IrrigationSettings.defaults
        )
        let deficit = result?.netDeficitMm ?? 0
        guard deficit >= prefs.irrigationDeficitThresholdMm else { return [] }

        let dedupKey = "irrigation_deficit:\(yyyymmdd(Date()))"
        let title = "Irrigation may be needed"
        let message = String(format: "Forecast deficit %.1f mm over the next %d days exceeds your threshold (%.1f mm).",
                             deficit, prefs.irrigationForecastDays, prefs.irrigationDeficitThresholdMm)
        let severity: AlertSeverity = deficit >= prefs.irrigationDeficitThresholdMm * 2 ? .warning : .info
        let alertId = deterministicUUID(vineyardId: vineyardId, dedupKey: dedupKey)
        return [
            BackendAlertUpsert(
                id: alertId,
                vineyardId: vineyardId,
                alertType: AlertType.irrigationNeeded.rawValue,
                severity: severity.rawValue,
                title: title,
                message: message,
                relatedTable: nil,
                relatedId: nil,
                paddockId: firstPaddock.id,
                action: AlertAction.openIrrigationAdvisor.rawValue,
                dedupKey: dedupKey,
                generatedForDate: today(),
                expiresAt: Calendar.current.date(byAdding: .day, value: 1, to: Date()),
                createdBy: userId
            )
        ]
    }

    // MARK: - Weather

    private func generateWeatherAlertsFromForecast(
        forecastDays: [ForecastDay],
        vineyardId: UUID,
        prefs: BackendAlertPreferences,
        userId: UUID?
    ) -> [BackendAlertUpsert] {
        guard let firstDay = forecastDays.first else { return [] }
        let date = firstDay.date
        let dedupKey = "weather_risk:\(yyyymmdd(date))"

        var risks: [String] = []
        var severity: AlertSeverity = .info
        if firstDay.forecastRainMm >= prefs.rainAlertThresholdMm {
            risks.append(String(format: "rain %.1f mm", firstDay.forecastRainMm))
            if firstDay.forecastRainMm >= prefs.rainAlertThresholdMm * 2 {
                severity = .warning
            }
        }
        if let wind = firstDay.forecastWindKmhMax, wind >= prefs.windAlertThresholdKmh {
            risks.append(String(format: "wind %.0f km/h", wind))
            if wind >= prefs.windAlertThresholdKmh * 1.5 {
                severity = max(severity, .warning)
            }
        }
        if let tMin = firstDay.forecastTempMinC, tMin <= prefs.frostAlertThresholdC {
            risks.append(String(format: "frost low %.1f°C", tMin))
            severity = .critical
        }
        if let tMax = firstDay.forecastTempMaxC, tMax >= prefs.heatAlertThresholdC {
            risks.append(String(format: "heat %.1f°C", tMax))
            if tMax >= prefs.heatAlertThresholdC + 5 {
                severity = max(severity, .warning)
            }
        }
        guard !risks.isEmpty else { return [] }

        let title = "Weather risk forecast"
        let message = "Forecast for \(date.formatted(date: .abbreviated, time: .omitted)): " + risks.joined(separator: ", ") + "."
        let alertId = deterministicUUID(vineyardId: vineyardId, dedupKey: dedupKey)
        return [
            BackendAlertUpsert(
                id: alertId,
                vineyardId: vineyardId,
                alertType: AlertType.weatherRisk.rawValue,
                severity: severity.rawValue,
                title: title,
                message: message,
                relatedTable: nil,
                relatedId: nil,
                paddockId: nil,
                action: AlertAction.openWeather.rawValue,
                dedupKey: dedupKey,
                generatedForDate: date,
                expiresAt: Calendar.current.date(byAdding: .day, value: 1, to: date),
                createdBy: userId
            )
        ]
    }

    // MARK: - Rain alerts (Davis cached current)

    /// Phase 1 (iOS-only) rain alerts driven by the Davis cached current
    /// observation returned by `get_vineyard_current_weather`.
    ///
    /// Two alert types are generated, both deduplicated by `dedup_key`
    /// so repeated refreshes do not create duplicates:
    ///
    /// 1. `rain_started` — fires when `rain_rate_mm_per_hr > 0` and the
    ///    cache is fresh. Dedupe key uses a vineyard-local 3-hour bucket
    ///    (`rain_started:{yyyy-MM-dd}:{0-7}`) so a new alert can only be
    ///    created once every 3 hours per vineyard. Severity is
    ///    `warning` when rate ≥ 5 mm/hr, otherwise `info`. Auto-expires
    ///    after 6 hours.
    ///
    /// 2. `rain_24h_summary` — only created during the 09:00 hour in
    ///    vineyard-local time and only if rainfall in the past 24h is
    ///    > 0 mm. Past-24h rainfall is read via the davis-proxy historic
    ///    endpoint. One alert per vineyard per local date.
    ///
    /// Stale / unavailable / not-configured cache responses skip the
    /// `rain_started` branch quietly.
    private func generateRainAlertsFromDavis(
        store: MigratedDataStore,
        vineyardId: UUID,
        userId: UUID?
    ) async -> [BackendAlertUpsert] {
        let service = WeatherCurrentService()
        let cached: WeatherCurrentService.CachedSnapshot?
        do {
            cached = try await service.fetchCachedCurrent(vineyardId: vineyardId)
        } catch {
            print("[AlertService] rain alerts: fetchCachedCurrent failed — \(error.localizedDescription)")
            return []
        }

        let timezone = vineyardTimeZone(store: store, vineyardId: vineyardId)
        var localCal = Calendar(identifier: .gregorian)
        localCal.timeZone = timezone
        let now = Date()
        let localComps = localCal.dateComponents([.year, .month, .day, .hour], from: now)
        let localDate = String(
            format: "%04d-%02d-%02d",
            localComps.year ?? 0,
            localComps.month ?? 0,
            localComps.day ?? 0
        )
        let stationLabel: String = {
            if let name = cached?.stationName, !name.isEmpty { return name }
            if let v = store.vineyards.first(where: { $0.id == vineyardId }), !v.name.isEmpty {
                return v.name
            }
            return "the vineyard"
        }()

        var upserts: [BackendAlertUpsert] = []

        // 1. Rain started — only when cache is ok + fresh.
        if let snap = cached,
           snap.status == "ok",
           snap.isStale == false,
           let rate = snap.rainRateMmPerHr,
           rate > 0 {
            let bucket = (localComps.hour ?? 0) / 3
            let dedupKey = "rain_started:\(localDate):\(bucket)"
            let severity: AlertSeverity = rate >= 5 ? .warning : .info
            let title = "Rain has started"
            let message = String(
                format: "Rain detected at %@. Current rate %.1f mm/hr.",
                stationLabel,
                rate
            )
            let alertId = deterministicUUID(vineyardId: vineyardId, dedupKey: dedupKey)
            let expires = localCal.date(byAdding: .hour, value: 6, to: now)
            upserts.append(BackendAlertUpsert(
                id: alertId,
                vineyardId: vineyardId,
                alertType: AlertType.rainStarted.rawValue,
                severity: severity.rawValue,
                title: title,
                message: message,
                relatedTable: nil,
                relatedId: nil,
                paddockId: nil,
                action: AlertAction.openWeather.rawValue,
                dedupKey: dedupKey,
                generatedForDate: localCal.startOfDay(for: now),
                expiresAt: expires,
                createdBy: userId
            ))
        }

        // 2. 9 AM rain summary — vineyard-local 09:00..09:59.
        if (localComps.hour ?? -1) == 9 {
            let stationId = cached?.stationId ?? ""
            var rainfallMm: Double? = nil
            if !stationId.isEmpty {
                let from = now.addingTimeInterval(-24 * 60 * 60)
                do {
                    let result = try await VineyardDavisProxyService.fetchHistoricRainfall(
                        vineyardId: vineyardId,
                        stationId: stationId,
                        from: from,
                        to: now
                    )
                    rainfallMm = result.totalMm
                } catch {
                    print("[AlertService] rain 24h summary: historic fetch failed — \(error.localizedDescription)")
                }
            }
            if let mm = rainfallMm, mm > 0 {
                let dedupKey = "rain_24h_summary:\(localDate)"
                let title = "Rainfall in past 24 hours"
                let message = String(
                    format: "%.1f mm of rain recorded at %@ in the past 24 hours.",
                    mm,
                    stationLabel
                )
                let alertId = deterministicUUID(vineyardId: vineyardId, dedupKey: dedupKey)
                // Keep the daily summary visible until the end of the
                // following local day so it doesn't disappear before
                // managers see it.
                let expires = localCal.date(
                    byAdding: .day,
                    value: 2,
                    to: localCal.startOfDay(for: now)
                )
                upserts.append(BackendAlertUpsert(
                    id: alertId,
                    vineyardId: vineyardId,
                    alertType: AlertType.rain24hSummary.rawValue,
                    severity: AlertSeverity.info.rawValue,
                    title: title,
                    message: message,
                    relatedTable: nil,
                    relatedId: nil,
                    paddockId: nil,
                    action: AlertAction.openWeather.rawValue,
                    dedupKey: dedupKey,
                    generatedForDate: localCal.startOfDay(for: now),
                    expiresAt: expires,
                    createdBy: userId
                ))
            }
        }

        return upserts
    }

    /// Phase 1 timezone resolution. `vineyards.timezone` doesn't exist
    /// in the backend yet, so we default Stockmans Ridge Wines to
    /// Australia/Sydney and fall back to the device timezone for any
    /// other vineyard. Phase 2 will add a server-side timezone column.
    private func vineyardTimeZone(store: MigratedDataStore, vineyardId: UUID) -> TimeZone {
        let name = store.vineyards.first(where: { $0.id == vineyardId })?.name ?? ""
        if name.localizedCaseInsensitiveContains("Stockmans Ridge") {
            return TimeZone(identifier: "Australia/Sydney") ?? .current
        }
        return .current
    }

    // MARK: - Disease risk

    private func generateDiseaseAlerts(
        store: MigratedDataStore,
        vineyardId: UUID,
        prefs: BackendAlertPreferences,
        userId: UUID?
    ) async -> [BackendAlertUpsert] {
        let paddocks = store.paddocks.filter { $0.vineyardId == vineyardId && !$0.polygonPoints.isEmpty }
        guard let firstPaddock = paddocks.first else { return [] }
        let lat = firstPaddock.polygonPoints.map(\.latitude).reduce(0, +) / Double(firstPaddock.polygonPoints.count)
        let lon = firstPaddock.polygonPoints.map(\.longitude).reduce(0, +) / Double(firstPaddock.polygonPoints.count)

        await hourlyService.fetchWithDavisOverride(
            latitude: lat,
            longitude: lon,
            pastDays: 2,
            forecastDays: 3,
            vineyardId: vineyardId
        )
        guard let forecast = hourlyService.forecast, !forecast.hours.isEmpty else { return [] }

        var enabledModels: Set<DiseaseModel> = []
        if prefs.diseaseDownyEnabled { enabledModels.insert(.downyMildew) }
        if prefs.diseasePowderyEnabled { enabledModels.insert(.powderyMildew) }
        if prefs.diseaseBotrytisEnabled { enabledModels.insert(.botrytis) }
        guard !enabledModels.isEmpty else { return [] }

        let assessments = DiseaseRiskCalculator.assess(hours: forecast.hours, models: enabledModels)
        let today = today()
        let tomorrow = tomorrow()
        var upserts: [BackendAlertUpsert] = []

        for assessment in assessments {
            guard let severity = assessment.severity else { continue }
            let alertType: AlertType
            switch assessment.model {
            case .downyMildew: alertType = .diseaseDownyMildew
            case .powderyMildew: alertType = .diseasePowderyMildew
            case .botrytis: alertType = .diseaseBotrytis
            }
            let dedupKey = "disease:\(assessment.model.rawValue):\(yyyymmdd(Date()))"
            // Powdery is driven by temperature + RH, not wetness, so don't
            // append a wetness-source note for it.
            let wetnessNote: String
            switch assessment.model {
            case .powderyMildew:
                wetnessNote = ""
            case .downyMildew, .botrytis:
                wetnessNote = assessment.usedMeasuredWetness
                    ? " Based on measured leaf wetness."
                    : " Based on estimated wetness (no measured leaf wetness sensor)."
            }
            let alertId = deterministicUUID(vineyardId: vineyardId, dedupKey: dedupKey)
            upserts.append(BackendAlertUpsert(
                id: alertId,
                vineyardId: vineyardId,
                alertType: alertType.rawValue,
                severity: severity.rawValue,
                title: assessment.title,
                message: assessment.summary + wetnessNote,
                relatedTable: nil,
                relatedId: nil,
                paddockId: firstPaddock.id,
                action: AlertAction.openDiseaseRisk.rawValue,
                dedupKey: dedupKey,
                generatedForDate: today,
                expiresAt: tomorrow,
                createdBy: userId
            ))
        }
        return upserts
    }

    // MARK: - User actions

    func markRead(_ alert: AlertWithStatus) async {
        guard !alert.isRead else { return }
        try? await repository.markStatus(alertId: alert.alert.id, read: true, dismissed: nil)
        if let idx = alerts.firstIndex(where: { $0.id == alert.id }) {
            let now = Date()
            let newStatus = BackendAlertUserStatus(
                alertId: alert.alert.id,
                userId: alerts[idx].status?.userId ?? UUID(),
                readAt: now,
                dismissedAt: alerts[idx].status?.dismissedAt
            )
            alerts[idx] = AlertWithStatus(alert: alert.alert, status: newStatus)
        }
    }

    func markAllRead() async {
        for a in unreadAlerts {
            await markRead(a)
        }
    }

    func dismiss(_ alert: AlertWithStatus) async {
        try? await repository.markStatus(alertId: alert.alert.id, read: nil, dismissed: true)
        if let idx = alerts.firstIndex(where: { $0.id == alert.id }) {
            let now = Date()
            let newStatus = BackendAlertUserStatus(
                alertId: alert.alert.id,
                userId: alerts[idx].status?.userId ?? UUID(),
                readAt: alerts[idx].status?.readAt,
                dismissedAt: now
            )
            alerts[idx] = AlertWithStatus(alert: alert.alert, status: newStatus)
        }
    }

    // MARK: - Preferences

    func savePreferences(_ prefs: BackendAlertPreferences) async {
        do {
            try await repository.upsertPreferences(prefs)
            self.preferences = prefs
        } catch {
            self.status = .failure(error.localizedDescription)
        }
    }

    // MARK: - Helpers

    private func today() -> Date {
        Calendar.current.startOfDay(for: Date())
    }

    private func tomorrow() -> Date {
        Calendar.current.date(byAdding: .day, value: 1, to: today()) ?? Date()
    }

    private func yyyymmdd(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// Deterministic UUID derived from vineyardId + dedup key. Matching
    /// vineyard_id+dedup_key uniqueness in SQL means upserts overwrite the
    /// same row, but we still send a stable id so client and server agree.
    private func deterministicUUID(vineyardId: UUID, dedupKey: String) -> UUID {
        let raw = "\(vineyardId.uuidString):\(dedupKey)"
        var hash = UInt64(5381)
        for byte in raw.utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        var bytes = [UInt8](repeating: 0, count: 16)
        let h1 = hash
        let h2 = hash &* 6364136223846793005 &+ 1442695040888963407
        for i in 0..<8 {
            bytes[i] = UInt8((h1 >> (8 * i)) & 0xff)
            bytes[8 + i] = UInt8((h2 >> (8 * i)) & 0xff)
        }
        // Set version (4) and variant (RFC4122) bits.
        bytes[6] = (bytes[6] & 0x0f) | 0x40
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
