import Foundation

enum AccessibilityIDs {
    static let auditTrailScreen = "audit-trail.screen"
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
    static let syncStatusOverflowButton = "sync-status.overflow"
    static let syncStatusOverflowSheet = "sync-status.overflow-sheet"
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
    static let sharedConfigurationStatusLabel = "settings.advanced.shared-configuration.status"
    static let sharedConfigurationDetailLabel = "settings.advanced.shared-configuration.detail"
    static let sharedConfigurationSyncNowButton = "settings.advanced.shared-configuration.sync-now"
    static let iosBackgroundRefreshStatusLabel = "settings.advanced.ios-background-refresh.status"
    static let iosBackgroundRefreshDetailLabel = "settings.advanced.ios-background-refresh.detail"
    static let iosBackgroundRefreshRunNowButton = "settings.advanced.ios-background-refresh.run-now"
    static let bookingSection = "settings.booking.section"
    static let bookingSubtitleLabel = "settings.booking.subtitle"
    static let bookingSetupButton = "settings.booking.setup"
    static let bookingPageStatusLabel = "settings.booking.page.status"
    static let bookingInboxStatusLabel = "settings.booking.inbox.status"
    static let bookingRequestsStatusLabel = "settings.booking.requests.status"
    static let bookingMessageLabel = "settings.booking.message"
    static let bookingPageURLField = "settings.booking.page-url"
    static let bookingOpenPageButton = "settings.booking.page.open"
    static let bookingCopyPageURLButton = "settings.booking.page.copy-url"
    static let bookingAppointmentTypePicker = "settings.booking.appointment-type"
    static let bookingAutomaticApprovalToggle = "settings.booking.automatic-approval"
    static let bookingApprovalCalendarStatusLabel = "settings.booking.approval-calendar.status"
    static let bookingApprovalCalendarWarningLabel = "settings.booking.approval-calendar.warning"
    static let bookingInboxURLField = "settings.booking.inbox-url"
    static let bookingInboxAdminTokenField = "settings.booking.inbox-admin-token"
    static let bookingGitHubRepositoryField = "settings.booking.github.repository"
    static let bookingGitHubDeployKeyPublicKey = "settings.booking.github.deploy-key.public-key"
    static let bookingPublishButton = "settings.booking.publish"
    static let bookingCheckInboxButton = "settings.booking.check-inbox"
    static let bookingSendTestRequestButton = "settings.booking.send-test-request"
    static let bookingImportRequestsButton = "settings.booking.import-requests"
    static let bookingSettingsButton = "settings.booking.settings"
    static let bookingSettingsSheet = "booking-settings.sheet"
    static let bookingWorkspaceSectionPicker = "booking.workspace.section"
    static let bookingAddAppointmentTypeButton = "booking.appointment-types.add"
    static let bookingRequestHistoryButton = "settings.booking.request-history"
    static let bookingRequestHistorySheet = "booking-history.sheet"
    static let bookingSetupSheet = "booking-setup.sheet"
    static let bookingSetupStepPicker = "booking-setup.step-picker"
    static let bookingSetupCreateDraftButton = "booking-setup.create-draft"
    static let bookingSetupVerifyPageButton = "booking-setup.verify-page"
    static let bookingSetupCheckInboxButton = "booking-setup.check-inbox"
    static let bookingSetupSendTestButton = "booking-setup.send-test"
    static let bookingSetupImportRequestsButton = "booking-setup.import-requests"
    static let bookingSetupDoneButton = "booking-setup.done"
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

    static func bookingApproveRequestButton(_ id: String) -> String {
        "settings.booking.approve.\(sanitized(id))"
    }

    static func bookingDeclineRequestButton(_ id: String) -> String {
        "settings.booking.decline.\(sanitized(id))"
    }

    private static func sanitized(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"[^A-Za-z0-9]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
