import Foundation

/// A single daily rainfall observation with provenance.
nonisolated struct RainfallObservation: Sendable, Hashable, Identifiable {
    let date: Date
    let rainfallMm: Double
    let isMeasured: Bool
    let provider: WeatherProvider
    let stationName: String?

    var id: Date { date }
}

/// Result of a rainfall history fetch — daily totals plus source labels and
/// any fallback warning text the UI should surface.
nonisolated struct RainfallHistoryResult: Sendable, Hashable {
    let dailyMm: [Date: Double]
    /// The provider the user *configured*. May differ from where data came
    /// from when fallback occurred.
    let configuredProvider: WeatherProvider
    /// The provider that actually supplied the data.
    let effectiveProvider: WeatherProvider
    let providerLabel: String
    let stationName: String?
    /// `true` when the values are measured station observations.
    let isMeasured: Bool
    let fallbackUsed: Bool
    let fallbackReason: String?
    let coveredFrom: Date
    let coveredTo: Date
    let recordCount: Int

    static let empty = RainfallHistoryResult(
        dailyMm: [:],
        configuredProvider: .automatic,
        effectiveProvider: .automatic,
        providerLabel: "Source: Automatic Forecast / Historical Weather",
        stationName: nil,
        isMeasured: false,
        fallbackUsed: false,
        fallbackReason: nil,
        coveredFrom: Date(),
        coveredTo: Date(),
        recordCount: 0
    )
}

/// Resolves the active weather provider and fetches daily rainfall, preferring
/// the local station (Davis WeatherLink) over forecast/archive sources.
///
/// Provider priority (for actual / historical rainfall):
/// A. Davis WeatherLink — selected, credentials saved, connection tested,
///    station selected.
/// B. Weather Underground (selected) — currently relies on Open-Meteo Archive
///    for historical daily totals (WU history requires its own per-station
///    history endpoint).
/// C. Automatic — Open-Meteo Archive.
@MainActor
enum RainfallHistoryService {
    /// We cap direct Davis archive fetches to this many trailing days so the
    /// total number of WeatherLink v2 calls (24h chunks) stays reasonable.
    /// Older portions of a year-long range are filled in from Open-Meteo
    /// Archive and clearly labelled as fallback data.
    static let davisMaxDaysWindow: Int = 120

    static func fetchDailyRainfall(
        vineyardId: UUID?,
        latitude: Double,
        longitude: Double,
        from: Date,
        to: Date,
        weatherStationId: String?
    ) async -> RainfallHistoryResult {
        let cal = Calendar.current
        let safeFrom = cal.startOfDay(for: from)
        let endOfToday = (cal.date(bySettingHour: 23, minute: 59, second: 59, of: cal.startOfDay(for: Date())) ?? Date())
        let safeTo = min(to, endOfToday)
        guard safeFrom <= safeTo else {
            return RainfallHistoryResult(
                dailyMm: [:],
                configuredProvider: .automatic,
                effectiveProvider: .automatic,
                providerLabel: "Source: Automatic Forecast / Historical Weather",
                stationName: nil,
                isMeasured: false,
                fallbackUsed: false,
                fallbackReason: nil,
                coveredFrom: safeFrom,
                coveredTo: safeTo,
                recordCount: 0
            )
        }

        let status: WeatherSourceStatus? = vineyardId.map {
            WeatherProviderResolver.resolve(for: $0, weatherStationId: weatherStationId)
        }
        let configuredProvider: WeatherProvider = status?.provider ?? .automatic

        // MARK: Davis path
        if let vid = vineyardId,
           let s = status,
           s.provider == .davis,
           s.quality != .forecastOnly {
            let cfg = WeatherProviderStore.shared.config(for: vid)
            let stationLabel = (cfg.davisStationName?.isEmpty == false ? cfg.davisStationName! : (cfg.davisStationId ?? ""))
            if let stationId = cfg.davisStationId, !stationId.isEmpty,
               let apiKey = WeatherKeychain.get(.apiKey),
               let apiSecret = WeatherKeychain.get(.apiSecret) {

                // Limit Davis fetch window to last `davisMaxDaysWindow` days.
                let earliestDavis = cal.date(byAdding: .day, value: -davisMaxDaysWindow, to: safeTo) ?? safeFrom
                let davisStart = max(safeFrom, earliestDavis)

                do {
                    let davis = try await DavisWeatherLinkService.fetchDailyRainfall(
                        apiKey: apiKey,
                        apiSecret: apiSecret,
                        stationId: stationId,
                        from: davisStart,
                        to: safeTo
                    )

                    var merged = davis.dailyMm
                    var fallbackUsed = false
                    var fallbackReason: String?

                    // Fill earlier portion from Open-Meteo Archive when range
                    // exceeds the Davis window.
                    if davisStart > safeFrom {
                        let priorEnd = cal.date(byAdding: .day, value: -1, to: davisStart) ?? safeFrom
                        if let archive = try? await OpenMeteoRainfallArchive.fetchDaily(
                            latitude: latitude,
                            longitude: longitude,
                            from: safeFrom,
                            to: priorEnd
                        ) {
                            for (k, v) in archive where merged[k] == nil {
                                merged[k] = v
                            }
                        }
                        fallbackUsed = true
                        fallbackReason = "Davis history covers the last \(davisMaxDaysWindow) days. Earlier dates filled from automatic archive."
                    }

                    let label = "Source: Davis WeatherLink — \(stationLabel)"
                    return RainfallHistoryResult(
                        dailyMm: merged,
                        configuredProvider: .davis,
                        effectiveProvider: .davis,
                        providerLabel: label,
                        stationName: cfg.davisStationName,
                        isMeasured: true,
                        fallbackUsed: fallbackUsed,
                        fallbackReason: fallbackReason,
                        coveredFrom: safeFrom,
                        coveredTo: safeTo,
                        recordCount: davis.recordCount
                    )
                } catch {
                    let archive = (try? await OpenMeteoRainfallArchive.fetchDaily(
                        latitude: latitude,
                        longitude: longitude,
                        from: safeFrom,
                        to: safeTo
                    )) ?? [:]
                    return RainfallHistoryResult(
                        dailyMm: archive,
                        configuredProvider: .davis,
                        effectiveProvider: .automatic,
                        providerLabel: "Source: Davis WeatherLink — \(stationLabel)",
                        stationName: cfg.davisStationName,
                        isMeasured: false,
                        fallbackUsed: true,
                        fallbackReason: "Davis data unavailable for this period — using fallback. (\(error.localizedDescription))",
                        coveredFrom: safeFrom,
                        coveredTo: safeTo,
                        recordCount: archive.count
                    )
                }
            }
        }

        // MARK: Fallback path (WU / Automatic / Davis-not-configured)
        let archive = (try? await OpenMeteoRainfallArchive.fetchDaily(
            latitude: latitude,
            longitude: longitude,
            from: safeFrom,
            to: safeTo
        )) ?? [:]

        let label: String
        var fallbackUsed = false
        var fallbackReason: String?
        switch configuredProvider {
        case .davis:
            label = "Source: Davis WeatherLink configured — using fallback"
            fallbackUsed = true
            fallbackReason = "Davis WeatherLink isn't fully connected yet. Using automatic archive data."
        case .wunderground:
            label = "Source: Weather Underground — historical via automatic archive"
            fallbackUsed = true
            fallbackReason = "Weather Underground daily history isn't supported yet. Using automatic archive data."
        case .automatic:
            label = "Source: Automatic Forecast / Historical Weather"
        }

        return RainfallHistoryResult(
            dailyMm: archive,
            configuredProvider: configuredProvider,
            effectiveProvider: .automatic,
            providerLabel: label,
            stationName: nil,
            isMeasured: false,
            fallbackUsed: fallbackUsed,
            fallbackReason: fallbackReason,
            coveredFrom: safeFrom,
            coveredTo: safeTo,
            recordCount: archive.count
        )
    }

    /// Convenience for "rainfall in the last N days" — used by Irrigation
    /// Advisor to offset the deficit calculation with measured rain.
    static func fetchRecentRainfall(
        vineyardId: UUID?,
        latitude: Double,
        longitude: Double,
        days: Int,
        weatherStationId: String?
    ) async -> RainfallHistoryResult {
        let cal = Calendar.current
        let to = Date()
        let from = cal.date(byAdding: .day, value: -max(1, days), to: cal.startOfDay(for: to))
            ?? to.addingTimeInterval(-Double(max(1, days)) * 86400)
        return await fetchDailyRainfall(
            vineyardId: vineyardId,
            latitude: latitude,
            longitude: longitude,
            from: from,
            to: to,
            weatherStationId: weatherStationId
        )
    }
}

// MARK: - Open-Meteo Archive (fallback)

nonisolated enum OpenMeteoRainfallArchive {
    /// Returns daily precipitation_sum keyed by start-of-day in
    /// `Calendar.current`.
    static func fetchDaily(
        latitude: Double,
        longitude: Double,
        from: Date,
        to: Date
    ) async throws -> [Date: Double] {
        let cal = Calendar.current
        let safeFrom = cal.startOfDay(for: from)
        let safeTo = min(to, cal.startOfDay(for: Date()).addingTimeInterval(24 * 3600 - 1))
        guard safeFrom <= safeTo else { return [:] }

        let fmt = DateFormatter()
        fmt.calendar = cal
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = cal.timeZone
        fmt.dateFormat = "yyyy-MM-dd"
        let startStr = fmt.string(from: safeFrom)
        let endStr = fmt.string(from: safeTo)

        let urlString = "https://archive-api.open-meteo.com/v1/archive?latitude=\(latitude)&longitude=\(longitude)&start_date=\(startStr)&end_date=\(endStr)&daily=precipitation_sum&timezone=auto"
        guard let url = URL(string: urlString) else { return [:] }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return [:]
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let daily = json["daily"] as? [String: Any],
              let times = daily["time"] as? [String],
              let rains = daily["precipitation_sum"] as? [Any] else {
            return [:]
        }

        var map: [Date: Double] = [:]
        let count = min(times.count, rains.count)
        for i in 0..<count {
            guard let d = fmt.date(from: times[i]) else { continue }
            if let value = parseDouble(rains[i]) {
                map[cal.startOfDay(for: d)] = value
            }
        }
        return map
    }

    private static func parseDouble(_ value: Any) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) }
        if value is NSNull { return nil }
        return nil
    }
}
