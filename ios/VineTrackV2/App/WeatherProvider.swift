import Foundation

/// Weather data source providers available to the user.
nonisolated enum WeatherProvider: String, Codable, Sendable, CaseIterable, Identifiable {
    case automatic
    case wunderground
    case davis

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic: return "Automatic Forecast"
        case .wunderground: return "Weather Underground PWS"
        case .davis: return "Davis WeatherLink"
        }
    }

    var shortName: String {
        switch self {
        case .automatic: return "Automatic Forecast"
        case .wunderground: return "Weather Underground"
        case .davis: return "Davis WeatherLink"
        }
    }

    var symbol: String {
        switch self {
        case .automatic: return "cloud.sun.fill"
        case .wunderground: return "antenna.radiowaves.left.and.right"
        case .davis: return "sensor.tag.radiowaves.forward.fill"
        }
    }

    var helpCopy: String {
        switch self {
        case .automatic:
            return "No setup required. Uses forecast weather based on vineyard location."
        case .wunderground:
            return "Uses your selected nearby PWS for current/local observations where available."
        case .davis:
            return "Connect your Davis WeatherLink account to use your own station data. If leaf wetness sensors are available, disease risk can use measured wetness instead of estimated wetness."
        }
    }
}

/// Per-vineyard provider configuration, persisted via UserDefaults
/// (non-secret fields only). Davis credentials live in the Keychain.
nonisolated struct WeatherProviderConfig: Codable, Sendable, Equatable {
    var provider: WeatherProvider = .automatic
    var davisStationId: String? = nil
    var davisStationName: String? = nil
    var davisHasCredentials: Bool = false
    var davisLastTestSuccess: Date? = nil
    var davisLastTestError: String? = nil
    var davisDetectedSensors: [String] = []
    var davisHasLeafWetnessSensor: Bool = false
    var davisConnectionTested: Bool = false
    var davisAvailableStations: [DavisStation] = []
    var lastSuccessfulUpdate: Date? = nil

    static let `default` = WeatherProviderConfig()
}

@MainActor
final class WeatherProviderStore {
    static let shared = WeatherProviderStore()

    private let defaults = UserDefaults.standard

    private func key(for vineyardId: UUID) -> String {
        "VineTrack.WeatherProviderConfig.\(vineyardId.uuidString)"
    }

    func config(for vineyardId: UUID) -> WeatherProviderConfig {
        guard let data = defaults.data(forKey: key(for: vineyardId)),
              let cfg = try? JSONDecoder().decode(WeatherProviderConfig.self, from: data)
        else {
            return .default
        }
        return cfg
    }

    func save(_ config: WeatherProviderConfig, for vineyardId: UUID) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        defaults.set(data, forKey: key(for: vineyardId))
    }
}
