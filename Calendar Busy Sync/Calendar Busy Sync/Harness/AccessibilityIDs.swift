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
    static let googleAuthDisconnectButton = "google-auth.disconnect"
    static let googleCalendarStatusLabel = "google-calendar.status"
    static let googleCalendarMessageLabel = "google-calendar.message"
    static let googleCalendarRefreshButton = "google-calendar.refresh"
    static let googleCalendarPicker = "google-calendar.picker"
    static let googleCalendarCreateButton = "google-calendar.create"
    static let googleCalendarDeleteButton = "google-calendar.delete"
    static let googleCalendarLastEventLabel = "google-calendar.last-event"
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

    private static func sanitized(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"[^A-Za-z0-9]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
