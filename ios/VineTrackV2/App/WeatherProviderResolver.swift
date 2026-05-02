import Foundation

/// Computed view of the active weather data source for UI labels.
nonisolated struct WeatherSourceStatus: Sendable, Equatable {
    enum Quality: String, Sendable, Equatable {
        case forecastOnly
        case localStation
        case localStationWithMeasuredWetness

        var displayName: String {
            switch self {
            case .forecastOnly: return "Forecast only"
            case .localStation: return "Local station"
            case .localStationWithMeasuredWetness: return "Local station + measured wetness"
            }
        }
    }

    let provider: WeatherProvider
    let quality: Quality
    let primaryLabel: String
    let detailLabel: String
    let lastUpdated: Date?

    /// One-line label for use in advisor / spray screens.
    var compactLabel: String {
        switch provider {
        case .automatic:
            return "Forecast source: Automatic Forecast"
        case .wunderground:
            return "Local data: Weather Underground + forecast"
        case .davis:
            return quality == .localStationWithMeasuredWetness
                ? "Local data: Davis WeatherLink + forecast (measured wetness)"
                : "Local data: Davis WeatherLink + forecast"
        }
    }
}

@MainActor
enum WeatherProviderResolver {

    /// Resolves the effective provider from the saved config.
    /// Falls back to `.automatic` if a configured provider lacks required setup.
    static func resolve(for vineyardId: UUID, weatherStationId: String?) -> WeatherSourceStatus {
        let cfg = WeatherProviderStore.shared.config(for: vineyardId)

        switch cfg.provider {
        case .davis:
            if cfg.davisHasCredentials {
                let quality: WeatherSourceStatus.Quality =
                    cfg.davisHasLeafWetnessSensor ? .localStationWithMeasuredWetness : .localStation
                return WeatherSourceStatus(
                    provider: .davis,
                    quality: quality,
                    primaryLabel: "Davis WeatherLink",
                    detailLabel: cfg.davisStationId ?? "Davis station",
                    lastUpdated: cfg.lastSuccessfulUpdate
                )
            }
            // Fall back to automatic if creds missing.
            return automatic(lastUpdated: cfg.lastSuccessfulUpdate)

        case .wunderground:
            if let station = weatherStationId, !station.isEmpty {
                return WeatherSourceStatus(
                    provider: .wunderground,
                    quality: .localStation,
                    primaryLabel: "Weather Underground",
                    detailLabel: station,
                    lastUpdated: cfg.lastSuccessfulUpdate
                )
            }
            return automatic(lastUpdated: cfg.lastSuccessfulUpdate)

        case .automatic:
            return automatic(lastUpdated: cfg.lastSuccessfulUpdate)
        }
    }

    private static func automatic(lastUpdated: Date?) -> WeatherSourceStatus {
        WeatherSourceStatus(
            provider: .automatic,
            quality: .forecastOnly,
            primaryLabel: "Automatic Forecast",
            detailLabel: "Based on vineyard location",
            lastUpdated: lastUpdated
        )
    }
}
