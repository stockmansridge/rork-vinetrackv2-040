import Foundation

/// Fetches a year's worth of daily rainfall (mm) for the vineyard location.
///
/// Phase 1 uses the Open-Meteo Archive API for historical daily rainfall.
/// The resolved provider label (Davis / Weather Underground / Automatic) is
/// preserved so the UI can show the configured source even when historical
/// values are filled by the Open-Meteo fallback.
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

    func load(year: Int,
              latitude: Double,
              longitude: Double,
              providerLabel: String) async {
        isLoading = true
        errorMessage = nil
        self.providerLabel = providerLabel
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
            // Year is entirely in the future.
            self.dailyRainMm = [:]
            self.lastUpdated = Date()
            return
        }

        let fmt = DateFormatter()
        fmt.calendar = cal
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = cal.timeZone
        fmt.dateFormat = "yyyy-MM-dd"
        let startStr = fmt.string(from: jan1)
        let endStr = fmt.string(from: end)

        let urlString = "https://archive-api.open-meteo.com/v1/archive?latitude=\(latitude)&longitude=\(longitude)&start_date=\(startStr)&end_date=\(endStr)&daily=precipitation_sum&timezone=auto"

        guard let url = URL(string: urlString) else {
            errorMessage = "Invalid rainfall URL"
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                errorMessage = "Could not load rainfall (HTTP \(code))"
                return
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let daily = json["daily"] as? [String: Any],
                  let times = daily["time"] as? [String],
                  let rains = daily["precipitation_sum"] as? [Any] else {
                errorMessage = "Could not parse rainfall response"
                return
            }

            var map: [Date: Double] = [:]
            let count = min(times.count, rains.count)
            for i in 0..<count {
                guard let d = fmt.date(from: times[i]) else { continue }
                if let value = Self.parse(rains[i]) {
                    map[cal.startOfDay(for: d)] = value
                }
            }
            self.dailyRainMm = map
            self.lastUpdated = Date()
        } catch {
            errorMessage = "Could not load rainfall: \(error.localizedDescription)"
        }
    }

    private static func parse(_ value: Any) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) }
        if value is NSNull { return nil }
        return nil
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
