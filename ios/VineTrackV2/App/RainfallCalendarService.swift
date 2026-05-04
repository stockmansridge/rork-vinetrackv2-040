import Foundation

/// Fetches a year's worth of daily rainfall (mm) for the vineyard location,
/// preferring the configured local weather station (Davis WeatherLink) and
/// falling back gracefully to Open-Meteo Archive.
@MainActor
@Observable
final class RainfallCalendarService {
    var isLoading: Bool = false
    var errorMessage: String?
    var year: Int = Calendar.current.component(.year, from: Date())
    /// Daily rainfall keyed by start-of-day date.
    var dailyRainMm: [Date: Double] = [:]
    var providerLabel: String = "Source: Automatic Forecast / Historical Weather"
    var fallbackNote: String = "Daily history via Open-Meteo Archive"
    var lastUpdated: Date?
    var fallbackUsed: Bool = false
    var stationName: String?
    var isMeasured: Bool = false

    func load(year: Int,
              vineyardId: UUID?,
              latitude: Double,
              longitude: Double,
              weatherStationId: String?) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        self.year = year

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

        self.dailyRainMm = result.dailyMm
        self.providerLabel = result.providerLabel
        self.stationName = result.stationName
        self.isMeasured = result.isMeasured
        self.fallbackUsed = result.fallbackUsed
        self.fallbackNote = result.fallbackReason
            ?? (result.isMeasured
                ? "Daily totals from station archive"
                : "Daily history via Open-Meteo Archive")
        self.lastUpdated = Date()
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
