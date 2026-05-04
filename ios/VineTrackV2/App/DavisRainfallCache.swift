import Foundation

/// On-device cache for Davis WeatherLink daily rainfall (mm) per station/year.
///
/// Davis WeatherLink v2 historic endpoint allows a 24-hour window per call,
/// so a full year-long fetch can be 365 calls per station. To stay well below
/// the WeatherLink rate limit we persist the daily totals we've already
/// computed and only fetch the days we don't have, plus today/yesterday
/// (which can still accumulate rainfall in real time).
nonisolated enum DavisRainfallCache {
    private static let prefix = "DavisRainfallCache.v1"
    private static let lastFetchedSuffix = ".lastFetched"

    private static func key(stationId: String, year: Int) -> String {
        "\(prefix).\(stationId).\(year)"
    }

    private static func dateFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = Calendar.current.timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

    /// Returns cached daily rainfall (start-of-day → mm) for the given
    /// station/year. Empty when nothing is cached.
    static func load(stationId: String, year: Int) -> [Date: Double] {
        let k = key(stationId: stationId, year: year)
        let raw = UserDefaults.standard.dictionary(forKey: k) ?? [:]
        let cal = Calendar.current
        let fmt = dateFormatter()
        var out: [Date: Double] = [:]
        for (s, v) in raw {
            guard let d = fmt.date(from: s) else { continue }
            let mm: Double?
            if let dbl = v as? Double { mm = dbl }
            else if let i = v as? Int { mm = Double(i) }
            else if let n = v as? NSNumber { mm = n.doubleValue }
            else { mm = nil }
            if let mm { out[cal.startOfDay(for: d)] = mm }
        }
        return out
    }

    /// Replaces the cache entry entirely.
    static func save(stationId: String, year: Int, daily: [Date: Double]) {
        let fmt = dateFormatter()
        var dict: [String: Double] = [:]
        for (date, v) in daily {
            dict[fmt.string(from: date)] = v
        }
        let k = key(stationId: stationId, year: year)
        UserDefaults.standard.set(dict, forKey: k)
        UserDefaults.standard.set(Date(), forKey: k + lastFetchedSuffix)
    }

    /// Merges new values into the cached entry, returning the merged map.
    /// New values overwrite existing ones for the same date.
    @discardableResult
    static func merge(stationId: String, year: Int, additions: [Date: Double]) -> [Date: Double] {
        var existing = load(stationId: stationId, year: year)
        for (k, v) in additions { existing[k] = v }
        save(stationId: stationId, year: year, daily: existing)
        return existing
    }

    static func lastFetched(stationId: String, year: Int) -> Date? {
        UserDefaults.standard.object(forKey: key(stationId: stationId, year: year) + lastFetchedSuffix) as? Date
    }

    static func clear(stationId: String, year: Int) {
        let k = key(stationId: stationId, year: year)
        UserDefaults.standard.removeObject(forKey: k)
        UserDefaults.standard.removeObject(forKey: k + lastFetchedSuffix)
    }
}
