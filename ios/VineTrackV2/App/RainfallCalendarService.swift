import Foundation

/// Fetches a year's worth of daily rainfall (mm) for the vineyard location,
/// preferring the configured local weather station (Davis WeatherLink) and
/// falling back gracefully to Open-Meteo Archive.
@MainActor
@Observable
final class RainfallCalendarService {
    var isLoading: Bool = false
    var isRefreshingRecent: Bool = false
    var errorMessage: String?
    var year: Int = Calendar.current.component(.year, from: Date())
    /// Daily rainfall keyed by start-of-day date.
    var dailyRainMm: [Date: Double] = [:]
    /// Per-day source (start-of-day → provenance).
    var sources: [Date: RainfallSource] = [:]
    var providerLabel: String = "Source: Automatic Forecast / Historical Weather"
    var fallbackNote: String = "Daily history via Open-Meteo Archive"
    var coverageSummary: String?
    var lastUpdated: Date?
    var fallbackUsed: Bool = false
    var rateLimited: Bool = false
    var stationName: String?
    var isMeasured: Bool = false
    var davisDaysCovered: Int = 0
    var wuDaysCovered: Int = 0
    var archiveDaysCovered: Int = 0

    private var lastVineyardId: UUID?
    private var lastLatitude: Double?
    private var lastLongitude: Double?
    private var lastWeatherStationId: String?

    func load(year: Int,
              vineyardId: UUID?,
              latitude: Double,
              longitude: Double,
              weatherStationId: String?) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        self.year = year
        self.lastVineyardId = vineyardId
        self.lastLatitude = latitude
        self.lastLongitude = longitude
        self.lastWeatherStationId = weatherStationId

        let cal = Calendar.current
        var comps = DateComponents()
        comps.year = year; comps.month = 1; comps.day = 1
        guard let jan1 = cal.date(from: comps) else {
            errorMessage = "Invalid year"
            return
        }
        comps.month = 12; comps.day = 31
        guard let dec31 = cal.date(from: comps) else {
            errorMessage = "Invalid year"
            return
        }
        let today = cal.startOfDay(for: Date())
        let end = min(dec31, today)

        if end < jan1 {
            self.dailyRainMm = [:]
            self.sources = [:]
            self.lastUpdated = Date()
            return
        }

        let result = await RainfallHistoryService.fetchDailyRainfall(
            vineyardId: vineyardId,
            latitude: latitude,
            longitude: longitude,
            from: jan1,
            to: end,
            weatherStationId: weatherStationId
        )

        apply(result)
    }

    /// Refresh only the most recent `days` days from Davis (or the active local
    /// provider). Existing cached/archive values for older dates are kept.
    func refreshRecent(days: Int = 30) async {
        guard let lat = lastLatitude, let lon = lastLongitude else { return }
        isRefreshingRecent = true
        defer { isRefreshingRecent = false }

        let cal = Calendar.current
        let to = cal.startOfDay(for: Date())
        let from = cal.date(byAdding: .day, value: -max(1, days), to: to) ?? to

        let recent = await RainfallHistoryService.fetchDailyRainfall(
            vineyardId: lastVineyardId,
            latitude: lat,
            longitude: lon,
            from: from,
            to: Date(),
            weatherStationId: lastWeatherStationId,
            davisRecentOnlyDays: days
        )

        // Merge recent results into the existing yearly dataset so older
        // dates remain unchanged.
        var merged = dailyRainMm
        var mergedSources = sources
        for (k, v) in recent.dailyMm {
            merged[k] = v
        }
        for (k, v) in recent.sources {
            mergedSources[k] = v
        }
        dailyRainMm = merged
        sources = mergedSources
        providerLabel = recent.providerLabel
        stationName = recent.stationName
        isMeasured = recent.isMeasured || isMeasured
        fallbackUsed = recent.fallbackUsed || fallbackUsed
        rateLimited = recent.rateLimited
        fallbackNote = recent.fallbackReason ?? fallbackNote
        davisDaysCovered = mergedSources.values.filter { $0 == .davis }.count
        wuDaysCovered = mergedSources.values.filter { $0 == .wunderground }.count
        archiveDaysCovered = mergedSources.values.filter { $0 == .archive }.count
        coverageSummary = coverageSummaryString(davis: davisDaysCovered, wu: wuDaysCovered, archive: archiveDaysCovered)
        lastUpdated = Date()
    }

    private func apply(_ result: RainfallHistoryResult) {
        self.dailyRainMm = result.dailyMm
        self.sources = result.sources
        self.providerLabel = result.providerLabel
        self.stationName = result.stationName
        self.isMeasured = result.isMeasured
        self.fallbackUsed = result.fallbackUsed
        self.rateLimited = result.rateLimited
        self.davisDaysCovered = result.davisDaysCovered
        self.wuDaysCovered = result.wuDaysCovered
        self.archiveDaysCovered = result.archiveDaysCovered
        self.coverageSummary = result.coverageSummary
        self.fallbackNote = result.fallbackReason
            ?? (result.isMeasured
                ? "Daily totals from station archive"
                : "Daily history via Open-Meteo Archive")
        self.lastUpdated = Date()
    }

    private func coverageSummaryString(davis: Int, wu: Int, archive: Int) -> String? {
        var parts: [String] = []
        if davis > 0 { parts.append("Davis: \(davis) day\(davis == 1 ? "" : "s")") }
        if wu > 0 { parts.append("WU: \(wu) day\(wu == 1 ? "" : "s")") }
        if archive > 0 { parts.append("Archive: \(archive) day\(archive == 1 ? "" : "s")") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Per-month summary derived from a `[Date: Double]` rainfall map.
nonisolated struct RainfallMonthSummary: Sendable, Hashable, Identifiable {
    let month: Int          // 1...12
    let totalMm: Double
    let rainDays: Int
    let wettestDay: Int?    // day of month, or nil
    let wettestDayMm: Double?
    let averageMm: Double   // average across days that have a value
    let daysWithData: Int

    var id: Int { month }
}

/// Annual roll-up.
nonisolated struct RainfallAnnualSummary: Sendable, Hashable {
    let year: Int
    let totalMm: Double
    let rainDays: Int
    let wettestDay: Date?
    let wettestDayMm: Double?
    let wettestMonth: Int?
    let wettestMonthMm: Double?
    let driestMonth: Int?
    let driestMonthMm: Double?
    let daysWithData: Int
}

enum RainfallCalendarMath {
    static let rainDayThresholdMm: Double = 0.2

    static func monthSummaries(year: Int, daily: [Date: Double]) -> [RainfallMonthSummary] {
        let cal = Calendar.current
        var byMonth: [Int: [(day: Int, mm: Double)]] = [:]
        for (date, mm) in daily {
            let comps = cal.dateComponents([.year, .month, .day], from: date)
            guard comps.year == year, let m = comps.month, let d = comps.day else { continue }
            byMonth[m, default: []].append((d, mm))
        }
        return (1...12).map { m in
            let entries = byMonth[m] ?? []
            let total = entries.reduce(0) { $0 + $1.mm }
            let rainDays = entries.filter { $0.mm >= rainDayThresholdMm }.count
            let wettest = entries.max(by: { $0.mm < $1.mm })
            let avg = entries.isEmpty ? 0 : total / Double(entries.count)
            return RainfallMonthSummary(
                month: m,
                totalMm: total,
                rainDays: rainDays,
                wettestDay: wettest.map { $0.day },
                wettestDayMm: wettest.map { $0.mm },
                averageMm: avg,
                daysWithData: entries.count
            )
        }
    }

    static func annual(year: Int, daily: [Date: Double], months: [RainfallMonthSummary]) -> RainfallAnnualSummary {
        let cal = Calendar.current
        let total = months.reduce(0) { $0 + $1.totalMm }
        let rainDays = months.reduce(0) { $0 + $1.rainDays }
        let daysWithData = months.reduce(0) { $0 + $1.daysWithData }

        var wettestDate: Date?
        var wettestMm: Double = -1
        for (date, mm) in daily {
            let comps = cal.dateComponents([.year], from: date)
            guard comps.year == year else { continue }
            if mm > wettestMm {
                wettestMm = mm
                wettestDate = date
            }
        }

        let nonZeroMonths = months.filter { $0.daysWithData > 0 }
        let wettestMonth = nonZeroMonths.max(by: { $0.totalMm < $1.totalMm })
        let driestMonth = nonZeroMonths.min(by: { $0.totalMm < $1.totalMm })

        return RainfallAnnualSummary(
            year: year,
            totalMm: total,
            rainDays: rainDays,
            wettestDay: wettestDate,
            wettestDayMm: wettestMm > 0 ? wettestMm : nil,
            wettestMonth: wettestMonth?.month,
            wettestMonthMm: wettestMonth?.totalMm,
            driestMonth: driestMonth?.month,
            driestMonthMm: driestMonth?.totalMm,
            daysWithData: daysWithData
        )
    }
}
