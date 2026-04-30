import Foundation

nonisolated enum BackendRole: String, Codable, CaseIterable, Sendable {
    case owner
    case manager
    case supervisor
    case `operator`

    var canViewFinancials: Bool {
        switch self {
        case .owner, .manager:
            true
        case .supervisor, .operator:
            false
        }
    }

    var canChangeSettings: Bool {
        switch self {
        case .owner, .manager:
            true
        case .supervisor, .operator:
            false
        }
    }

    var canDeleteOperationalRecords: Bool {
        switch self {
        case .owner, .manager, .supervisor:
            true
        case .operator:
            false
        }
    }

    var canInviteMembers: Bool {
        switch self {
        case .owner, .manager:
            true
        case .supervisor, .operator:
            false
        }
    }

    var canExportFinancialReports: Bool {
        switch self {
        case .owner, .manager:
            true
        case .supervisor, .operator:
            false
        }
    }

    var canManageBilling: Bool {
        switch self {
        case .owner, .manager:
            true
        case .supervisor, .operator:
            false
        }
    }

    var canEditRecords: Bool {
        switch self {
        case .owner, .manager, .supervisor, .operator:
            true
        }
    }

    var canCreateOperationalRecords: Bool {
        switch self {
        case .owner, .manager, .supervisor, .operator:
            true
        }
    }
}
