import Foundation

nonisolated enum AlertSeverity: String, Codable, Sendable, CaseIterable {
    case info
    case warning
    case critical

    var displayName: String {
        switch self {
        case .info: return "Info"
        case .warning: return "Warning"
        case .critical: return "Critical"
        }
    }
}

nonisolated enum AlertType: String, Codable, Sendable {
    case irrigationNeeded = "irrigation_needed"
    case agedPins = "aged_pins"
    case weatherRisk = "weather_risk"
    case sprayJobDue = "spray_job_due"
    case syncIssue = "sync_issue"
}

nonisolated enum AlertAction: String, Codable, Sendable {
    case openIrrigationAdvisor = "open_irrigation_advisor"
    case openPins = "open_pins"
    case openSprayProgram = "open_spray_program"
    case openSprayRecord = "open_spray_record"
    case openWeather = "open_weather"
}

nonisolated struct BackendAlert: Codable, Sendable, Identifiable, Hashable {
    let id: UUID
    let vineyardId: UUID
    let alertType: String
    let severity: String
    let title: String
    let message: String
    let relatedTable: String?
    let relatedId: UUID?
    let paddockId: UUID?
    let action: String?
    let dedupKey: String
    let generatedForDate: Date?
    let createdAt: Date?
    let updatedAt: Date?
    let expiresAt: Date?
    let createdBy: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case vineyardId = "vineyard_id"
        case alertType = "alert_type"
        case severity
        case title
        case message
        case relatedTable = "related_table"
        case relatedId = "related_id"
        case paddockId = "paddock_id"
        case action
        case dedupKey = "dedup_key"
        case generatedForDate = "generated_for_date"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case expiresAt = "expires_at"
        case createdBy = "created_by"
    }

    var typedSeverity: AlertSeverity { AlertSeverity(rawValue: severity) ?? .info }
    var typedAlertType: AlertType? { AlertType(rawValue: alertType) }
    var typedAction: AlertAction? { action.flatMap { AlertAction(rawValue: $0) } }
}

nonisolated struct BackendAlertUpsert: Encodable, Sendable {
    let id: UUID
    let vineyardId: UUID
    let alertType: String
    let severity: String
    let title: String
    let message: String
    let relatedTable: String?
    let relatedId: UUID?
    let paddockId: UUID?
    let action: String?
    let dedupKey: String
    let generatedForDate: Date?
    let expiresAt: Date?
    let createdBy: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case vineyardId = "vineyard_id"
        case alertType = "alert_type"
        case severity
        case title
        case message
        case relatedTable = "related_table"
        case relatedId = "related_id"
        case paddockId = "paddock_id"
        case action
        case dedupKey = "dedup_key"
        case generatedForDate = "generated_for_date"
        case expiresAt = "expires_at"
        case createdBy = "created_by"
    }
}

nonisolated struct BackendAlertUserStatus: Codable, Sendable, Hashable {
    let alertId: UUID
    let userId: UUID
    let readAt: Date?
    let dismissedAt: Date?

    enum CodingKeys: String, CodingKey {
        case alertId = "alert_id"
        case userId = "user_id"
        case readAt = "read_at"
        case dismissedAt = "dismissed_at"
    }
}

nonisolated struct BackendAlertPreferences: Codable, Sendable, Hashable {
    let vineyardId: UUID
    var irrigationAlertsEnabled: Bool
    var irrigationForecastDays: Int
    var irrigationDeficitThresholdMm: Double
    var agedPinAlertsEnabled: Bool
    var agedPinDays: Int
    var weatherAlertsEnabled: Bool
    var rainAlertThresholdMm: Double
    var windAlertThresholdKmh: Double
    var frostAlertThresholdC: Double
    var heatAlertThresholdC: Double
    var sprayJobRemindersEnabled: Bool
    var pushEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case vineyardId = "vineyard_id"
        case irrigationAlertsEnabled = "irrigation_alerts_enabled"
        case irrigationForecastDays = "irrigation_forecast_days"
        case irrigationDeficitThresholdMm = "irrigation_deficit_threshold_mm"
        case agedPinAlertsEnabled = "aged_pin_alerts_enabled"
        case agedPinDays = "aged_pin_days"
        case weatherAlertsEnabled = "weather_alerts_enabled"
        case rainAlertThresholdMm = "rain_alert_threshold_mm"
        case windAlertThresholdKmh = "wind_alert_threshold_kmh"
        case frostAlertThresholdC = "frost_alert_threshold_c"
        case heatAlertThresholdC = "heat_alert_threshold_c"
        case sprayJobRemindersEnabled = "spray_job_reminders_enabled"
        case pushEnabled = "push_enabled"
    }

    static func defaults(for vineyardId: UUID) -> BackendAlertPreferences {
        BackendAlertPreferences(
            vineyardId: vineyardId,
            irrigationAlertsEnabled: true,
            irrigationForecastDays: 5,
            irrigationDeficitThresholdMm: 8,
            agedPinAlertsEnabled: true,
            agedPinDays: 14,
            weatherAlertsEnabled: true,
            rainAlertThresholdMm: 5,
            windAlertThresholdKmh: 25,
            frostAlertThresholdC: 1,
            heatAlertThresholdC: 35,
            sprayJobRemindersEnabled: true,
            pushEnabled: false
        )
    }
}

/// Combined view-model for the UI: alert + user-specific status.
nonisolated struct AlertWithStatus: Sendable, Identifiable, Hashable {
    let alert: BackendAlert
    let status: BackendAlertUserStatus?

    var id: UUID { alert.id }
    var isRead: Bool { status?.readAt != nil }
    var isDismissed: Bool { status?.dismissedAt != nil }
}
