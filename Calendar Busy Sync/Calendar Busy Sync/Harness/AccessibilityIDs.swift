import Foundation

enum AccessibilityIDs {
    static let auditTrailList = "audit-trail.list"
    static let auditTrailOpenButton = "audit-trail.open"
    static let menuBarOpenSettingsButton = "menu-bar.open-settings"
    static let menuBarOpenLogsButton = "menu-bar.open-logs"
    static let menuBarLaunchAtLoginToggle = "menu-bar.launch-at-login"
    static let menuBarSyncNowButton = "menu-bar.sync-now"
    static let menuBarQuitButton = "menu-bar.quit"
    static let syncStatusPendingCount = "sync-status.pending-count"
    static let syncStatusFailedCount = "sync-status.failed-count"
    static let syncStatusDetail = "sync-status.detail"
    static let syncNowButton = "sync-status.sync-now"
    static let syncPollIntervalStepper = "settings.sync.poll-interval"
    static let appleCalendarStatusLabel = "apple-calendar.status"
    static let appleCalendarMessageLabel = "apple-calendar.message"
    static let appleCalendarConnectButton = "apple-calendar.connect"
    static let appleCalendarDisconnectButton = "apple-calendar.disconnect"
    static let appleCalendarOpenSettingsButton = "apple-calendar.open-settings"
    static let appleCalendarRefreshButton = "apple-calendar.refresh"
    static let appleCalendarPicker = "apple-calendar.picker"
    static let googleAuthMessageLabel = "google-auth.message"
    static let googleAuthResolutionWarning = "google-auth.resolution-warning"
    static let googleAuthConnectButton = "google-auth.connect"
    static let googleCalendarStatusLabel = "google-calendar.status"
    static let googleCalendarLiveSmokeStatusLabel = "google-calendar.live-smoke-status"
    static let sharedConfigurationToggle = "settings.advanced.shared-configuration.enabled"
    static let googleOAuthUseCustomToggle = "settings.advanced.google-oauth.use-custom"
    static let googleOAuthClientIDField = "settings.advanced.google-oauth.client-id"
    static let googleOAuthServerClientIDField = "settings.advanced.google-oauth.server-client-id"
    static let mirrorPreviewList = "mirror-preview.list"
    static let mirrorPreviewBusyLabel = "mirror-preview.busy-label"

    static func mirrorPreviewRow(_ id: String) -> String {
        "mirror-preview.row.\(sanitized(id))"
    }

    static func googleAccountCard(_ id: String) -> String {
        "google-account.card.\(sanitized(id))"
    }

    static func googleAuthDisconnectButton(_ id: String) -> String {
        "google-auth.disconnect.\(sanitized(id))"
    }

    static func googleAuthConnectSharedButton(_ id: String) -> String {
        "google-auth.connect-shared.\(sanitized(id))"
    }

    static func googleAuthRemoveSharedButton(_ id: String) -> String {
        "google-auth.remove-shared.\(sanitized(id))"
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

    private static func sanitized(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"[^A-Za-z0-9]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
