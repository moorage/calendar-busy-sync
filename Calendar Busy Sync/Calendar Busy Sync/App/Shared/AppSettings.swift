import Foundation

enum AuditTrailLogLength: String, CaseIterable, Codable, Identifiable {
    case last1000
    case last5000
    case last10000
    case unlimited

    var id: String { rawValue }

    var displayLabel: String {
        switch self {
        case .last1000:
            return "Last 1000 events"
        case .last5000:
            return "Last 5000 events"
        case .last10000:
            return "Last 10000 events"
        case .unlimited:
            return "Unlimited"
        }
    }

    var limit: Int? {
        switch self {
        case .last1000:
            return 1000
        case .last5000:
            return 5000
        case .last10000:
            return 10000
        case .unlimited:
            return nil
        }
    }

    static func defaultValue(for platform: HarnessPlatformTarget) -> AuditTrailLogLength {
        switch platform {
        case .macos:
            return .unlimited
        case .ios:
            return .last1000
        }
    }
}

enum AppSettingsDefaults {
    static let pollIntervalMinutes = 2
}

struct GoogleOAuthOverrideConfiguration: Equatable {
    var usesCustomApp = false
    var clientID = ""
    var serverClientID = ""

    var modeSummary: String {
        usesCustomApp ? "Custom Google OAuth app" : "Shared default Google OAuth app"
    }
}
