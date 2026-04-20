import Foundation

enum AccessibilityIDs {
    static let accountsList = "accounts.list"
    static let auditTrailList = "audit-trail.list"
    static let syncStatusLastRun = "sync-status.last-run"
    static let syncStatusPendingCount = "sync-status.pending-count"
    static let syncStatusFailedCount = "sync-status.failed-count"
    static let syncPollIntervalStepper = "settings.sync.poll-interval"
    static let appleCalendarConnectionStatusLabel = "apple-calendar.connection-status"
    static let appleCalendarStatusLabel = "apple-calendar.status"
    static let appleCalendarMessageLabel = "apple-calendar.message"
    static let appleCalendarConnectButton = "apple-calendar.connect"
    static let appleCalendarDisconnectButton = "apple-calendar.disconnect"
    static let appleCalendarOpenSettingsButton = "apple-calendar.open-settings"
    static let appleCalendarRefreshButton = "apple-calendar.refresh"
    static let appleCalendarPicker = "apple-calendar.picker"
    static let appleCalendarCreateButton = "apple-calendar.create"
    static let appleCalendarDeleteButton = "apple-calendar.delete"
    static let appleCalendarLastEventLabel = "apple-calendar.last-event"
    static let googleAuthStatusLabel = "google-auth.status"
    static let googleAuthConnectedAccountLabel = "google-auth.connected-account"
    static let googleAuthMessageLabel = "google-auth.message"
    static let googleAuthResolutionWarning = "google-auth.resolution-warning"
    static let googleAuthConnectButton = "google-auth.connect"
    static let googleCalendarStatusLabel = "google-calendar.status"
    static let googleCalendarLiveSmokeStatusLabel = "google-calendar.live-smoke-status"
    static let googleOAuthUseCustomToggle = "settings.advanced.google-oauth.use-custom"
    static let googleOAuthClientIDField = "settings.advanced.google-oauth.client-id"
    static let googleOAuthServerClientIDField = "settings.advanced.google-oauth.server-client-id"
    static let mirrorPreviewList = "mirror-preview.list"
    static let mirrorPreviewBusyLabel = "mirror-preview.busy-label"

    static func accountRow(_ id: String) -> String {
        "calendar-picker.account.\(sanitized(id))"
    }

    static func calendarRow(_ id: String) -> String {
        "calendar-picker.calendar.\(sanitized(id))"
    }

    static func mirrorPreviewRow(_ id: String) -> String {
        "mirror-preview.row.\(sanitized(id))"
    }

    static func googleAccountCard(_ id: String) -> String {
        "google-account.card.\(sanitized(id))"
    }

    static func googleAuthDisconnectButton(_ id: String) -> String {
        "google-auth.disconnect.\(sanitized(id))"
    }

    static func googleAccountPrimaryButton(_ id: String) -> String {
        "google-account.primary.\(sanitized(id))"
    }

    static func googleCalendarMessageLabel(_ id: String) -> String {
        "google-calendar.message.\(sanitized(id))"
    }

    static func googleCalendarRefreshButton(_ id: String) -> String {
        "google-calendar.refresh.\(sanitized(id))"
    }

    static func googleCalendarPicker(_ id: String) -> String {
        "google-calendar.picker.\(sanitized(id))"
    }

    static func googleCalendarCreateButton(_ id: String) -> String {
        "google-calendar.create.\(sanitized(id))"
    }

    static func googleCalendarDeleteButton(_ id: String) -> String {
        "google-calendar.delete.\(sanitized(id))"
    }

    static func googleCalendarLastEventLabel(_ id: String) -> String {
        "google-calendar.last-event.\(sanitized(id))"
    }

    private static func sanitized(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"[^A-Za-z0-9]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
