import Foundation

// MARK: - Models

nonisolated struct DavisStation: Sendable, Hashable, Identifiable, Codable {
    let stationId: String
    let stationIdUuid: String?
    let name: String
    let latitude: Double?
    let longitude: Double?
    let timezone: String?
    let active: Bool?

    var id: String { stationId }
}

nonisolated struct DavisSensorSummary: Sendable, Hashable, Codable {
    let hasTemperatureHumidity: Bool
    let hasRain: Bool
    let hasWind: Bool
    let hasLeafWetness: Bool
    let hasSoilMoisture: Bool
    let detectedFields: [String]
    let detectedSensorTypes: [Int]
    let detectedDataStructureTypes: [Int]

    /// Friendly list rendered in the settings UI.
    var displayList: [String] {
        var items: [String] = []
        if hasTemperatureHumidity { items.append("Temperature / Humidity") }
        if hasRain { items.append("Rainfall") }
        if hasWind { items.append("Wind") }
        if hasLeafWetness { items.append("Leaf wetness") }
        if hasSoilMoisture { items.append("Soil moisture") }
        return items
    }

    static let empty = DavisSensorSummary(
        hasTemperatureHumidity: false,
        hasRain: false,
        hasWind: false,
        hasLeafWetness: false,
        hasSoilMoisture: false,
        detectedFields: [],
        detectedSensorTypes: [],
        detectedDataStructureTypes: []
    )
}

/// Daily rainfall totals (mm) aggregated from WeatherLink v2 historic
/// archive records. Keys are start-of-day in `Calendar.current`.
nonisolated struct DavisDailyRainfall: Sendable, Hashable {
    let dailyMm: [Date: Double]
    let totalMm: Double
    let recordCount: Int
    let coveredFrom: Date
    let coveredTo: Date
}

nonisolated struct DavisCurrentConditions: Sendable, Hashable {
    let stationId: String
    let generatedAt: Date
    /// Mapped current observations (best-effort; nil when not reported by the
    /// station). Davis returns imperial units; conversions happen here so
    /// callers always work in metric.
    let temperatureC: Double?
    let humidityPercent: Double?
    let rainMmLastHour: Double?
    let windKph: Double?
    /// `true`/`false` only when the station has a leaf-wetness sensor and the
    /// API returned a numeric reading; `nil` otherwise.
    let measuredLeafWetness: Bool?
    let sensors: DavisSensorSummary
}

nonisolated enum DavisWeatherLinkError: LocalizedError, Sendable {
    case missingCredentials
    case invalidCredentials
    case noStations
    case network(String)
    case decoding(String)
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "Save your Davis API Key and Secret first."
        case .invalidCredentials:
            return "Could not connect to WeatherLink. Check your API Key and API Secret."
        case .noStations:
            return "Connected, but no stations were returned for this WeatherLink account."
        case .network(let m):
            return "WeatherLink unavailable — \(m)"
        case .decoding(let m):
            return "WeatherLink response could not be parsed (\(m))."
        case .http(let code):
            if code == 401 || code == 403 {
                return "Could not connect to WeatherLink. Check your API Key and API Secret."
            }
            return "WeatherLink returned HTTP \(code)."
        }
    }
}

// MARK: - Service

/// Davis WeatherLink v2 client.
/// API Key is sent as the `api-key` query parameter; API Secret is sent in
/// the `X-Api-Secret` header. Neither is logged or persisted outside the
/// device Keychain.
nonisolated enum DavisWeatherLinkService {

    private static let baseURL = "https://api.weatherlink.com/v2"

    /// Validates credentials and returns the available stations. Use this for
    /// the Test Connection action.
    static func testConnection(apiKey: String, apiSecret: String) async throws -> [DavisStation] {
        try await fetchStations(apiKey: apiKey, apiSecret: apiSecret)
    }

    /// GET /v2/stations
    static func fetchStations(apiKey: String, apiSecret: String) async throws -> [DavisStation] {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSecret = apiSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty, !trimmedSecret.isEmpty else {
            throw DavisWeatherLinkError.missingCredentials
        }
        let data = try await get(path: "/stations", apiKey: trimmedKey, apiSecret: trimmedSecret)
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let array = json["stations"] as? [[String: Any]] else {
            throw DavisWeatherLinkError.decoding("Missing 'stations' array")
        }
        let stations = array.compactMap(parseStationDict)
        if stations.isEmpty { throw DavisWeatherLinkError.noStations }
        return stations
    }

    /// GET /v2/current/{station-id}
    static func fetchCurrentConditions(
        apiKey: String,
        apiSecret: String,
        stationId: String
    ) async throws -> DavisCurrentConditions {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSecret = apiSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty, !trimmedSecret.isEmpty, !stationId.isEmpty else {
            throw DavisWeatherLinkError.missingCredentials
        }
        let data = try await get(
            path: "/current/\(stationId)",
            apiKey: trimmedKey,
            apiSecret: trimmedSecret
        )
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw DavisWeatherLinkError.decoding("Invalid JSON")
        }
        return parseCurrentConditionsJSON(json, fallbackStationId: stationId)
    }

    /// Parses a WeatherLink v2 `/current/{station-id}` response (already
    /// decoded as a JSON object). Used by both the direct Davis client and
    /// the vineyard-shared proxy path.
    static func parseCurrentConditionsJSON(
        _ json: [String: Any],
        fallbackStationId: String
    ) -> DavisCurrentConditions {
        let resolvedStationId: String = {
            if let n = json["station_id"] as? Int { return String(n) }
            if let s = json["station_id"] as? String { return s }
            return fallbackStationId
        }()
        let generatedAt: Date = {
            if let n = parseAnyDouble(json["generated_at"] ?? 0) { return Date(timeIntervalSince1970: n) }
            return Date()
        }()

        let sensorsArr = (json["sensors"] as? [[String: Any]]) ?? []
        let summary = detectSensors(sensorsArr: sensorsArr)

        var temperatureF: Double?
        var humidity: Double?
        var rainMm: Double?
        var windKph: Double?
        var leafWetnessReading: Double?

        for sensor in sensorsArr {
            guard let dataArr = sensor["data"] as? [[String: Any]],
                  let latest = dataArr.last else { continue }

            for (rawKey, value) in latest {
                let key = rawKey.lowercased()
                guard let v = parseAnyDouble(value) else { continue }

                // Outdoor air temperature/humidity (skip indoor, soil, leaf-temp).
                if temperatureF == nil,
                   (key == "temp" || key == "temp_out" || key == "temp_avg" || key == "temp_last") {
                    temperatureF = v
                }
                if humidity == nil,
                   (key == "hum" || key == "hum_out" || key == "hum_last") {
                    humidity = v
                }

                // Rainfall — prefer last 60 min metric/imperial fields if present.
                if rainMm == nil {
                    if key.contains("rainfall_last_60_min_mm") {
                        rainMm = v
                    } else if key.contains("rainfall_last_60_min_in") {
                        rainMm = v * 25.4
                    } else if key == "rain_rate_last_mm" || key == "rainfall_last_15_min_mm" {
                        rainMm = v
                    } else if key == "rain_rate_last_in" || key == "rainfall_last_15_min_in" {
                        rainMm = v * 25.4
                    }
                }

                // Wind — average over recent window if available.
                if windKph == nil,
                   (key.contains("wind_speed_avg_last_10_min")
                    || key.contains("wind_speed_last")
                    || key == "wind_speed") {
                    // Davis reports mph.
                    windKph = v * 1.60934
                }

                // Leaf wetness — Davis fields look like wet_leaf_last_*, leaf_wetness_*, etc.
                if leafWetnessReading == nil, isLeafWetnessKey(key) {
                    leafWetnessReading = v
                }
            }
        }

        let measuredLeafWetness: Bool? = {
            guard summary.hasLeafWetness, let reading = leafWetnessReading else { return nil }
            // Davis leaf wetness scale is 0..15. Industry threshold ~7.
            return reading >= 7
        }()

        let temperatureC: Double? = temperatureF.map { ($0 - 32) * 5 / 9 }

        return DavisCurrentConditions(
            stationId: resolvedStationId,
            generatedAt: generatedAt,
            temperatureC: temperatureC,
            humidityPercent: humidity,
            rainMmLastHour: rainMm,
            windKph: windKph,
            measuredLeafWetness: measuredLeafWetness,
            sensors: summary
        )
    }

    // MARK: - Sensor detection

    /// Inspects WeatherLink current-conditions sensor blocks and reports which
    /// sensor types are present based on field names + sensor metadata.
    static func detectSensors(sensorsArr: [[String: Any]]) -> DavisSensorSummary {
        var hasTH = false
        var hasRain = false
        var hasWind = false
        var hasLW = false
        var hasSoil = false
        var fields: Set<String> = []
        var sensorTypes: Set<Int> = []
        var dataStructTypes: Set<Int> = []

        for sensor in sensorsArr {
            if let st = sensor["sensor_type"] as? Int { sensorTypes.insert(st) }
            if let ds = sensor["data_structure_type"] as? Int { dataStructTypes.insert(ds) }

            // Davis sensor type 242 = Leaf & Soil Moisture/Temp ISS.
            if let st = sensor["sensor_type"] as? Int, st == 242 {
                hasLW = true
                hasSoil = true
            }

            guard let dataArr = sensor["data"] as? [[String: Any]] else { continue }
            for entry in dataArr {
                for rawKey in entry.keys {
                    fields.insert(rawKey)
                    let key = rawKey.lowercased()

                    // Outdoor air T/H — exclude indoor / soil / leaf-temp variants.
                    if (key.contains("temp") || key.contains("hum") || key.contains("dew")) &&
                        !key.contains("soil") && !key.contains("leaf") &&
                        !key.hasPrefix("temp_in") && !key.hasPrefix("hum_in") &&
                        !key.contains("_in_") {
                        hasTH = true
                    }
                    if key.contains("rain") || key.contains("rainfall") {
                        hasRain = true
                    }
                    if key.contains("wind") {
                        hasWind = true
                    }
                    if isLeafWetnessKey(key) {
                        hasLW = true
                    }
                    if key.contains("soil_moisture") || key.contains("moist_soil") {
                        hasSoil = true
                    }
                }
            }
        }

        return DavisSensorSummary(
            hasTemperatureHumidity: hasTH,
            hasRain: hasRain,
            hasWind: hasWind,
            hasLeafWetness: hasLW,
            hasSoilMoisture: hasSoil,
            detectedFields: Array(fields).sorted(),
            detectedSensorTypes: Array(sensorTypes).sorted(),
            detectedDataStructureTypes: Array(dataStructTypes).sorted()
        )
    }

    // MARK: - Internals

    private static func isLeafWetnessKey(_ key: String) -> Bool {
        // Common Davis WeatherLink field names for leaf wetness:
        // wet_leaf_last_1, wet_leaf_last_2, leaf_wetness, leaf_wetness_*,
        // leaf_wetness_last_*, wet_leaf_at_*.
        if key.contains("leaf_wetness") { return true }
        if key.contains("wet_leaf") { return true }
        if key.contains("leaf_wet") { return true }
        return false
    }

    static func parseStationDict(_ dict: [String: Any]) -> DavisStation? {
        let stationId: String
        if let n = dict["station_id"] as? Int {
            stationId = String(n)
        } else if let s = dict["station_id"] as? String {
            stationId = s
        } else if let n = dict["station_id"] as? NSNumber {
            stationId = n.stringValue
        } else {
            return nil
        }
        let name = (dict["station_name"] as? String) ?? "Davis Station \(stationId)"
        let active: Bool? = {
            if let b = dict["active"] as? Bool { return b }
            if let i = dict["active"] as? Int { return i != 0 }
            return nil
        }()
        return DavisStation(
            stationId: stationId,
            stationIdUuid: dict["station_id_uuid"] as? String,
            name: name,
            latitude: parseAnyDouble(dict["latitude"] ?? 0),
            longitude: parseAnyDouble(dict["longitude"] ?? 0),
            timezone: dict["time_zone"] as? String,
            active: active
        )
    }

    private static func get(
        path: String,
        apiKey: String,
        apiSecret: String,
        extraQuery: [URLQueryItem] = []
    ) async throws -> Data {
        guard var components = URLComponents(string: baseURL + path) else {
            throw DavisWeatherLinkError.network("Invalid URL")
        }
        var items: [URLQueryItem] = [URLQueryItem(name: "api-key", value: apiKey)]
        items.append(contentsOf: extraQuery)
        components.queryItems = items
        guard let url = components.url else {
            throw DavisWeatherLinkError.network("Invalid URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiSecret, forHTTPHeaderField: "X-Api-Secret")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw DavisWeatherLinkError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw DavisWeatherLinkError.network("No HTTP response")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw DavisWeatherLinkError.invalidCredentials
        }
        guard (200..<300).contains(http.statusCode) else {
            throw DavisWeatherLinkError.http(http.statusCode)
        }
        return data
    }

    // MARK: - Historic rainfall

    /// Per WeatherLink v2 docs, the historic endpoint accepts a window of up
    /// to 24 hours per call. We chunk longer windows into 24h calls.
    private static let historicChunkSeconds: TimeInterval = 24 * 60 * 60

    /// Fetches archive (interval) rainfall and aggregates to daily totals (mm)
    /// using `Calendar.current` (device timezone). Splits the requested window
    /// into 24-hour chunks to satisfy the WeatherLink v2 historic limit.
    ///
    /// Cumulative running totals (`rainfall_year_*`, `rainfall_monthly_*`,
    /// `rainfall_daily_*`, `rainfall_storm_*`) are deliberately ignored — only
    /// per-interval `rainfall_mm` / `rainfall_in` fields are summed.
    static func fetchDailyRainfall(
        apiKey: String,
        apiSecret: String,
        stationId: String,
        from: Date,
        to: Date,
        maxConcurrent: Int = 4
    ) async throws -> DavisDailyRainfall {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSecret = apiSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty, !trimmedSecret.isEmpty, !stationId.isEmpty else {
            throw DavisWeatherLinkError.missingCredentials
        }
        guard from < to else {
            return DavisDailyRainfall(dailyMm: [:], totalMm: 0, recordCount: 0,
                                      coveredFrom: from, coveredTo: to)
        }

        var chunks: [(start: Date, end: Date)] = []
        var cur = from
        while cur < to {
            let next = min(cur.addingTimeInterval(historicChunkSeconds), to)
            chunks.append((cur, next))
            cur = next
        }

        let limit = max(1, min(maxConcurrent, 6))
        var perRecord: [(ts: Date, mm: Double)] = []

        try await withThrowingTaskGroup(of: [(Date, Double)].self) { group in
            var index = 0
            var inFlight = 0
            while index < chunks.count {
                while inFlight < limit && index < chunks.count {
                    let chunk = chunks[index]
                    index += 1
                    inFlight += 1
                    group.addTask {
                        try await fetchHistoricRainfallChunk(
                            apiKey: trimmedKey,
                            apiSecret: trimmedSecret,
                            stationId: stationId,
                            startEpoch: Int(chunk.start.timeIntervalSince1970),
                            endEpoch: Int(chunk.end.timeIntervalSince1970)
                        )
                    }
                }
                if let res = try await group.next() {
                    perRecord.append(contentsOf: res)
                    inFlight -= 1
                }
            }
            for try await res in group {
                perRecord.append(contentsOf: res)
            }
        }

        let cal = Calendar.current
        var daily: [Date: Double] = [:]
        for (ts, mm) in perRecord {
            let key = cal.startOfDay(for: ts)
            daily[key, default: 0] += mm
        }
        let total = daily.values.reduce(0, +)
        return DavisDailyRainfall(
            dailyMm: daily,
            totalMm: total,
            recordCount: perRecord.count,
            coveredFrom: from,
            coveredTo: to
        )
    }

    /// Convenience: total rainfall for the last `days` days plus the daily
    /// breakdown.
    static func fetchRecentRainfall(
        apiKey: String,
        apiSecret: String,
        stationId: String,
        days: Int
    ) async throws -> DavisDailyRainfall {
        let cal = Calendar.current
        let to = Date()
        let startOfToday = cal.startOfDay(for: to)
        let from = cal.date(byAdding: .day, value: -max(1, days), to: startOfToday)
            ?? to.addingTimeInterval(-Double(max(1, days)) * 86400)
        return try await fetchDailyRainfall(
            apiKey: apiKey,
            apiSecret: apiSecret,
            stationId: stationId,
            from: from,
            to: to
        )
    }

    private static func fetchHistoricRainfallChunk(
        apiKey: String,
        apiSecret: String,
        stationId: String,
        startEpoch: Int,
        endEpoch: Int
    ) async throws -> [(Date, Double)] {
        let extra = [
            URLQueryItem(name: "start-timestamp", value: String(startEpoch)),
            URLQueryItem(name: "end-timestamp", value: String(endEpoch))
        ]
        let data = try await get(
            path: "/historic/\(stationId)",
            apiKey: apiKey,
            apiSecret: apiSecret,
            extraQuery: extra
        )
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let sensors = json["sensors"] as? [[String: Any]] else {
            throw DavisWeatherLinkError.decoding("Missing 'sensors' array in historic")
        }
        return parseHistoricRainfall(sensorsArr: sensors)
    }

    /// Parses interval rainfall fields from a WeatherLink v2 historic
    /// response. Returns `(timestamp, mm)` per archive record.
    static func parseHistoricRainfall(sensorsArr: [[String: Any]]) -> [(Date, Double)] {
        var out: [(Date, Double)] = []
        for sensor in sensorsArr {
            guard let dataArr = sensor["data"] as? [[String: Any]] else { continue }
            for entry in dataArr {
                guard let ts = parseAnyDouble(entry["ts"] ?? 0), ts > 0 else { continue }
                var mm: Double?
                // Prefer metric per-interval field, then imperial.
                if let v = parseAnyDouble(entry["rainfall_mm"] ?? 0),
                   !isCumulativeFieldPresent(entry: entry, preferredKey: "rainfall_mm") {
                    mm = v
                } else if let v = parseAnyDouble(entry["rainfall_in"] ?? 0),
                          !isCumulativeFieldPresent(entry: entry, preferredKey: "rainfall_in") {
                    mm = v * 25.4
                }
                if let value = mm, value.isFinite, value >= 0 {
                    out.append((Date(timeIntervalSince1970: ts), value))
                }
            }
        }
        return out
    }

    /// Helper: ensures the field we read is the per-interval rain key, not a
    /// running counter. Currently we only inspect the chosen key directly.
    private static func isCumulativeFieldPresent(entry: [String: Any], preferredKey: String) -> Bool {
        let key = preferredKey.lowercased()
        return key.contains("year") || key.contains("month") || key.contains("daily") || key.contains("storm")
    }

    static func parseAnyDouble(_ value: Any) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) }
        return nil
    }
}
