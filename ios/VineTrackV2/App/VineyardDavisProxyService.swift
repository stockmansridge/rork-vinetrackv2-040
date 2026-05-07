import Foundation
import Supabase

/// Status of a single server-side write performed by the davis-proxy
/// edge function during a `current` action. Returned in the response
/// body so the iOS UI can confirm exactly which writes succeeded
/// without depending on Edge Function log access.
nonisolated struct DavisProxyWriteStatus: Sendable, Equatable {
    public let attempted: Bool
    public let success: Bool
    public let code: String?
    public let message: String?
}

/// Server-side diagnostics returned by the davis-proxy `current` action.
/// Reports whether `vineyard_weather_observations` and `rainfall_daily`
/// were written, plus the vineyard-local date and parsed rain value used.
nonisolated struct DavisProxyCurrentDiagnostics: Sendable, Equatable {
    public let observations: DavisProxyWriteStatus
    public let rainfallDaily: DavisProxyWriteStatus
    public let rainfallDate: String?
    public let rainTodayMm: Double?
    public let stationId: String?
    public let stationName: String?
    public let timezone: String?
    /// Deployed proxy build identifier, taken from `_proxy.version` (or
    /// the top-level `_proxy_version` fallback). Lets the UI prove which
    /// edge function code is actually serving requests.
    public let version: String?
}

/// Bundles the parsed current conditions with the server-side proxy
/// diagnostics for a `current` action.
nonisolated struct DavisProxyCurrentResult: Sendable {
    public let conditions: DavisCurrentConditions
    public let diagnostics: DavisProxyCurrentDiagnostics?
}

/// Errors surfaced by the davis-proxy edge function.
nonisolated enum VineyardDavisProxyError: LocalizedError, Sendable {
    case notAuthenticated
    case forbidden(String)
    case notConfigured
    case rateLimited
    case network(String)
    case decoding(String)
    case http(Int, String?)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Sign in to use the vineyard's Davis WeatherLink connection."
        case .forbidden(let m):
            return m.isEmpty ? "You don't have permission for this Davis action." : m
        case .notConfigured:
            return "Davis WeatherLink setup is incomplete for this vineyard."
        case .rateLimited:
            return "WeatherLink rate limit reached. Showing archive rainfall for now."
        case .network(let m):
            return "WeatherLink unavailable — \(m)"
        case .decoding(let m):
            return "WeatherLink response could not be parsed (\(m))."
        case .http(let code, let msg):
            if let msg, !msg.isEmpty { return msg }
            return "WeatherLink proxy returned HTTP \(code)."
        }
    }
}

/// Client for the `davis-proxy` Supabase Edge Function. Used by *every*
/// vineyard member (owner, manager, operator) once the vineyard has a
/// shared Davis WeatherLink integration. Operators never hold the API
/// secret; the edge function reads vineyard credentials with the
/// service-role key after verifying membership.
nonisolated enum VineyardDavisProxyService {

    private static let functionName = "davis-proxy"

    /// Per WeatherLink v2 docs the historic endpoint accepts a 24h window
    /// per call, so longer ranges are chunked the same way as the direct
    /// Davis client.
    private static let historicChunkSeconds: TimeInterval = 24 * 60 * 60

    // MARK: - Public API

    /// Lists stations available to the vineyard's stored credentials.
    static func fetchStations(vineyardId: UUID) async throws -> [DavisStation] {
        let json = try await invoke(
            payload: [
                "vineyardId": vineyardId.uuidString,
                "action": "stations",
            ]
        )
        guard let arr = json["stations"] as? [[String: Any]] else {
            throw VineyardDavisProxyError.decoding("Missing 'stations' array")
        }
        return arr.compactMap(DavisWeatherLinkService.parseStationDict)
    }

    /// Test-connection variant for owner/manager who is verifying a key
    /// pair *before* saving it to the vineyard integration. The proxy
    /// only honours this for owner/manager callers.
    static func testConnection(
        vineyardId: UUID,
        apiKey: String,
        apiSecret: String
    ) async throws -> [DavisStation] {
        let json = try await invoke(
            payload: [
                "vineyardId": vineyardId.uuidString,
                "action": "test",
                "apiKey": apiKey,
                "apiSecret": apiSecret,
            ]
        )
        guard let arr = json["stations"] as? [[String: Any]] else {
            throw VineyardDavisProxyError.decoding("Missing 'stations' array")
        }
        return arr.compactMap(DavisWeatherLinkService.parseStationDict)
    }

    /// Fetches the latest current conditions + sensor summary for the
    /// vineyard's selected (or supplied) station.
    static func fetchCurrentConditions(
        vineyardId: UUID,
        stationId: String
    ) async throws -> DavisCurrentConditions {
        let result = try await fetchCurrentConditionsWithDiagnostics(
            vineyardId: vineyardId, stationId: stationId
        )
        return result.conditions
    }

    /// Variant of ``fetchCurrentConditions(vineyardId:stationId:)`` that
    /// also returns the server-side write diagnostics. Use this from
    /// places that need to confirm `rainfall_daily` and
    /// `vineyard_weather_observations` writes succeeded (e.g. the
    /// "Refresh Davis now" button).
    static func fetchCurrentConditionsWithDiagnostics(
        vineyardId: UUID,
        stationId: String
    ) async throws -> DavisProxyCurrentResult {
        guard !stationId.isEmpty else { throw VineyardDavisProxyError.notConfigured }
        let json = try await invoke(
            payload: [
                "vineyardId": vineyardId.uuidString,
                "action": "current",
                "stationId": stationId,
            ]
        )
        let conditions = DavisWeatherLinkService.parseCurrentConditionsJSON(
            json,
            fallbackStationId: stationId
        )
        let topLevelVersion = json["_proxy_version"] as? String
        let diagnostics = parseProxyDiagnostics(json["_proxy"], topLevelVersion: topLevelVersion)
        return DavisProxyCurrentResult(conditions: conditions, diagnostics: diagnostics)
    }

    /// Parses the `_proxy` diagnostics block returned by the edge
    /// function. Returns nil when an older proxy build (no `_proxy` key)
    /// is deployed, so callers can fall back to a generic message.
    private static func parseProxyDiagnostics(
        _ raw: Any?,
        topLevelVersion: String? = nil
    ) -> DavisProxyCurrentDiagnostics? {
        guard let dict = raw as? [String: Any] else {
            // Even an old proxy without a `_proxy` block may now stamp
            // `_proxy_version` at the top level. Surface that on its own
            // so the UI can still prove which build is live.
            if let v = topLevelVersion {
                return DavisProxyCurrentDiagnostics(
                    observations: DavisProxyWriteStatus(attempted: false, success: false, code: nil, message: nil),
                    rainfallDaily: DavisProxyWriteStatus(attempted: false, success: false, code: nil, message: nil),
                    rainfallDate: nil, rainTodayMm: nil,
                    stationId: nil, stationName: nil, timezone: nil,
                    version: v
                )
            }
            return nil
        }
        func parseStatus(_ v: Any?) -> DavisProxyWriteStatus {
            let d = (v as? [String: Any]) ?? [:]
            return DavisProxyWriteStatus(
                attempted: (d["attempted"] as? Bool) ?? false,
                success: (d["success"] as? Bool) ?? false,
                code: d["code"] as? String,
                message: d["message"] as? String
            )
        }
        let obs = parseStatus(dict["observations"])
        let rainBlock = (dict["rainfall_daily"] as? [String: Any]) ?? [:]
        let rain = DavisProxyWriteStatus(
            attempted: (rainBlock["attempted"] as? Bool) ?? false,
            success: (rainBlock["success"] as? Bool) ?? false,
            code: rainBlock["code"] as? String,
            message: rainBlock["message"] as? String
        )
        let rainDate = rainBlock["date"] as? String
        let rainMm: Double? = {
            if let n = rainBlock["rain_today_mm"] as? Double { return n }
            if let n = rainBlock["rain_today_mm"] as? NSNumber { return n.doubleValue }
            return nil
        }()
        let version = (dict["version"] as? String) ?? topLevelVersion
        return DavisProxyCurrentDiagnostics(
            observations: obs,
            rainfallDaily: rain,
            rainfallDate: rainDate,
            rainTodayMm: rainMm,
            stationId: dict["station_id"] as? String,
            stationName: dict["station_name"] as? String,
            timezone: dict["timezone"] as? String,
            version: version
        )
    }

    /// Fetches archive rainfall and aggregates to daily totals (mm) using
    /// `Calendar.current`. Splits the requested window into 24h chunks to
    /// satisfy the WeatherLink v2 historic endpoint limit.
    static func fetchHistoricRainfall(
        vineyardId: UUID,
        stationId: String,
        from: Date,
        to: Date
    ) async throws -> DavisDailyRainfall {
        guard !stationId.isEmpty else { throw VineyardDavisProxyError.notConfigured }
        guard from < to else {
            return DavisDailyRainfall(
                dailyMm: [:], totalMm: 0, recordCount: 0,
                coveredFrom: from, coveredTo: to
            )
        }

        var chunks: [(start: Date, end: Date)] = []
        var cur = from
        while cur < to {
            let next = min(cur.addingTimeInterval(historicChunkSeconds), to)
            chunks.append((cur, next))
            cur = next
        }

        var perRecord: [(ts: Date, mm: Double)] = []
        for chunk in chunks {
            let json = try await invoke(
                payload: [
                    "vineyardId": vineyardId.uuidString,
                    "action": "historic",
                    "stationId": stationId,
                    "startEpoch": Int(chunk.start.timeIntervalSince1970),
                    "endEpoch": Int(chunk.end.timeIntervalSince1970),
                ]
            )
            guard let sensors = json["sensors"] as? [[String: Any]] else {
                throw VineyardDavisProxyError.decoding("Missing 'sensors' array in historic")
            }
            let parsed = DavisWeatherLinkService.parseHistoricRainfall(sensorsArr: sensors)
            for (d, mm) in parsed { perRecord.append((d, mm)) }
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

    // MARK: - Internals

    /// Posts `payload` as JSON to the davis-proxy edge function and returns
    /// the parsed response object. Throws a typed
    /// `VineyardDavisProxyError` so callers can render appropriate UX.
    private static func invoke(
        payload: [String: Any]
    ) async throws -> [String: Any] {
        let provider = SupabaseClientProvider.shared
        guard provider.isConfigured else {
            throw VineyardDavisProxyError.network("Backend not configured")
        }

        let base = AppConfig.supabaseURL.absoluteString
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/functions/v1/\(functionName)") else {
            throw VineyardDavisProxyError.network("Invalid edge function URL")
        }

        // Caller JWT (if signed in). The edge function rejects anonymous
        // access, so we surface a clearer "not authenticated" error when
        // we can't get a session token.
        let session = try? await provider.client.auth.session
        guard let token = session?.accessToken, !token.isEmpty else {
            print("[DavisProxy] notAuthenticated action=\(payload["action"] as? String ?? "-") vineyardId=\(payload["vineyardId"] as? String ?? "-")")
            throw VineyardDavisProxyError.notAuthenticated
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            throw VineyardDavisProxyError.decoding("Could not encode request body")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw VineyardDavisProxyError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw VineyardDavisProxyError.network("No HTTP response")
        }

        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let errorMessage = body["error"] as? String

        let action = payload["action"] as? String ?? "-"
        let vid = payload["vineyardId"] as? String ?? "-"
        let stationId = payload["stationId"] as? String ?? "-"
        switch http.statusCode {
        case 200..<300:
            print("[DavisProxy] vineyardId=\(vid) provider=davis action=\(action) stationId=\(stationId) result=success status=\(http.statusCode)")
            return body
        case 401:
            print("[DavisProxy] vineyardId=\(vid) provider=davis action=\(action) result=fail status=401 reason=notAuthenticated")
            throw VineyardDavisProxyError.notAuthenticated
        case 403:
            print("[DavisProxy] vineyardId=\(vid) provider=davis action=\(action) result=fail status=403 reason=forbidden")
            throw VineyardDavisProxyError.forbidden(errorMessage ?? "")
        case 404:
            print("[DavisProxy] vineyardId=\(vid) provider=davis action=\(action) result=fail status=404 reason=notConfigured")
            throw VineyardDavisProxyError.notConfigured
        case 429:
            print("[DavisProxy] vineyardId=\(vid) provider=davis action=\(action) result=fail status=429 reason=rateLimited")
            throw VineyardDavisProxyError.rateLimited
        default:
            print("[DavisProxy] vineyardId=\(vid) provider=davis action=\(action) result=fail status=\(http.statusCode)")
            throw VineyardDavisProxyError.http(http.statusCode, errorMessage)
        }
    }
}
