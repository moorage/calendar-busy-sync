import Combine
import Foundation

enum LiveGoogleSmokeStatus: Equatable {
    case idle
    case awaitingAuthentication
    case running(String)
    case passed(String)
    case failed(String)

    var summary: String? {
        switch self {
        case .idle:
            return nil
        case .awaitingAuthentication:
            return "Waiting for Google sign-in"
        case let .running(message), let .passed(message), let .failed(message):
            return message
        }
    }

    var statusLabel: String? {
        switch self {
        case .idle:
            return nil
        case .awaitingAuthentication:
            return "Pending"
        case .running:
            return "Running"
        case .passed:
            return "Passed"
        case .failed:
            return "Failed"
        }
    }
}

private enum BookingCalendarTargetProvider: String {
    case automatic
    case apple
    case google
}

struct BookingCalendarTargetOption: Identifiable, Equatable {
    var id: String
    var label: String
    var detail: String

    static func apple(calendarID: String) -> String {
        "apple|\(calendarID)"
    }

    static func google(accountID: String, calendarID: String) -> String {
        "google|\(accountID)|\(calendarID)"
    }
}

private struct BookingSiteBuildWriteResult {
    var writtenFileCount: Int
    var busyIntervalCount: Int
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var state: ScenarioState?
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var defaultGoogleOAuthConfiguration: DefaultGoogleOAuthConfiguration?
    @Published private(set) var googleOAuthResolution: GoogleOAuthConfigurationResolution = .invalid(
        message: "Google OAuth configuration has not been loaded yet."
    )
    @Published private(set) var appleCalendarAuthorizationState: AppleCalendarAuthorizationState
    @Published private(set) var isAppleCalendarEnabled: Bool
    @Published private(set) var appleCalendarMessage: String? {
        didSet {
            appleCalendarMessageUpdatedAt = appleCalendarMessage == nil ? nil : Date()
            if let appleCalendarMessage, appleCalendarMessage != oldValue {
                appendAuditTrailEntry(
                    title: "Apple / iCloud calendar",
                    detail: appleCalendarMessage,
                    status: isAppleCalendarOperationInFlight ? "working" : appleCalendarAuthorizationState.auditTrailStatus
                )
            }
        }
    }
    @Published private(set) var appleCalendarMessageUpdatedAt: Date?
    @Published private(set) var appleCalendars: [AppleCalendarSummary] = []
    @Published private(set) var lastManagedAppleEvent: AppleManagedEventRecord?
    @Published private(set) var isAppleCalendarOperationInFlight = false
    @Published private(set) var googleStoredAccounts: [StoredGoogleAccount] = []
    @Published private(set) var googleAuthMessage: String? {
        didSet {
            googleAuthMessageUpdatedAt = googleAuthMessage == nil ? nil : Date()
            if let googleAuthMessage, googleAuthMessage != oldValue {
                appendAuditTrailEntry(
                    title: "Google account",
                    detail: googleAuthMessage,
                    status: isGoogleAuthInFlight ? "working" : "ready"
                )
            }
        }
    }
    @Published private(set) var googleAuthMessageUpdatedAt: Date?
    @Published private(set) var isGoogleAuthInFlight = false
    @Published private(set) var googleCalendarsByAccountID: [String: [GoogleCalendarSummary]] = [:]
    @Published private(set) var googleMessagesByAccountID: [String: String] = [:]
    @Published private(set) var googleMessageUpdatedAtByAccountID: [String: Date] = [:]
    @Published private(set) var lastManagedGoogleEventsByAccountID: [String: GoogleManagedEventRecord] = [:]
    @Published private(set) var googleOperationAccountIDs: Set<String> = []
    @Published private(set) var activeGoogleAccountID: String?
    @Published private(set) var sharedGoogleAccountDescriptors: [SharedGoogleAccountDescriptor] = []
    @Published private(set) var liveGoogleSmokeStatus: LiveGoogleSmokeStatus = .idle
    @Published private(set) var isSyncInFlight = false
    @Published private(set) var lastBusyMirrorSyncSummary: BusyMirrorSyncSummary?
    @Published private(set) var syncMessage: String?
    @Published private(set) var sharedConfigurationSyncState: SharedConfigurationSyncState
    @Published private(set) var runtimeAuditTrailEntries: [AuditTrailEntry] = []
    @Published private(set) var iosBackgroundRefreshState: IOSBackgroundRefreshState
    @Published private(set) var bookingSetupSnapshot: BookingSetupSnapshot
    @Published private(set) var bookingLastGeneratedFingerprintString: String
    @Published private(set) var bookingLastServedFingerprintString: String
    @Published private(set) var bookingLastGeneratedAt: Date?
    @Published private(set) var bookingLastUploadedAt: Date?
    @Published private(set) var bookingLastVerifiedAt: Date?
    @Published private(set) var isBookingTestRequestInFlight = false
    @Published private(set) var isBookingImportInFlight = false
    @Published private(set) var isBookingApprovalInFlight = false
    @Published private(set) var isBookingVercelDeploymentInFlight = false
    @Published private(set) var bookingAvailabilityPublishSummary: String?
    @Published private(set) var importedBookingRequests: [BookingImportedRequest] = []
    @Published private(set) var bookingAppointmentTypes: [BookingAppointmentType] = []
    @Published var pollIntervalMinutes: Int {
        didSet {
            guard !isApplyingSharedConfiguration else { return }
            persistSettings()
            restartSyncLoopIfNeeded()
        }
    }
    @Published var auditTrailLogLength: AuditTrailLogLength {
        didSet {
            guard !isApplyingSharedConfiguration else { return }
            persistSettings()
            trimAuditTrailEntriesIfNeeded()
        }
    }
    @Published var usesCustomGoogleOAuthApp: Bool {
        didSet {
            guard !isApplyingSharedConfiguration else { return }
            persistSettingsAndRefreshGoogleConfiguration()
        }
    }
    @Published var isSharedConfigurationEnabled: Bool {
        didSet {
            guard !isApplyingSharedConfiguration else { return }
            handleSharedConfigurationEnabledChange(from: oldValue, to: isSharedConfigurationEnabled)
        }
    }
    @Published var customGoogleOAuthClientID: String {
        didSet {
            guard !isApplyingSharedConfiguration else { return }
            persistSettingsAndRefreshGoogleConfiguration()
        }
    }
    @Published var customGoogleOAuthServerClientID: String {
        didSet {
            guard !isApplyingSharedConfiguration else { return }
            persistSettingsAndRefreshGoogleConfiguration()
        }
    }
    @Published var bookingPageURLString: String {
        didSet {
            persistBookingSettings()
        }
    }
    @Published var bookingInboxURLString: String {
        didSet {
            persistBookingSettings()
            markBookingInboxConfigured(oldValue: oldValue, newValue: bookingInboxURLString)
        }
    }
    @Published var bookingInboxAdminTokenString: String {
        didSet {
            persistBookingAdminToken()
        }
    }
    @Published var bookingGitHubRepositoryString: String {
        didSet {
            persistBookingSettings()
        }
    }
    @Published var bookingGitHubBranchString: String {
        didSet {
            persistBookingSettings()
        }
    }
    @Published private(set) var bookingGitHubDeployKeyPublicKeyString: String
    @Published private(set) var bookingGitHubDeployKeyFingerprintString: String
    @Published private(set) var bookingGitHubDeployKeyRepositoryString: String
    @Published private(set) var bookingGitHubDeployKeyVerifiedAt: Date?
    @Published var bookingVercelScopeString: String {
        didSet {
            persistBookingSettings()
        }
    }
    @Published var bookingVercelProjectNameString: String {
        didSet {
            persistBookingSettings()
        }
    }
    @Published var bookingVercelTokenString: String {
        didSet {
            persistBookingVercelToken()
        }
    }
    @Published var bookingPublicNameString: String {
        didSet {
            persistBookingSettings()
            markBookingCustomizationChanged(oldValue: oldValue, newValue: bookingPublicNameString)
        }
    }
    @Published var bookingPageTitleString: String {
        didSet {
            persistBookingSettings()
            markBookingCustomizationChanged(oldValue: oldValue, newValue: bookingPageTitleString)
        }
    }
    @Published var bookingPageSubtitleString: String {
        didSet {
            persistBookingSettings()
            markBookingCustomizationChanged(oldValue: oldValue, newValue: bookingPageSubtitleString)
        }
    }
    @Published var bookingTimeZoneIdentifierString: String {
        didSet {
            persistBookingSettings()
            markBookingCustomizationChanged(oldValue: oldValue, newValue: bookingTimeZoneIdentifierString)
        }
    }
    @Published var bookingThemeAccentColorString: String {
        didSet {
            persistBookingSettings()
            markBookingCustomizationChanged(oldValue: oldValue, newValue: bookingThemeAccentColorString)
        }
    }
    @Published var bookingThemeBackgroundColorString: String {
        didSet {
            persistBookingSettings()
            markBookingCustomizationChanged(oldValue: oldValue, newValue: bookingThemeBackgroundColorString)
        }
    }
    @Published var bookingThemeTextColorString: String {
        didSet {
            persistBookingSettings()
            markBookingCustomizationChanged(oldValue: oldValue, newValue: bookingThemeTextColorString)
        }
    }
    @Published var bookingCalendarTargetProviderString: String {
        didSet {
            persistBookingSettings()
        }
    }
    @Published var bookingAppleTargetCalendarIDString: String {
        didSet {
            persistBookingSettings()
        }
    }
    @Published var bookingGoogleTargetAccountIDString: String {
        didSet {
            persistBookingSettings()
        }
    }
    @Published var bookingGoogleTargetCalendarIDString: String {
        didSet {
            persistBookingSettings()
        }
    }
    @Published var selectedBookingAppointmentTypeIDString: String {
        didSet {
            persistBookingSettings()
        }
    }
    @Published var isAutomaticBookingApprovalEnabled: Bool {
        didSet {
            persistBookingSettings()
        }
    }
    @Published var selectedAppleCalendarID: String {
        didSet {
            guard !isApplyingSharedConfiguration else { return }
            persistSettings()

            guard hasPrepared, selectedAppleCalendarID != oldValue else { return }
            let previousCalendarID = oldValue
            let nextCalendarID = selectedAppleCalendarID
            Task { @MainActor [weak self] in
                await self?.handleAppleCalendarSelectionChange(
                    from: previousCalendarID,
                    to: nextCalendarID
                )
            }
        }
    }
    @Published private(set) var googleSelectedCalendarIDs: [String: String]

    let launchOptions: HarnessLaunchOptions

    private let loader: ScenarioLoader
    private let fileManager: FileManager
    private let launchDate: Date
    private let userDefaults: UserDefaults
    private let sharedConfigurationStore: any SharedAppConfigurationStoring
    private let iosBackgroundRefreshScheduler: any IOSBackgroundRefreshScheduling
    private let appleCalendarService: any AppleCalendarProviding
    private let appleCalendarSettingsOpener: any AppleCalendarSettingsOpening
    private let bookingSecretStore: any BookingSecretStoring
    private let bookingInviteFileWriter: any BookingInviteFileWriting
    private let googleCalendarService: GoogleCalendarService
    private let googleAccountStore: any GoogleAccountStoring
    private let googleSignInEnvironment: GoogleSignInEnvironment
    private let liveGoogleDebugConfiguration: LiveGoogleDebugConfiguration
    private let iosBackgroundRefreshDebugConfiguration: IOSBackgroundRefreshDebugConfiguration
    private var hasPrepared = false
    private var hasAttemptedLiveGoogleSmoke = false
    private var syncLoopTask: Task<Void, Never>?
    private var isBookingAvailabilityPublishInFlight = false
    private var isApplyingSharedConfiguration = false
    private var lastSettingsMutationAt: Date
    private var persistedAppleCalendarReference: SharedAppleCalendarReference?

    private enum SettingKey {
        static let pollIntervalMinutes = "settings.pollIntervalMinutes"
        static let auditTrailLogLength = "settings.auditTrailLogLength"
        static let lastModifiedAt = "settings.lastModifiedAt"
        static let isSharedConfigurationEnabled = "settings.sharedConfiguration.enabled"
        static let usesAppleCalendar = "settings.appleCalendar.enabled"
        static let selectedAppleCalendarID = "settings.appleCalendar.selectedCalendarID"
        static let selectedAppleCalendarReference = "settings.appleCalendar.selectedCalendarReference"
        static let usesCustomGoogleOAuthApp = "settings.googleOAuth.usesCustomApp"
        static let customGoogleOAuthClientID = "settings.googleOAuth.clientID"
        static let customGoogleOAuthServerClientID = "settings.googleOAuth.serverClientID"
        static let selectedGoogleCalendarIDs = "settings.googleCalendar.selectedCalendarIDs"
        static let activeGoogleAccountID = "settings.googleCalendar.activeAccountID"
        static let sharedGoogleAccountDescriptors = "settings.googleCalendar.sharedAccountDescriptors"
        static let bookingSetupSnapshot = "settings.booking.setupSnapshot"
        static let bookingLastGeneratedFingerprint = "settings.booking.lastGeneratedFingerprint"
        static let bookingLastServedFingerprint = "settings.booking.lastServedFingerprint"
        static let bookingLastGeneratedAt = "settings.booking.lastGeneratedAt"
        static let bookingLastUploadedAt = "settings.booking.lastUploadedAt"
        static let bookingLastVerifiedAt = "settings.booking.lastVerifiedAt"
        static let bookingPageURL = "settings.booking.pageURL"
        static let bookingInboxURL = "settings.booking.inboxURL"
        static let selectedBookingAppointmentTypeID = "settings.booking.selectedAppointmentTypeID"
        static let isAutomaticBookingApprovalEnabled = "settings.booking.automaticApprovalEnabled"
        static let bookingAppointmentTypes = "settings.booking.appointmentTypes"
        static let bookingPageFilesFolderPath = "settings.booking.pageFilesFolderPath"
        static let bookingGitHubRepository = "settings.booking.github.repository"
        static let bookingGitHubBranch = "settings.booking.github.branch"
        static let bookingGitHubDeployKeyPublicKey = "settings.booking.github.deployKey.publicKey"
        static let bookingGitHubDeployKeyFingerprint = "settings.booking.github.deployKey.fingerprint"
        static let bookingGitHubDeployKeyRepository = "settings.booking.github.deployKey.repository"
        static let bookingGitHubDeployKeyVerifiedAt = "settings.booking.github.deployKey.verifiedAt"
        static let bookingVercelScope = "settings.booking.vercel.scope"
        static let bookingVercelProjectName = "settings.booking.vercel.projectName"
        static let bookingPublicName = "settings.booking.publicPage.publicName"
        static let bookingPageTitle = "settings.booking.publicPage.pageTitle"
        static let bookingPageSubtitle = "settings.booking.publicPage.pageSubtitle"
        static let bookingTimeZoneIdentifier = "settings.booking.publicPage.timeZoneIdentifier"
        static let bookingThemeAccentColor = "settings.booking.publicPage.theme.accentColor"
        static let bookingThemeBackgroundColor = "settings.booking.publicPage.theme.backgroundColor"
        static let bookingThemeTextColor = "settings.booking.publicPage.theme.textColor"
        static let bookingCalendarTargetProvider = "settings.booking.calendarTarget.provider"
        static let bookingAppleTargetCalendarID = "settings.booking.calendarTarget.appleCalendarID"
        static let bookingGoogleTargetAccountID = "settings.booking.calendarTarget.googleAccountID"
        static let bookingGoogleTargetCalendarID = "settings.booking.calendarTarget.googleCalendarID"
    }

    private enum EnvironmentKey {
        static let uiTestBookingInboxAdminToken = "CALENDAR_BUSY_SYNC_UI_TEST_BOOKING_INBOX_ADMIN_TOKEN"
        static let uiTestBookingInboxAdminTokenFile = "CALENDAR_BUSY_SYNC_UI_TEST_BOOKING_INBOX_ADMIN_TOKEN_FILE"
    }

    init(
        launchOptions: HarnessLaunchOptions,
        fileManager: FileManager = .default,
        launchDate: Date = Date(),
        userDefaults: UserDefaults = .standard,
        processInfo: ProcessInfo = .processInfo,
        sharedConfigurationStore: (any SharedAppConfigurationStoring)? = nil,
        iosBackgroundRefreshScheduler: (any IOSBackgroundRefreshScheduling)? = nil,
        appleCalendarService: (any AppleCalendarProviding)? = nil,
        appleCalendarSettingsOpener: (any AppleCalendarSettingsOpening)? = nil,
        bookingSecretStore: (any BookingSecretStoring)? = nil,
        bookingInviteFileWriter: (any BookingInviteFileWriting)? = nil,
        googleCalendarService: GoogleCalendarService? = nil,
        googleAccountStore: (any GoogleAccountStoring)? = nil,
        googleSignInEnvironment: GoogleSignInEnvironment? = nil,
        liveGoogleDebugConfiguration: LiveGoogleDebugConfiguration? = nil,
        iosBackgroundRefreshDebugConfiguration: IOSBackgroundRefreshDebugConfiguration? = nil
    ) {
        let resolvedSharedConfigurationStore = sharedConfigurationStore ?? ICloudSharedAppConfigurationStore()
        let sharedConfigurationEnabled = userDefaults.object(forKey: SettingKey.isSharedConfigurationEnabled) as? Bool ?? true
        let resolvedGoogleSignInEnvironment = googleSignInEnvironment ?? GoogleSignInEnvironment.current()
        let resolvedBookingSecretStore = bookingSecretStore ?? BookingKeychainSecretStore()

        self.launchOptions = launchOptions
        self.loader = ScenarioLoader()
        self.fileManager = fileManager
        self.launchDate = launchDate
        self.userDefaults = userDefaults
        self.sharedConfigurationStore = resolvedSharedConfigurationStore
        self.iosBackgroundRefreshScheduler = iosBackgroundRefreshScheduler ?? SystemIOSBackgroundRefreshScheduler()
        let resolvedAppleCalendarService = appleCalendarService ?? AppleCalendarService()
        self.appleCalendarService = resolvedAppleCalendarService
        self.appleCalendarSettingsOpener = appleCalendarSettingsOpener ?? AppleCalendarSettingsOpener()
        self.bookingSecretStore = resolvedBookingSecretStore
        self.bookingInviteFileWriter = bookingInviteFileWriter ?? BookingInviteFileWriter()
        self.googleCalendarService = googleCalendarService ?? GoogleCalendarService()
        self.googleAccountStore = googleAccountStore ?? GoogleAccountStore()
        self.googleSignInEnvironment = resolvedGoogleSignInEnvironment
        self.liveGoogleDebugConfiguration = liveGoogleDebugConfiguration ?? LiveGoogleDebugConfiguration.from(processInfo: processInfo)
        self.iosBackgroundRefreshDebugConfiguration = iosBackgroundRefreshDebugConfiguration ?? IOSBackgroundRefreshDebugConfiguration.from(processInfo: processInfo)
        self.pollIntervalMinutes = Self.loadPollInterval(from: userDefaults)
        self.auditTrailLogLength = Self.loadAuditTrailLogLength(from: userDefaults, platform: launchOptions.platformTarget)
        self.lastSettingsMutationAt = Self.loadSettingsMutationDate(from: userDefaults)
        self.isAppleCalendarEnabled = userDefaults.object(forKey: SettingKey.usesAppleCalendar) as? Bool ?? false
        self.selectedAppleCalendarID = userDefaults.string(forKey: SettingKey.selectedAppleCalendarID) ?? ""
        self.persistedAppleCalendarReference = Self.loadAppleCalendarReference(from: userDefaults)
        self.appleCalendarAuthorizationState = resolvedAppleCalendarService.authorizationState()
        self.isSharedConfigurationEnabled = sharedConfigurationEnabled
        self.sharedConfigurationSyncState = Self.initialSharedConfigurationSyncState(
            isSharedConfigurationEnabled: sharedConfigurationEnabled,
            sharedConfigurationStore: resolvedSharedConfigurationStore
        )
        self.usesCustomGoogleOAuthApp = userDefaults.object(forKey: SettingKey.usesCustomGoogleOAuthApp) as? Bool ?? false
        self.customGoogleOAuthClientID = userDefaults.string(forKey: SettingKey.customGoogleOAuthClientID) ?? ""
        self.customGoogleOAuthServerClientID = userDefaults.string(forKey: SettingKey.customGoogleOAuthServerClientID) ?? ""
        self.googleSelectedCalendarIDs = Self.loadGoogleSelectedCalendarIDs(from: userDefaults)
        self.activeGoogleAccountID = userDefaults.string(forKey: SettingKey.activeGoogleAccountID)
        self.sharedGoogleAccountDescriptors = Self.loadSharedGoogleAccountDescriptors(from: userDefaults)
        self.bookingSetupSnapshot = Self.loadBookingSetupSnapshot(from: userDefaults)
        self.bookingLastGeneratedFingerprintString = userDefaults.string(forKey: SettingKey.bookingLastGeneratedFingerprint) ?? ""
        self.bookingLastServedFingerprintString = userDefaults.string(forKey: SettingKey.bookingLastServedFingerprint) ?? ""
        self.bookingLastGeneratedAt = userDefaults.object(forKey: SettingKey.bookingLastGeneratedAt) as? Date
        self.bookingLastUploadedAt = userDefaults.object(forKey: SettingKey.bookingLastUploadedAt) as? Date
        self.bookingLastVerifiedAt = userDefaults.object(forKey: SettingKey.bookingLastVerifiedAt) as? Date
        let loadedBookingAppointmentTypes = Self.loadBookingAppointmentTypes(from: userDefaults)
        self.bookingAppointmentTypes = loadedBookingAppointmentTypes
        self.bookingPageURLString = userDefaults.string(forKey: SettingKey.bookingPageURL) ?? ""
        self.bookingInboxURLString = userDefaults.string(forKey: SettingKey.bookingInboxURL) ?? ""
        self.bookingGitHubRepositoryString = userDefaults.string(forKey: SettingKey.bookingGitHubRepository) ?? ""
        self.bookingGitHubBranchString = userDefaults.string(forKey: SettingKey.bookingGitHubBranch) ?? "main"
        self.bookingGitHubDeployKeyPublicKeyString = userDefaults.string(forKey: SettingKey.bookingGitHubDeployKeyPublicKey) ?? ""
        self.bookingGitHubDeployKeyFingerprintString = userDefaults.string(forKey: SettingKey.bookingGitHubDeployKeyFingerprint) ?? ""
        self.bookingGitHubDeployKeyRepositoryString = userDefaults.string(forKey: SettingKey.bookingGitHubDeployKeyRepository) ?? ""
        self.bookingGitHubDeployKeyVerifiedAt = userDefaults.object(forKey: SettingKey.bookingGitHubDeployKeyVerifiedAt) as? Date
        self.bookingVercelScopeString = userDefaults.string(forKey: SettingKey.bookingVercelScope) ?? ""
        self.bookingVercelProjectNameString = userDefaults.string(forKey: SettingKey.bookingVercelProjectName) ?? ""
        self.bookingVercelTokenString = (try? resolvedBookingSecretStore.loadVercelToken()) ?? ""
        self.bookingPublicNameString = userDefaults.string(forKey: SettingKey.bookingPublicName) ?? BookingProfile.example.publicName
        self.bookingPageTitleString = userDefaults.string(forKey: SettingKey.bookingPageTitle) ?? BookingProfile.example.pageTitle
        self.bookingPageSubtitleString = userDefaults.string(forKey: SettingKey.bookingPageSubtitle) ?? BookingProfile.example.pageSubtitle
        self.bookingTimeZoneIdentifierString = userDefaults.string(forKey: SettingKey.bookingTimeZoneIdentifier) ?? BookingProfile.example.timeZoneIdentifier
        self.bookingThemeAccentColorString = userDefaults.string(forKey: SettingKey.bookingThemeAccentColor) ?? BookingTheme.defaultValue.accentColor
        self.bookingThemeBackgroundColorString = userDefaults.string(forKey: SettingKey.bookingThemeBackgroundColor) ?? BookingTheme.defaultValue.backgroundColor
        self.bookingThemeTextColorString = userDefaults.string(forKey: SettingKey.bookingThemeTextColor) ?? BookingTheme.defaultValue.textColor
        self.bookingCalendarTargetProviderString = userDefaults.string(forKey: SettingKey.bookingCalendarTargetProvider) ?? ""
        self.bookingAppleTargetCalendarIDString = userDefaults.string(forKey: SettingKey.bookingAppleTargetCalendarID) ?? ""
        self.bookingGoogleTargetAccountIDString = userDefaults.string(forKey: SettingKey.bookingGoogleTargetAccountID) ?? ""
        self.bookingGoogleTargetCalendarIDString = userDefaults.string(forKey: SettingKey.bookingGoogleTargetCalendarID) ?? ""
        self.selectedBookingAppointmentTypeIDString = userDefaults.string(forKey: SettingKey.selectedBookingAppointmentTypeID)
            ?? loadedBookingAppointmentTypes.first?.id.rawValue
            ?? ""
        self.isAutomaticBookingApprovalEnabled = userDefaults.object(forKey: SettingKey.isAutomaticBookingApprovalEnabled) as? Bool ?? false
        let storedBookingInboxAdminToken = (try? resolvedBookingSecretStore.loadAdminToken()) ?? ""
        let uiTestBookingInboxAdminToken = Self.loadUITestBookingInboxAdminToken(
            launchOptions: launchOptions,
            processInfo: processInfo,
            fileManager: fileManager
        )
        self.bookingInboxAdminTokenString = storedBookingInboxAdminToken.isEmpty
            ? uiTestBookingInboxAdminToken.trimmingCharacters(in: .whitespacesAndNewlines)
            : storedBookingInboxAdminToken
        try? resolvedBookingSecretStore.deleteLegacyGitHubToken()
        self.iosBackgroundRefreshState = Self.initialIOSBackgroundRefreshState(
            launchOptions: launchOptions,
            scheduler: self.iosBackgroundRefreshScheduler
        )
        if self.bookingInboxAdminTokenString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           self.bookingSetupSnapshot.inboxStatus == .connected
        {
            self.bookingSetupSnapshot.inboxStatus = .reachable
        }
        if self.liveGoogleDebugConfiguration.isEnabled {
            self.liveGoogleSmokeStatus = .awaitingAuthentication
        }

        startObservingSharedConfiguration()
    }

    deinit {
        syncLoopTask?.cancel()
    }

    func prepareIfNeeded() async {
        guard !hasPrepared else { return }
        hasPrepared = true

        let scenarioLoadStart = Date()

        do {
            let loadedState = try loadInitialState()
            state = loadedState
            lastErrorMessage = nil
            let readinessDetail: String
            if launchOptions.scenarioName == nil && launchOptions.scenarioRoot == nil {
                readinessDetail = "Live settings shell is ready."
            } else {
                readinessDetail = "Loaded \(loadedState.connectedAccountCount) accounts and \(loadedState.selectedCalendarCount) selected calendars from the current scenario."
            }
            appendAuditTrailEntry(
                title: "App ready",
                detail: readinessDetail,
                status: "ready"
            )
            let readyDate = Date()
            try HarnessArtifactWriter.writeArtifacts(
                state: loadedState,
                launchOptions: launchOptions,
                launchDate: launchDate,
                scenarioLoadStartedAt: scenarioLoadStart,
                readyDate: readyDate,
                fileManager: fileManager
            )
        } catch {
            state = nil
            lastErrorMessage = error.localizedDescription
            appendAuditTrailEntry(
                title: "App startup",
                detail: error.localizedDescription,
                status: "failed"
            )
        }

        reconcileSharedConfigurationAtLaunch()
        refreshGoogleConfiguration()
        refreshAppleCalendarAuthorizationState()
        await restoreAppleCalendarAccessIfNeeded()
        await restoreGoogleAccountsIfPossible()
        restartSyncLoopIfNeeded()
        await syncNowIfReady()
        scheduleIOSBackgroundRefreshIfPossible()
        if iosBackgroundRefreshDebugConfiguration.runImmediately {
            await handleIOSBackgroundRefreshTask()
        }
    }

    var supportsPollingSettings: Bool {
        launchOptions.platformTarget == .macos
    }

    var supportsIOSBackgroundRefresh: Bool {
        launchOptions.platformTarget == .ios
            && !launchOptions.uiTestMode
            && launchOptions.appStoreScreenshotMode == nil
    }

    var usesCooperativeIOSSyncScheduling: Bool {
        launchOptions.platformTarget == .ios
    }

    var syncStatusLabel: String {
        if isSyncInFlight {
            return "Syncing…"
        }

        guard let lastBusyMirrorSyncSummary else {
            return "Waiting"
        }

        return lastBusyMirrorSyncSummary.failedCount == 0 ? "Ready" : "Needs attention"
    }

    var syncStatusDetail: String {
        if isSyncInFlight {
            return "Reconciling busy holds across all selected calendars."
        }

        if let syncMessage {
            return syncMessage
        }

        guard let lastBusyMirrorSyncSummary else {
            return "Select calendars to manage mirrored busy holds. Two or more selected calendars create new mirrors."
        }

        return "Last run created \(lastBusyMirrorSyncSummary.createdCount), updated \(lastBusyMirrorSyncSummary.updatedCount), deleted \(lastBusyMirrorSyncSummary.deletedCount), failed \(lastBusyMirrorSyncSummary.failedCount)."
    }

    var selectedCalendarSummary: String {
        let count = selectedParticipantCount
        switch count {
        case 0:
            return "No calendars selected"
        case 1:
            return "1 calendar selected"
        default:
            return "\(count) calendars selected"
        }
    }

    var setupSummary: String {
        let count = pendingActivityCount
        return count == 0 ? "All required setup is complete." : "\(count) setup item(s) still need attention."
    }

    var currentActivitySummary: String {
        if isSyncInFlight {
            return "Syncing selected calendars"
        }

        if isGoogleAuthInFlight {
            return googleStoredAccounts.isEmpty ? "Connecting Google account" : "Adding Google account"
        }

        if !googleOperationAccountIDs.isEmpty {
            let count = googleOperationAccountIDs.count
            return count == 1 ? "Updating 1 Google account" : "Updating \(count) Google accounts"
        }

        if isAppleCalendarOperationInFlight {
            return "Updating Apple calendars"
        }

        switch liveGoogleSmokeStatus {
        case .awaitingAuthentication:
            return "Waiting for Google sign-in"
        case let .running(message), let .passed(message), let .failed(message):
            return message
        case .idle:
            break
        }

        if let syncMessage {
            return syncMessage
        }

        if selectedParticipantCount == 0 {
            return "Choose calendars to sync"
        }

        if selectedParticipantCount == 1 {
            return "Add one more calendar to start mirroring"
        }

        if let lastBusyMirrorSyncSummary, lastBusyMirrorSyncSummary.failedCount > 0 {
            return "Last sync completed with failures"
        }

        return "Syncing completed across \(selectedParticipantCount) calendars."
    }

    var currentActivityTimestampSuffix: String? {
        if isSyncInFlight || isGoogleAuthInFlight || !googleOperationAccountIDs.isEmpty || isAppleCalendarOperationInFlight {
            return nil
        }

        switch liveGoogleSmokeStatus {
        case .idle:
            break
        case .awaitingAuthentication, .running, .passed, .failed:
            return nil
        }

        guard let lastBusyMirrorSyncSummary,
              lastBusyMirrorSyncSummary.failedCount == 0,
              lastBusyMirrorSyncSummary.participantCount >= 2
        else {
            return nil
        }

        return Self.messageTimestampLabel(for: lastBusyMirrorSyncSummary.completedAt)
    }

    var currentActivityIconName: String {
        if isSyncInFlight {
            return "arrow.triangle.2.circlepath.circle.fill"
        }

        if isGoogleAuthInFlight {
            return "person.crop.circle.badge.plus"
        }

        if !googleOperationAccountIDs.isEmpty {
            return "arrow.clockwise.circle"
        }

        if isAppleCalendarOperationInFlight {
            return "calendar.badge.clock"
        }

        switch liveGoogleSmokeStatus {
        case .awaitingAuthentication:
            return "person.crop.circle.badge.exclamationmark"
        case .running:
            return "arrow.triangle.2.circlepath.circle"
        case .passed:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .idle:
            break
        }

        if let lastBusyMirrorSyncSummary, lastBusyMirrorSyncSummary.failedCount > 0 {
            return "exclamationmark.triangle.fill"
        }

        if selectedParticipantCount < 2 {
            return "calendar.badge.exclamationmark"
        }

        return "checkmark.circle.fill"
    }

    var syncLastRunLabel: String {
        guard let lastBusyMirrorSyncSummary else {
            return "Never"
        }

        return Self.syncTimestampFormatter.string(from: lastBusyMirrorSyncSummary.completedAt)
    }

    var syncPendingCountLabel: String {
        "Pending writes: \(isSyncInFlight ? "calculating" : "0")"
    }

    var syncFailureCountLabel: String {
        "Failed writes: \(lastBusyMirrorSyncSummary?.failedCount ?? 0)"
    }

    var pendingActivityCount: Int {
        var count = 0

        if googleStoredAccounts.isEmpty {
            count += 1
        } else {
            count += googleNeedsAttentionCount
        }

        if usesCustomGoogleOAuthApp, googleOAuthResolutionMessage != nil {
            count += 1
        }

        if isAppleCalendarEnabled {
            if appleCalendarAuthorizationState != .granted || selectedAppleCalendar == nil {
                count += 1
            }
        }

        if selectedParticipantCount < 2 {
            count += 1
        }

        return count
    }

    var pendingActivityLabel: String {
        let count = pendingActivityCount
        return count == 1 ? "1 pending item" : "\(count) pending items"
    }

    var failureCount: Int {
        lastBusyMirrorSyncSummary?.failedCount ?? 0
    }

    var failureCountLabel: String {
        let count = failureCount
        return count == 1 ? "1 failure" : "\(count) failures"
    }

    var canSyncNow: Bool {
        !isSyncInFlight && selectedParticipantCount >= 1
    }

    var googleOAuthConfiguration: GoogleOAuthOverrideConfiguration {
        GoogleOAuthOverrideConfiguration(
            usesCustomApp: usesCustomGoogleOAuthApp,
            clientID: customGoogleOAuthClientID,
            serverClientID: customGoogleOAuthServerClientID
        )
    }

    var connectedAccountsForDisplay: [ConnectedAccountListEntry] {
        ConnectedAccountListBuilder.build(
            scenarioAccounts: state?.scenario.accounts ?? [],
            appleCalendarEnabled: isAppleCalendarEnabled,
            appleCalendarAuthorizationState: appleCalendarAuthorizationState,
            selectedAppleCalendar: selectedAppleCalendar,
            googleAccountCards: googleAccountCards
        )
    }

    var appleConnectButtonTitle: String {
        isAppleCalendarEnabled ? "Reconnect Apple Calendar" : "Connect Apple Calendar"
    }

    var googleAuthMessageTimestampLabel: String? {
        Self.messageTimestampLabel(for: googleAuthMessageUpdatedAt)
    }

    var appleCalendarMessageTimestampLabel: String? {
        Self.messageTimestampLabel(for: appleCalendarMessageUpdatedAt)
    }

    var canOpenAppleCalendarSettings: Bool {
        launchOptions.platformTarget == .macos
    }

    var sharedConfigurationStatusLabel: String {
        sharedConfigurationSyncState.statusLabel
    }

    var sharedConfigurationStatusMessage: String {
        sharedConfigurationSyncState.detail
    }

    var sharedConfigurationStatusTimestampLabel: String? {
        Self.messageTimestampLabel(for: sharedConfigurationSyncState.updatedAt)
    }

    var sharedConfigurationScopeMessage: String {
        "Only non-secret settings sync through iCloud. Google sign-in and Apple permissions stay on each device."
    }

    var sharedConfigurationHasFailureStatus: Bool {
        sharedConfigurationSyncState.isFailure
    }

    var canManuallySyncSharedConfiguration: Bool {
        isSharedConfigurationEnabled && sharedConfigurationStore.isAvailable && !isSharedConfigurationSyncInFlight
    }

    private var isSharedConfigurationSyncInFlight: Bool {
        if case .syncing = sharedConfigurationSyncState {
            return true
        }

        return false
    }

    var iosBackgroundRefreshStatusLabel: String? {
        guard launchOptions.platformTarget == .ios else {
            return nil
        }

        switch iosBackgroundRefreshState {
        case .unsupported:
            return "Unavailable"
        case .denied:
            return "Off"
        case .restricted:
            return "Restricted"
        case .scheduled:
            return "On"
        case .failed:
            return "Issue"
        }
    }

    var iosBackgroundRefreshDetail: String? {
        guard launchOptions.platformTarget == .ios else {
            return nil
        }

        switch iosBackgroundRefreshState {
        case .unsupported:
            if launchOptions.uiTestMode || launchOptions.appStoreScreenshotMode != nil {
                return "Background refresh stays off during harness UI-test and screenshot launches."
            }
            return "Background refresh is not available for this app launch."
        case .denied:
            return "Background App Refresh is turned off for this device or for Calendar Busy Sync in Settings."
        case .restricted:
            return "Background App Refresh is restricted on this device, so iOS will not run sync in the background."
        case let .scheduled(date):
            let label = Self.messageTimestampLabel(for: date) ?? "later"
            return "Best effort. iOS decides the actual timing; the current request asks for no earlier than \(label)."
        case let .failed(message):
            return "The app could not schedule a background refresh request. \(message)"
        }
    }

    var canRunIOSBackgroundRefreshVerification: Bool {
        supportsIOSBackgroundRefresh && !isSyncInFlight
    }

    var selectedAppleCalendar: AppleCalendarSummary? {
        appleCalendars.first(where: { $0.id == selectedAppleCalendarID })
    }

    var selectedParticipantCount: Int {
        googleAccountCards.filter { $0.selectedCalendar != nil }.count
            + (selectedAppleCalendar == nil ? 0 : 1)
    }

    var bookingApprovalCalendarTargetSummary: String {
        if let calendar = bookingAppleCalendarTarget {
            return "Apple / iCloud: \(calendar.displayName)"
        }

        if let target = bookingGoogleCalendarTarget {
            let account = target.account
            let calendar = target.calendar
            return "Google: \(calendar.displayName) (\(account.email))"
        }

        return "No target calendar selected"
    }

    var bookingApprovalCalendarDetail: String {
        if let calendar = bookingAppleCalendarTarget {
            return "Accepted bookings are added to \(calendar.displayName). iCloud calendars also save an invite file with attendees."
        }

        if let target = bookingGoogleCalendarTarget {
            let account = target.account
            let calendar = target.calendar
            return "Accepted bookings are added to \(calendar.displayName) for \(account.email)."
        }

        return "Select an Apple / iCloud calendar or a Google calendar before approving requests or enabling automatic acceptance."
    }

    var bookingCalendarTargetWarning: String? {
        guard bookingCalendarTargetOptions.isEmpty else {
            return nil
        }

        switch appleCalendarAuthorizationState {
        case .denied:
            return "Apple Calendar access is denied for this app. Re-enable it in System Settings > Privacy & Security > Calendars."
        case .restricted:
            return "Apple Calendar access is restricted on this device, so Booking cannot load Apple or iCloud target calendars."
        case .notDetermined:
            return "Grant Apple Calendar access or connect Google on this device before Booking can write accepted requests to a calendar."
        case .granted:
            break
        }

        let pendingLocalConnectionCount = googleAccountRosterRows.filter {
            $0.kind == .needsLocalConnection
        }.count

        if pendingLocalConnectionCount > 0 {
            let sharedAccountMessage = pendingLocalConnectionCount == 1
                ? "A shared Google calendar is configured, but this Mac still needs local Google sign-in before Booking can write accepted requests to it."
                : "\(pendingLocalConnectionCount) shared Google calendars are configured, but this Mac still needs local Google sign-in before Booking can write accepted requests to them."

            if let blockingReason = googleSignInEnvironment.blockingReason {
                return "\(sharedAccountMessage) \(blockingReason)"
            }

            return sharedAccountMessage
        }

        if let blockingReason = googleSignInEnvironment.blockingReason {
            return blockingReason
        }

        if let googleAuthMessage {
            return googleAuthMessage
        }

        if case let .invalid(message) = googleOAuthResolution {
            return message
        }

        return nil
    }

    var bookingApprovalGoogleTargetAccountID: String? {
        bookingGoogleCalendarTarget?.account.id
    }

    var bookingApprovalAppleTargetIsSelected: Bool {
        bookingAppleCalendarTarget != nil
    }

    var bookingCalendarTargetOptions: [BookingCalendarTargetOption] {
        let appleOptions = appleCalendars.map { calendar in
            BookingCalendarTargetOption(
                id: BookingCalendarTargetOption.apple(calendarID: calendar.id),
                label: calendar.displayName,
                detail: "Apple / iCloud"
            )
        }
        let googleOptions = googleAccountCards.flatMap { card in
            card.calendars.map { calendar in
                BookingCalendarTargetOption(
                    id: BookingCalendarTargetOption.google(accountID: card.id, calendarID: calendar.id),
                    label: calendar.displayName,
                    detail: "Google • \(card.account.email)"
                )
            }
        }
        return appleOptions + googleOptions
    }

    var selectedBookingCalendarTargetOptionID: String {
        if let calendar = bookingAppleCalendarTarget {
            return BookingCalendarTargetOption.apple(calendarID: calendar.id)
        }

        if let target = bookingGoogleCalendarTarget {
            return BookingCalendarTargetOption.google(
                accountID: target.account.id,
                calendarID: target.calendar.id
            )
        }

        return ""
    }

    private var bookingTargetProvider: BookingCalendarTargetProvider {
        BookingCalendarTargetProvider(rawValue: bookingCalendarTargetProviderString) ?? .automatic
    }

    private var bookingAppleCalendarTarget: AppleCalendarSummary? {
        guard bookingTargetProvider != .google else {
            return nil
        }

        let targetCalendarID = bookingAppleTargetCalendarIDString.isEmpty
            ? selectedAppleCalendarID
            : bookingAppleTargetCalendarIDString
        return appleCalendars.first(where: { $0.id == targetCalendarID })
    }

    private var bookingGoogleCalendarTarget: (account: StoredGoogleAccount, calendar: GoogleCalendarSummary)? {
        if bookingTargetProvider == .google,
           let account = storedGoogleAccount(id: bookingGoogleTargetAccountIDString),
           let calendar = googleCalendarsByAccountID[account.id]?.first(where: { $0.id == bookingGoogleTargetCalendarIDString }) {
            return (account, calendar)
        }

        guard bookingTargetProvider == .automatic || bookingTargetProvider == .google else {
            return nil
        }

        if let accountID = activeResolvedGoogleAccountID,
           let account = storedGoogleAccount(id: accountID),
           let calendar = selectedGoogleCalendar(for: accountID) {
            return (account, calendar)
        }

        return nil
    }

    private func bookingAppleCalendarTarget(
        for appointmentType: BookingAppointmentType,
        allowsFallback: Bool = true
    ) -> AppleCalendarSummary? {
        guard let target = appointmentType.calendarTarget else {
            return allowsFallback ? bookingAppleCalendarTarget : nil
        }

        guard target.provider == .apple else {
            return nil
        }

        return appleCalendars.first(where: { $0.id == target.calendarID })
    }

    private func bookingGoogleCalendarTarget(
        for appointmentType: BookingAppointmentType,
        allowsFallback: Bool = true
    ) -> (account: StoredGoogleAccount, calendar: GoogleCalendarSummary)? {
        guard let target = appointmentType.calendarTarget else {
            return allowsFallback ? bookingGoogleCalendarTarget : nil
        }

        guard target.provider == .google,
              let accountID = target.accountID,
              let account = storedGoogleAccount(id: accountID),
              let calendar = googleCalendarsByAccountID[accountID]?.first(where: { $0.id == target.calendarID })
        else {
            return nil
        }

        return (account, calendar)
    }

    private func defaultBookingAppointmentCalendarTarget() -> BookingAppointmentCalendarTarget? {
        if let calendar = bookingAppleCalendarTarget {
            return .apple(calendarID: calendar.id)
        }

        if let target = bookingGoogleCalendarTarget {
            return .google(accountID: target.account.id, calendarID: target.calendar.id)
        }

        return nil
    }

    var appleConnectionStatusLabel: String {
        if isAppleCalendarOperationInFlight {
            return isAppleCalendarEnabled ? "Updating…" : "Connecting…"
        }

        guard isAppleCalendarEnabled else {
            return "Not connected"
        }

        switch appleCalendarAuthorizationState {
        case .granted:
            return "Connected"
        case .denied:
            return "Permission denied"
        case .restricted:
            return "Restricted"
        case .notDetermined:
            return "Pending"
        }
    }

    var appleConnectionDetail: String {
        guard isAppleCalendarEnabled else {
            return "Connect Apple Calendar to use calendars available on this device, including iCloud calendars."
        }

        switch appleCalendarAuthorizationState {
        case .granted:
            if let selectedAppleCalendar {
                return "Apple Calendar access is enabled. Busy slots will be written to \(selectedAppleCalendar.displayName)."
            }

            return "Apple Calendar access is enabled. Load or select a writable Apple calendar on this device."
        case .denied:
            return "Calendar access is denied for this app. Re-enable it in System Settings > Privacy & Security > Calendars."
        case .restricted:
            return "Calendar access is restricted on this device."
        case .notDetermined:
            return "Apple Calendar access has not been granted yet."
        }
    }

    var appleCalendarStatusLabel: String {
        if isAppleCalendarOperationInFlight {
            return "Working…"
        }

        guard isAppleCalendarEnabled else {
            return "Connect required"
        }

        switch appleCalendarAuthorizationState {
        case .denied:
            return "Permission denied"
        case .restricted:
            return "Restricted"
        case .notDetermined:
            return "Permission required"
        case .granted:
            if appleCalendars.isEmpty {
                return "No calendars loaded"
            }

            if selectedAppleCalendar == nil {
                return "Select a calendar"
            }

            return "Ready"
        }
    }

    var appleCalendarDetail: String {
        guard isAppleCalendarEnabled else {
            return "Connect Apple Calendar to choose a writable Apple or iCloud calendar."
        }

        switch appleCalendarAuthorizationState {
        case .granted:
            if let selectedAppleCalendar {
                return "Busy slots will be written to \(selectedAppleCalendar.displayName)."
            }

            if appleCalendars.isEmpty {
                return "No writable Apple calendars are loaded yet."
            }

            return "Select which Apple or iCloud calendar should receive busy slots."
        case .denied:
            return "Calendar access is denied for this app."
        case .restricted:
            return "Calendar access is restricted on this device."
        case .notDetermined:
            return "Grant Apple Calendar access to load local and iCloud calendars."
        }
    }

    var canRefreshAppleCalendars: Bool {
        isAppleCalendarEnabled && !isAppleCalendarOperationInFlight
    }

    var canCreateManagedAppleEvent: Bool {
        selectedAppleCalendar != nil && !isAppleCalendarOperationInFlight
    }

    var canDeleteManagedAppleEvent: Bool {
        lastManagedAppleEvent != nil && !isAppleCalendarOperationInFlight
    }

    var googleConnectedAccounts: [GoogleConnectedAccount] {
        googleStoredAccounts.map(\.connectedAccount)
    }

    var googleAccountRosterRows: [GoogleAccountRosterRowModel] {
        GoogleAccountRosterBuilder.build(
            localCards: googleAccountCards,
            sharedDescriptors: sharedGoogleAccountDescriptors,
            isSharedConfigurationEnabled: isSharedConfigurationEnabled
        )
    }

    var googleAccountCards: [GoogleAccountCardModel] {
        googleStoredAccounts.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }.map { storedAccount in
            GoogleAccountCardModel(
                account: storedAccount.connectedAccount,
                calendars: googleCalendarsByAccountID[storedAccount.id] ?? [],
                selectedCalendarID: googleSelectedCalendarIDs[storedAccount.id] ?? "",
                message: googleMessagesByAccountID[storedAccount.id],
                messageTimestampLabel: Self.messageTimestampLabel(
                    for: googleMessageUpdatedAtByAccountID[storedAccount.id]
                ),
                lastManagedEvent: lastManagedGoogleEventsByAccountID[storedAccount.id],
                isOperationInFlight: googleOperationAccountIDs.contains(storedAccount.id)
            )
        }
    }

    var googleReadyAccountCount: Int {
        googleAccountRosterRows.filter { $0.countsTowardSetup && !$0.needsAttention }.count
    }

    var googleNeedsAttentionCount: Int {
        googleAccountRosterRows.filter { $0.countsTowardSetup && $0.needsAttention }.count
    }

    var googleConnectionStatusLabel: String {
        if isGoogleAuthInFlight {
            return googleStoredAccounts.isEmpty ? "Connecting…" : "Adding…"
        }

        if !googleStoredAccounts.isEmpty {
            let count = googleStoredAccounts.count
            return count == 1 ? "1 account connected" : "\(count) accounts connected"
        }

        if googleSignInEnvironment.blockingReason != nil {
            return "Signed build required"
        }

        return "Not connected"
    }

    var googleConnectionDetail: String {
        let pendingLocalConnectionCount = googleAccountRosterRows.filter {
            $0.kind == .needsLocalConnection
        }.count

        if pendingLocalConnectionCount > 0 {
            return pendingLocalConnectionCount == 1
                ? "1 shared Google account still needs local sign-in on this device."
                : "\(pendingLocalConnectionCount) shared Google accounts still need local sign-in on this device."
        }

        if !googleStoredAccounts.isEmpty {
            return "Add another Google account or manage each participating calendar below."
        }

        if let blockingReason = googleSignInEnvironment.blockingReason {
            return blockingReason
        }

        if case let .invalid(message) = googleOAuthResolution {
            return message
        }

        return "Connect Google to authorize calendar selection and busy-slot mirroring."
    }

    var googleOAuthResolutionMessage: String? {
        if case let .invalid(message) = googleOAuthResolution {
            return message
        }
        return nil
    }

    var canStartGoogleSignIn: Bool {
        !isGoogleAuthInFlight
            && googleSignInEnvironment.allowsInteractiveSignIn
            && defaultGoogleOAuthConfiguration != nil
            && (!usesCustomGoogleOAuthApp || googleOAuthResolutionMessage == nil)
    }

    var googleConnectButtonTitle: String {
        googleStoredAccounts.isEmpty ? "Add Google Account" : "Add Another Google Account"
    }

    var googleCalendarStatusLabel: String {
        if !googleOperationAccountIDs.isEmpty {
            return "Working…"
        }

        if googleStoredAccounts.isEmpty {
            return "Sign in required"
        }

        if googleAccountCards.allSatisfy({ $0.statusLabel == "Ready" }) {
            return "Ready"
        }

        return "Action needed"
    }

    var googleCalendarDetail: String {
        let setupRows = googleAccountRosterRows.filter(\.countsTowardSetup)

        if googleStoredAccounts.isEmpty && setupRows.isEmpty {
            return "Connect Google to load writable calendars from each signed-in account."
        }

        let readyCount = setupRows.filter { !$0.needsAttention }.count
        let total = setupRows.count
        return "\(readyCount) of \(total) Google accounts are ready on this device."
    }

    var liveGoogleSmokeStatusLabel: String? {
        liveGoogleSmokeStatus.statusLabel
    }

    var liveGoogleSmokeSummary: String? {
        liveGoogleSmokeStatus.summary
    }

    var auditTrailEntries: [AuditTrailEntry] {
        if let limit = auditTrailLogLength.limit, runtimeAuditTrailEntries.count > limit {
            return Array(runtimeAuditTrailEntries.prefix(limit))
        }

        return runtimeAuditTrailEntries
    }

    var bookingPageStatusLabel: String {
        bookingSetupSnapshot.pageStatus.label
    }

    var bookingPageEvidenceLines: [String] {
        var lines: [String] = []
        if let bookingLastGeneratedAt {
            lines.append("Generated \(Self.syncTimestampFormatter.string(from: bookingLastGeneratedAt))")
        }
        if let bookingLastUploadedAt {
            lines.append("Uploaded \(Self.syncTimestampFormatter.string(from: bookingLastUploadedAt))")
        }
        if let bookingLastVerifiedAt {
            lines.append("Verified \(Self.syncTimestampFormatter.string(from: bookingLastVerifiedAt))")
        }
        if !bookingLastGeneratedFingerprintString.isEmpty {
            lines.append("Latest local version \(String(bookingLastGeneratedFingerprintString.prefix(12)))")
        }
        if !bookingLastServedFingerprintString.isEmpty {
            lines.append("Live page version \(String(bookingLastServedFingerprintString.prefix(12)))")
        }
        if let bookingAvailabilityPublishSummary {
            lines.append(bookingAvailabilityPublishSummary)
        }
        return lines
    }

    var bookingInboxStatusLabel: String {
        bookingSetupSnapshot.inboxStatus.label
    }

    var bookingPagePreviewSummary: String {
        "\(bookingResolvedPageTitle) / \(bookingResolvedPublicName) / \(bookingResolvedTheme.accentColor)"
    }

    var bookingPageSafetyLines: [String] {
        [
            "Public config includes appointment copy, public key, inbox URL, and version fingerprint.",
            "Secret scan runs before writing generated config and availability.",
            "Protected files keep slot signing, request encryption, and relay protocol behavior intact.",
        ]
    }

    var bookingSafeCustomizationFileLines: [String] {
        [
            "content/profile.md",
            "content/appointment-types/*.md",
            "content/default-copy.json",
            "assets/styles.css",
        ]
    }

    var bookingProtectedProtocolFileLines: [String] {
        [
            "assets/app.js",
            "public/site-config.json",
            "public/availability/*.json",
        ]
    }

    var bookingVercelEnvironmentLines: [String] {
        [
            "ALLOWED_ORIGIN=\(bookingExpectedAllowedOriginString.isEmpty ? "https://owner.github.io" : bookingExpectedAllowedOriginString)",
            "BLOB_READ_WRITE_TOKEN=(created by connected Vercel Blob storage)",
            "INBOX_ADMIN_TOKEN=(generated and stored locally)",
            "MAX_PENDING_REQUESTS=100",
        ]
    }

    var bookingRequestInboxEvidenceLines: [String] {
        var lines = ["Status \(bookingInboxStatusLabel)"]
        if !bookingExpectedAllowedOriginString.isEmpty {
            lines.append("Expected origin \(bookingExpectedAllowedOriginString)")
        }
        if !bookingInboxURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("Vercel inbox URL stored")
        }
        if !bookingInboxAdminTokenString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("Inbox secret stored locally")
        }
        if !bookingVercelProjectNameString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("Vercel project \(bookingVercelProjectNameString.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        if !bookingVercelTokenString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("Vercel token stored locally")
        }
        lines.append("Vercel Blob storage is created and connected during deploy")
        return lines
    }

    var bookingExpectedAllowedOriginString: String {
        guard let url = URL(string: bookingPageURLString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return ""
        }

        return Self.originString(for: url)
    }

    var bookingRequestsStatusLabel: String {
        bookingSetupSnapshot.requestsLabel
    }

    var bookingResolvedProfile: BookingProfile {
        BookingProfile(
            id: BookingProfileID("default"),
            publicName: bookingResolvedPublicName,
            pageTitle: bookingResolvedPageTitle,
            pageSubtitle: bookingPageSubtitleString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? BookingProfile.example.pageSubtitle
                : bookingPageSubtitleString.trimmingCharacters(in: .whitespacesAndNewlines),
            timeZoneIdentifier: TimeZone(identifier: bookingTimeZoneIdentifierString.trimmingCharacters(in: .whitespacesAndNewlines))?.identifier
                ?? BookingProfile.example.timeZoneIdentifier
        )
    }

    var bookingResolvedTheme: BookingTheme {
        BookingTheme(
            accentColor: Self.normalizedHexColor(bookingThemeAccentColorString, fallback: BookingTheme.defaultValue.accentColor),
            backgroundColor: Self.normalizedHexColor(bookingThemeBackgroundColorString, fallback: BookingTheme.defaultValue.backgroundColor),
            textColor: Self.normalizedHexColor(bookingThemeTextColorString, fallback: BookingTheme.defaultValue.textColor)
        )
    }

    private var bookingResolvedPublicName: String {
        let value = bookingPublicNameString.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? BookingProfile.example.publicName : value
    }

    private var bookingResolvedPageTitle: String {
        let value = bookingPageTitleString.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "Request time with \(bookingResolvedPublicName)" : value
    }

    private var bookingResolvedShareID: BookingShareID {
        let slug = bookingAppointmentTypes.first { !$0.isPaused }?.slug
            ?? bookingAppointmentTypes.first?.slug
            ?? "intro-call"
        return BookingShareID(slug)
    }

    var selectedBookingAppointmentType: BookingAppointmentType? {
        bookingAppointmentTypes.first { $0.id.rawValue == selectedBookingAppointmentTypeIDString }
            ?? bookingAppointmentTypes.first
    }

    var selectedBookingAppointmentTypeURL: URL? {
        guard let selectedBookingAppointmentType else {
            return nil
        }

        return bookingPageURL(for: selectedBookingAppointmentType)
    }

    var selectedBookingAppointmentTypeURLString: String {
        selectedBookingAppointmentTypeURL?.absoluteString ?? ""
    }

    var canUseSelectedBookingAppointmentTypeURL: Bool {
        selectedBookingAppointmentTypeURL != nil && selectedBookingAppointmentType?.isPaused == false
    }

    var inferredBookingPageURLString: String {
        guard let repository = try? BookingGitHubRepository(rawValue: bookingGitHubRepositoryString) else {
            return ""
        }

        return repository.pagesURL.absoluteString
    }

    var canUseInferredBookingPageURL: Bool {
        !inferredBookingPageURLString.isEmpty
    }

    var canGenerateBookingGitHubDeployKey: Bool {
        (try? BookingGitHubRepository(rawValue: bookingGitHubRepositoryString)) != nil
    }

    var hasMatchingBookingGitHubDeployKey: Bool {
        guard let repository = try? BookingGitHubRepository(rawValue: bookingGitHubRepositoryString) else {
            return false
        }

        return bookingGitHubDeployKeyRepositoryString == repository.slug
            && !bookingGitHubDeployKeyPublicKeyString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var bookingGitHubDeployKeyStatusMessage: String {
        guard !bookingGitHubDeployKeyPublicKeyString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Generate a deploy key, add the public key to this GitHub repository with write access, then verify it."
        }

        let repositorySuffix = bookingGitHubDeployKeyRepositoryString.isEmpty
            ? ""
            : " for \(bookingGitHubDeployKeyRepositoryString)"
        if let verifiedAt = bookingGitHubDeployKeyVerifiedAt {
            let verifiedLabel = Self.messageTimestampLabel(for: verifiedAt) ?? Self.syncTimestampFormatter.string(from: verifiedAt)
            return "Deploy key\(repositorySuffix) verified \(verifiedLabel)."
        }

        return "Deploy key\(repositorySuffix) generated. Add the public key to GitHub with write access, then verify it."
    }

    var canPublishBookingPageToGitHub: Bool {
        (try? BookingGitHubRepository(rawValue: bookingGitHubRepositoryString)) != nil
            && hasMatchingBookingGitHubDeployKey
    }

    var shouldConfirmBookingPublishOnDismiss: Bool {
        bookingSetupSnapshot.pageStatus == .needsPublish
            && canPublishBookingPageToGitHub
            && hasActiveBookingAppointmentTypes
    }

    var canVerifyBookingPage: Bool {
        let trimmedURL = bookingPageURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedURL),
              let scheme = url.scheme?.lowercased(),
              scheme == "https",
              url.host?.isEmpty == false
        else {
            return false
        }

        return true
    }

    var hasActiveBookingAppointmentTypes: Bool {
        bookingAppointmentTypes.contains { !$0.isPaused }
    }

    var canRunBookingDryRun: Bool {
        true
    }

    var bookingPageFilesFolderPath: String {
        bookingSiteBuildOutputURL.path
    }

    var bookingPageFilesFolderURL: URL {
        bookingSiteBuildOutputURL
    }

    var bookingPageTemplateFolderPath: String {
        bookingEditableTemplateURL.path
    }

    var bookingPageTemplateFolderURL: URL {
        bookingEditableTemplateURL
    }

    var canCreateGoogleMeetForBookingTarget: Bool {
        selectedBookingAppointmentType.map { canCreateGoogleMeet(for: $0) } ?? false
    }

    var bookingPublishActionTitle: String {
        bookingPageURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? BookingCopy.Action.runDryRun
            : BookingCopy.Action.publishPage
    }

    var bookingPublishActionIconName: String {
        bookingPageURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? BookingIconography.pageStep.primarySystemName
            : BookingIconography.publishPage.primarySystemName
    }

    var canCheckBookingInbox: Bool {
        !bookingInboxURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canDeployBookingVercelInbox: Bool {
        !isBookingVercelDeploymentInFlight
            && !bookingVercelTokenString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !bookingVercelProjectNameString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !bookingExpectedAllowedOriginString.isEmpty
    }

    var canSendBookingTestRequest: Bool {
        bookingSetupSnapshot.inboxStatus == .connected
            && !bookingPageURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isBookingTestRequestInFlight
    }

    var canImportBookingRequests: Bool {
        bookingSetupSnapshot.inboxStatus == .connected
            && !bookingInboxAdminTokenString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isBookingImportInFlight
    }

    var hasImportedBookingRequests: Bool {
        !importedBookingRequests.isEmpty
    }

    var activeBookingRequests: [BookingImportedRequest] {
        importedBookingRequests.filter { request in
            request.status != .approved && request.status != .declined
        }
    }

    var hasActiveBookingRequests: Bool {
        !activeBookingRequests.isEmpty
    }

    var bookingRequestHistory: [BookingImportedRequest] {
        importedBookingRequests
    }

    var hasBookingRequestHistory: Bool {
        !bookingRequestHistory.isEmpty
    }

    func bookingPageURL(for appointmentType: BookingAppointmentType) -> URL? {
        guard !appointmentType.isPaused else {
            return nil
        }

        let trimmedURL = bookingPageURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmedURL),
              let scheme = components.scheme?.lowercased(),
              scheme == "https",
              components.host?.isEmpty == false
        else {
            return nil
        }

        var queryItems = components.queryItems?.filter { $0.name != "appointment" } ?? []
        queryItems.append(URLQueryItem(name: "appointment", value: appointmentType.slug))
        components.queryItems = queryItems
        return components.url
    }

    func canCreateGoogleMeet(for appointmentType: BookingAppointmentType) -> Bool {
        bookingGoogleCalendarTarget(for: appointmentType, allowsFallback: false) != nil
    }

    func bookingCalendarTargetSummary(for appointmentType: BookingAppointmentType) -> String {
        if let calendar = bookingAppleCalendarTarget(for: appointmentType, allowsFallback: false) {
            return "Apple / iCloud: \(calendar.displayName)"
        }

        if let target = bookingGoogleCalendarTarget(for: appointmentType, allowsFallback: false) {
            return "Google: \(target.calendar.displayName) (\(target.account.email))"
        }

        return "No target calendar selected"
    }

    func bookingCalendarTargetDetail(for appointmentType: BookingAppointmentType) -> String {
        if let calendar = bookingAppleCalendarTarget(for: appointmentType, allowsFallback: false) {
            return calendar.isLikelyICloud
                ? "Accepted \(appointmentType.name) requests are added here. iCloud targets also save an invite file with attendees."
                : "Accepted \(appointmentType.name) requests are added here."
        }

        if let target = bookingGoogleCalendarTarget(for: appointmentType, allowsFallback: false) {
            return "Accepted \(appointmentType.name) requests are added to \(target.calendar.displayName) for \(target.account.email)."
        }

        return "Choose where accepted \(appointmentType.name) requests should create calendar events."
    }

    func selectedBookingCalendarTargetOptionID(for appointmentTypeID: AppointmentTypeID) -> String {
        bookingAppointmentTypes.first(where: { $0.id == appointmentTypeID })?.calendarTarget?.optionID ?? ""
    }

    func bookingAppointmentTypeLifecycleStatus(_ appointmentType: BookingAppointmentType) -> BookingAppointmentTypeLifecycleStatus {
        if appointmentType.isPaused {
            return .paused
        }
        if appointmentType.weeklyHours.allSatisfy({ $0.windows.isEmpty }) {
            return .noSlots
        }
        if (try? BookingConfigurationValidator.validateAppointmentTypes(bookingAppointmentTypes)) == nil {
            return .broken("Validation failed")
        }
        switch bookingSetupSnapshot.pageStatus {
        case .published:
            return .live
        case .needsPublish:
            return .changedLocally
        case .notPublished, .generatedLocally, .uploaded, .publishFailed, .disabled:
            return .draft
        }
    }

    @discardableResult
    func addBookingAppointmentType() -> BookingAppointmentType {
        let slug = uniqueAppointmentSlug(base: "new-meeting")
        let appointmentType = BookingAppointmentType(
            id: AppointmentTypeID(slug),
            slug: slug,
            name: "New meeting",
            summary: "A focused conversation.",
            durationMinutes: 30,
            availabilityHorizonDays: BookingAppointmentType.defaultAvailabilityHorizonDays,
            minimumNoticeMinutes: 240,
            bufferBeforeMinutes: 0,
            bufferAfterMinutes: 0,
            weeklyHours: BookingWeeklyHours.weekdayDefault,
            location: .none,
            calendarTarget: defaultBookingAppointmentCalendarTarget(),
            isAutoConfirmEnabled: false,
            isPaused: false,
            questions: BookingDraftFactory.defaultAppointmentTypes.first?.questions ?? []
        )
        bookingAppointmentTypes.append(appointmentType)
        selectedBookingAppointmentTypeIDString = appointmentType.id.rawValue
        persistBookingAppointmentTypes()
        markBookingPageNeedsPublish(message: "Appointment type added. Generate page files before sharing it.")
        return appointmentType
    }

    @discardableResult
    func duplicateBookingAppointmentType(_ id: AppointmentTypeID) -> BookingAppointmentType? {
        guard let source = bookingAppointmentTypes.first(where: { $0.id == id }) else {
            return nil
        }

        let slug = uniqueAppointmentSlug(base: source.slug)
        var copy = source
        copy.id = AppointmentTypeID(slug)
        copy.slug = slug
        copy.name = "\(source.name) copy"
        copy.isPaused = true
        bookingAppointmentTypes.append(copy)
        selectedBookingAppointmentTypeIDString = copy.id.rawValue
        persistBookingAppointmentTypes()
        markBookingPageNeedsPublish(message: "Appointment type duplicated. Generate page files before sharing it.")
        return copy
    }

    func pauseBookingAppointmentType(_ id: AppointmentTypeID) {
        setBookingAppointmentTypePaused(id, isPaused: true)
    }

    func resumeBookingAppointmentType(_ id: AppointmentTypeID) {
        setBookingAppointmentTypePaused(id, isPaused: false)
    }

    func deleteBookingAppointmentType(_ id: AppointmentTypeID) {
        guard bookingAppointmentTypes.count > 1 else {
            markBookingPageNeedsPublish(message: "Keep at least one appointment type.")
            return
        }

        bookingAppointmentTypes.removeAll { $0.id == id }
        if selectedBookingAppointmentTypeIDString == id.rawValue {
            selectedBookingAppointmentTypeIDString = bookingAppointmentTypes.first?.id.rawValue ?? ""
        }
        persistBookingAppointmentTypes()
        markBookingPageNeedsPublish(message: "Appointment type removed. Generate page files before sharing changes.")
    }

    func updateBookingAppointmentType(_ appointmentType: BookingAppointmentType) {
        updateBookingAppointmentType(appointmentType, replacing: appointmentType.id)
    }

    func updateBookingAppointmentType(_ appointmentType: BookingAppointmentType, replacing originalID: AppointmentTypeID) {
        do {
            var nextAppointmentTypes = bookingAppointmentTypes
            if let index = nextAppointmentTypes.firstIndex(where: { $0.id == originalID }) {
                nextAppointmentTypes[index] = appointmentType
            } else {
                nextAppointmentTypes.append(appointmentType)
            }

            try BookingConfigurationValidator.validateAppointmentTypes(nextAppointmentTypes)
            bookingAppointmentTypes = nextAppointmentTypes
            selectedBookingAppointmentTypeIDString = appointmentType.id.rawValue
            persistBookingAppointmentTypes()
            markBookingPageNeedsPublish(message: "Appointment type saved. Generate page files before sharing changes.")
        } catch {
            updateBookingSetupSnapshot(
                BookingSetupSnapshot(
                    pageStatus: bookingSetupSnapshot.pageStatus,
                    inboxStatus: bookingSetupSnapshot.inboxStatus,
                    pendingRequestCount: bookingSetupSnapshot.pendingRequestCount,
                    lastMessage: error.localizedDescription
                ),
                auditDetail: "Could not save appointment type. \(error.localizedDescription)"
            )
        }
    }

    func setBookingCalendarTargetOptionID(_ optionID: String, for appointmentTypeID: AppointmentTypeID) {
        guard let index = bookingAppointmentTypes.firstIndex(where: { $0.id == appointmentTypeID }) else {
            return
        }

        guard optionID.isEmpty || BookingAppointmentCalendarTarget.parse(optionID: optionID) != nil else {
            return
        }

        bookingAppointmentTypes[index].calendarTarget = BookingAppointmentCalendarTarget.parse(optionID: optionID)
        selectedBookingAppointmentTypeIDString = appointmentTypeID.rawValue
        persistBookingAppointmentTypes()
        updateBookingSetupSnapshot(
            BookingSetupSnapshot(
                pageStatus: bookingSetupSnapshot.pageStatus,
                inboxStatus: bookingSetupSnapshot.inboxStatus,
                pendingRequestCount: bookingSetupSnapshot.pendingRequestCount,
                lastMessage: optionID.isEmpty
                    ? "Appointment target calendar cleared."
                    : "Appointment target calendar updated."
            ),
            auditDetail: optionID.isEmpty
                ? "Booking appointment target calendar cleared."
                : "Booking appointment target calendar updated."
        )
    }

    func useInferredGitHubPagesURL() {
        let inferredURL = inferredBookingPageURLString
        guard !inferredURL.isEmpty else {
            updateBookingSetupSnapshot(
                BookingSetupSnapshot(
                    pageStatus: .publishFailed,
                    inboxStatus: bookingSetupSnapshot.inboxStatus,
                    pendingRequestCount: bookingSetupSnapshot.pendingRequestCount,
                    lastMessage: "Enter a GitHub repository like owner/repo first."
                ),
                auditDetail: "Could not infer a GitHub Pages URL."
            )
            return
        }

        bookingPageURLString = inferredURL
        markBookingPageNeedsPublish(message: "Booking page URL set from the GitHub repository. Publish page files next.")
    }

    func generateBookingGitHubDeployKey() async {
        let repository: BookingGitHubRepository
        do {
            repository = try BookingGitHubRepository(rawValue: bookingGitHubRepositoryString)
        } catch {
            updateBookingSetupSnapshot(
                BookingSetupSnapshot(
                    pageStatus: .publishFailed,
                    inboxStatus: bookingSetupSnapshot.inboxStatus,
                    pendingRequestCount: bookingSetupSnapshot.pendingRequestCount,
                    lastMessage: error.localizedDescription
                ),
                auditDetail: "Deploy key generation skipped because repository settings are invalid."
            )
            return
        }

        #if os(macOS)
        do {
            let deployKey = try await BookingGitHubDeployKeyGenerator.generate(repository: repository, fileManager: fileManager)
            try bookingSecretStore.saveGitHubDeployKeyPrivateKey(deployKey.privateKeyPEM)
            recordBookingGitHubDeployKey(
                publicKey: deployKey.publicKey,
                fingerprint: deployKey.fingerprint,
                repository: repository.slug,
                verifiedAt: nil
            )
            updateBookingSetupSnapshot(
                BookingSetupSnapshot(
                    pageStatus: bookingSetupSnapshot.pageStatus,
                    inboxStatus: bookingSetupSnapshot.inboxStatus,
                    pendingRequestCount: bookingSetupSnapshot.pendingRequestCount,
                    lastMessage: "Deploy key generated. Add the public key to \(repository.slug) with write access, then verify it."
                ),
                auditDetail: "Generated a GitHub deploy key for \(repository.slug)."
            )
        } catch {
            updateBookingSetupSnapshot(
                BookingSetupSnapshot(
                    pageStatus: .publishFailed,
                    inboxStatus: bookingSetupSnapshot.inboxStatus,
                    pendingRequestCount: bookingSetupSnapshot.pendingRequestCount,
                    lastMessage: Self.bookingConfigurationFailureMessage(
                        error,
                        fallback: "Could not generate a deploy key."
                    )
                ),
                auditDetail: "Deploy key generation failed. \(error.localizedDescription)"
            )
        }
        #else
        updateBookingSetupSnapshot(
            BookingSetupSnapshot(
                pageStatus: .publishFailed,
                inboxStatus: bookingSetupSnapshot.inboxStatus,
                pendingRequestCount: bookingSetupSnapshot.pendingRequestCount,
                lastMessage: "GitHub publishing from the app is available on macOS."
            ),
            auditDetail: "Deploy key generation skipped on a non-macOS platform."
        )
        #endif
    }

    func verifyBookingGitHubDeployKey() async {
        let repository: BookingGitHubRepository
        do {
            repository = try BookingGitHubRepository(rawValue: bookingGitHubRepositoryString)
            guard bookingGitHubDeployKeyRepositoryString == repository.slug else {
                throw BookingConfigurationError.invalidField("Generate a deploy key for \(repository.slug) before verifying.")
            }
            let privateKey = try loadBookingGitHubDeployKeyPrivateKey()
            try await BookingGitHubPublisher.verifyDeployKey(
                repository: repository,
                privateKeyPEM: privateKey,
                fileManager: fileManager
            )
        } catch {
            updateBookingSetupSnapshot(
                BookingSetupSnapshot(
                    pageStatus: .publishFailed,
                    inboxStatus: bookingSetupSnapshot.inboxStatus,
                    pendingRequestCount: bookingSetupSnapshot.pendingRequestCount,
                    lastMessage: Self.bookingConfigurationFailureMessage(
                        error,
                        fallback: "Deploy key could not reach this GitHub repository."
                    )
                ),
                auditDetail: "GitHub deploy key verification failed. \(error.localizedDescription)"
            )
            return
        }

        let verifiedAt = Date()
        recordBookingGitHubDeployKey(
            publicKey: bookingGitHubDeployKeyPublicKeyString,
            fingerprint: bookingGitHubDeployKeyFingerprintString,
            repository: repository.slug,
            verifiedAt: verifiedAt
        )
        updateBookingSetupSnapshot(
            BookingSetupSnapshot(
                pageStatus: bookingSetupSnapshot.pageStatus,
                inboxStatus: bookingSetupSnapshot.inboxStatus,
                pendingRequestCount: bookingSetupSnapshot.pendingRequestCount,
                lastMessage: "Deploy key can reach \(repository.slug). Publish page files next."
            ),
            auditDetail: "Verified GitHub deploy key access for \(repository.slug)."
        )
    }

    func publishBookingPageToGitHub() async {
        await publishBookingPageToGitHub(reason: "Manual publish", updatesSnapshot: true)
    }

    private func publishBookingPageToGitHub(reason: String, updatesSnapshot: Bool) async {
        guard !isBookingAvailabilityPublishInFlight else {
            if updatesSnapshot {
                updateBookingSetupSnapshot(
                    BookingSetupSnapshot(
                        pageStatus: bookingSetupSnapshot.pageStatus,
                        inboxStatus: bookingSetupSnapshot.inboxStatus,
                        pendingRequestCount: bookingSetupSnapshot.pendingRequestCount,
                        lastMessage: "Booking availability publish is already running."
                    ),
                    auditDetail: "Skipped overlapping booking availability publish."
                )
            }
            return
        }

        guard hasMatchingBookingGitHubDeployKey else {
            if updatesSnapshot {
                updateBookingSetupSnapshot(
                    BookingSetupSnapshot(
                        pageStatus: .publishFailed,
                        inboxStatus: bookingSetupSnapshot.inboxStatus,
                        pendingRequestCount: bookingSetupSnapshot.pendingRequestCount,
                        lastMessage: "Generate a deploy key and add it to the GitHub repository with write access."
                    ),
                    auditDetail: "GitHub Pages publish skipped because no matching deploy key is configured."
                )
            }
            return
        }

        let repository: BookingGitHubRepository
        do {
            repository = try BookingGitHubRepository(rawValue: bookingGitHubRepositoryString)
        } catch {
            if updatesSnapshot {
                updateBookingSetupSnapshot(
                    BookingSetupSnapshot(
                        pageStatus: .publishFailed,
                        inboxStatus: bookingSetupSnapshot.inboxStatus,
                        pendingRequestCount: bookingSetupSnapshot.pendingRequestCount,
                        lastMessage: error.localizedDescription
                    ),
                    auditDetail: "GitHub Pages publish skipped because repository settings are invalid."
                )
            }
            return
        }

        isBookingAvailabilityPublishInFlight = true
        defer {
            isBookingAvailabilityPublishInFlight = false
        }

        do {
            let privateKey = try loadBookingGitHubDeployKeyPrivateKey()
            _ = try writeBookingSiteBuild()
            let publishSummary = try await BookingGitHubPublisher.publishDirectory(
                at: bookingSiteBuildOutputURL,
                repository: repository,
                branch: bookingGitHubBranchString,
                privateKeyPEM: privateKey,
                fileManager: fileManager
            )
            if bookingPageURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                bookingPageURLString = repository.pagesURL.absoluteString
            }

            let summaryMessage = Self.bookingGitHubPublishMessage(
                publishSummary,
                reason: reason
            )
            bookingAvailabilityPublishSummary = summaryMessage
            if publishSummary.didChangeRemote {
                recordBookingUploadedVersion(uploadedAt: Date())
            }
            recordBookingRemoteDriftWarningIfNeeded(
                publishSummary,
                repository: repository
            )
            if updatesSnapshot || publishSummary.didChangeRemote {
                updateBookingSetupSnapshot(
                    BookingSetupSnapshot(
                        pageStatus: publishSummary.didChangeRemote ? .uploaded : bookingSetupSnapshot.pageStatus,
                        inboxStatus: bookingSetupSnapshot.inboxStatus,
                        pendingRequestCount: bookingSetupSnapshot.pendingRequestCount,
                        lastMessage: summaryMessage
                    ),
                    auditDetail: "GitHub Pages publish for \(repository.slug): \(summaryMessage)"
                )
            } else {
                appendAuditTrailEntry(
                    title: "Booking availability publish",
                    detail: summaryMessage,
                    status: "ready"
                )
            }
        } catch {
            bookingAvailabilityPublishSummary = "Availability publish failed. \(error.localizedDescription)"
            if updatesSnapshot {
                updateBookingSetupSnapshot(
                    BookingSetupSnapshot(
                        pageStatus: .publishFailed,
                        inboxStatus: bookingSetupSnapshot.inboxStatus,
                        pendingRequestCount: bookingSetupSnapshot.pendingRequestCount,
                        lastMessage: Self.bookingConfigurationFailureMessage(
                            error,
                            fallback: BookingCopy.Validation.publishFailed
                        )
                    ),
                    auditDetail: "GitHub Pages publish failed. \(error.localizedDescription)"
                )
            } else {
                appendAuditTrailEntry(
                    title: "Booking availability publish",
                    detail: "GitHub Pages publish failed. \(error.localizedDescription)",
                    status: "failed"
                )
            }
        }
    }

    func handleIncomingURL(_ url: URL) {
        _ = GoogleSignInService.handle(url: url)
    }

    func handleIOSSceneDidBecomeActive() {
        scheduleIOSBackgroundRefreshIfPossible()
    }

    func handleIOSSceneDidEnterBackground() {
        scheduleIOSBackgroundRefreshIfPossible()
    }

    func handleIOSBackgroundRefreshTask() async {
        guard supportsIOSBackgroundRefresh else { return }

        await prepareIfNeeded()
        guard !Task.isCancelled else { return }

        await syncNowIfReady()
        guard !Task.isCancelled else { return }

        scheduleIOSBackgroundRefreshIfPossible()
    }

    func syncSharedConfigurationNow() async {
        guard isSharedConfigurationEnabled else {
            updateSharedConfigurationSyncState(.disabled, logEvent: false)
            return
        }

        guard sharedConfigurationStore.isAvailable else {
            updateSharedConfigurationSyncState(
                .unavailable,
                logEvent: true
            )
            return
        }

        let startedAt = Date()
        updateSharedConfigurationSyncState(.syncing, logEvent: true)

        guard sharedConfigurationStore.requestSync() else {
            updateSharedConfigurationSyncState(
                .failed(
                    message: "The app could not start an iCloud shared-settings sync request.",
                    at: startedAt
                ),
                logEvent: true
            )
            return
        }

        let localUpdatedAt = lastSettingsMutationAt
        if let sharedConfiguration = sharedConfigurationStore.loadConfiguration() {
            if sharedConfiguration.updatedAt > localUpdatedAt {
                applySharedConfigurationIfNewer(sharedConfiguration)
                return
            }

            if sharedConfiguration.updatedAt < localUpdatedAt {
                sharedConfigurationStore.saveConfiguration(
                    currentSharedConfiguration(updatedAt: localUpdatedAt)
                )
                updateSharedConfigurationSyncState(
                    .succeeded(
                        message: "Requested an iCloud update with this device's newer settings.",
                        at: startedAt
                    ),
                    logEvent: true
                )
                return
            }

            updateSharedConfigurationSyncState(
                .succeeded(
                    message: "This device already matches the current iCloud shared settings.",
                    at: startedAt
                ),
                logEvent: true
            )
            return
        }

        sharedConfigurationStore.saveConfiguration(
            currentSharedConfiguration(updatedAt: localUpdatedAt)
        )
        updateSharedConfigurationSyncState(
            .succeeded(
                message: "No shared iCloud settings were found, so this device requested an initial upload.",
                at: startedAt
            ),
            logEvent: true
        )
    }

    func runIOSBackgroundRefreshVerificationNow() async {
        guard canRunIOSBackgroundRefreshVerification else { return }
        await handleIOSBackgroundRefreshTask()
    }

    func startBookingSetup() {
        runBookingPublishDryRun()
    }

    func runBookingDryRunForHarness() async -> Bool {
        if isAppleCalendarEnabled {
            await refreshAppleCalendars()
        }

        return createBookingSiteBuild()
    }

    @discardableResult
    func runBookingPublishDryRun() -> Bool {
        if !bookingPageURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Task { @MainActor [weak self] in
                await self?.verifyBookingPagePublished()
            }
            return false
        }

        return createBookingSiteBuild()
    }

    @discardableResult
    func createBookingSiteBuild() -> Bool {
        do {
            let result = try writeBookingSiteBuild()
            updateBookingSetupSnapshot(
                BookingSetupSnapshot(
                    pageStatus: .generatedLocally,
                    inboxStatus: bookingSetupSnapshot.inboxStatus == .notConnected ? .needsCheck : bookingSetupSnapshot.inboxStatus,
                    pendingRequestCount: bookingSetupSnapshot.pendingRequestCount,
                    lastMessage: "Page files are ready at \(bookingSiteBuildOutputURL.path)."
                ),
                auditDetail: "Generated \(result.writtenFileCount) booking page files from \(result.busyIntervalCount) local busy interval(s)."
            )
            return true
        } catch {
            updateBookingSetupSnapshot(
                BookingSetupSnapshot(
                    pageStatus: .publishFailed,
                    inboxStatus: bookingSetupSnapshot.inboxStatus,
                    pendingRequestCount: bookingSetupSnapshot.pendingRequestCount,
                    lastMessage: "Could not generate page files. Check file access, then try again."
                ),
                auditDetail: "Could not generate booking page files. \(error.localizedDescription)"
            )
            return false
        }
    }

    @discardableResult
    func prepareBookingPageTemplateFolder() -> Bool {
        do {
            let didSeed = try BookingStaticSiteWriter.seedEditableTemplate(
                at: bookingEditableTemplateURL,
                fileManager: fileManager
            )
            updateBookingSetupSnapshot(
                BookingSetupSnapshot(
                    pageStatus: bookingSetupSnapshot.pageStatus,
                    inboxStatus: bookingSetupSnapshot.inboxStatus,
                    pendingRequestCount: bookingSetupSnapshot.pendingRequestCount,
                    lastMessage: didSeed
                        ? "Editable page template files are ready at \(bookingEditableTemplateURL.path)."
                        : "Editable page template files are at \(bookingEditableTemplateURL.path)."
                ),
                auditDetail: didSeed
                    ? "Seeded editable booking page template files."
                    : "Opened existing editable booking page template files."
            )
            return true
        } catch {
            updateBookingSetupSnapshot(
                BookingSetupSnapshot(
                    pageStatus: bookingSetupSnapshot.pageStatus,
                    inboxStatus: bookingSetupSnapshot.inboxStatus,
                    pendingRequestCount: bookingSetupSnapshot.pendingRequestCount,
                    lastMessage: "Could not prepare editable page template files."
                ),
                auditDetail: "Could not prepare editable booking page template files. \(error.localizedDescription)"
            )
            return false
        }
    }

    private func writeBookingSiteBuild() throws -> BookingSiteBuildWriteResult {
        let now = Date()
        let calendar = Calendar.current
        let busyIntervals = try bookingBusyIntervalsForDraft(now: now, calendar: calendar)
        let secrets = try loadOrCreateBookingSecrets()
        let draft = try BookingDraftFactory.makeDraft(
            now: now,
            inboxURL: URL(string: bookingInboxURLString.trimmingCharacters(in: .whitespacesAndNewlines)),
            busyIntervals: busyIntervals,
            secrets: secrets,
            appointmentTypes: bookingAppointmentTypes,
            profile: bookingResolvedProfile,
            theme: bookingResolvedTheme,
            shareID: bookingResolvedShareID,
            calendar: calendar
        )
        let artifacts = try BookingStaticSiteGenerator.artifacts(
            configuration: draft.configuration,
            slots: draft.slots,
            generatedAt: draft.generatedAt,
            expiresAt: draft.expiresAt
        )
        let fingerprint = try BookingPublicationFingerprint.publicSiteFingerprint(configuration: draft.configuration)
        try BookingStaticSiteWriter.seedEditableTemplate(
            at: bookingEditableTemplateURL,
            fileManager: fileManager
        )
        let summary = try BookingStaticSiteWriter.write(
            artifacts: artifacts,
            to: bookingSiteBuildOutputURL,
            templateDirectory: bookingEditableTemplateURL,
            fileManager: fileManager
        )
        recordBookingGeneratedVersion(fingerprint: fingerprint, generatedAt: now)
        return BookingSiteBuildWriteResult(
            writtenFileCount: summary.writtenRelativePaths.count,
            busyIntervalCount: busyIntervals.count
        )
    }

    private func bookingBusyIntervalsForDraft(now: Date, calendar: Calendar) throws -> [BookingBusyInterval] {
        guard
            isAppleCalendarEnabled,
            appleCalendarAuthorizationState == .granted,
            let selectedAppleCalendar
        else {
            return []
        }

        let participant = BusyMirrorParticipant(
            provider: .apple,
            accountID: nil,
            calendarID: selectedAppleCalendar.id,
            displayName: selectedAppleCalendar.displayName
        )
        let window = BookingDraftFactory.busyLookupWindow(
            startingAt: now,
            appointmentTypes: bookingAppointmentTypes,
            calendar: calendar
        )

        return try appleCalendarService.listBusySourceEvents(
            in: participant,
            window: window
        ).compactMap { event in
            guard event.endDate > event.startDate else {
                return nil
            }

            return BookingBusyInterval(
                interval: DateInterval(start: event.startDate, end: event.endDate)
            )
        }
    }

    func verifyBookingPagePublished() async {
        let trimmedURL = bookingPageURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedURL),
              let scheme = url.scheme?.lowercased(),
              scheme == "https",
              url.host?.isEmpty == false
        else {
            updateBookingSetupSnapshot(
                BookingSetupSnapshot(
                    pageStatus: .publishFailed,
                    inboxStatus: bookingSetupSnapshot.inboxStatus,
                    pendingRequestCount: bookingSetupSnapshot.pendingRequestCount,
                    lastMessage: BookingCopy.Validation.repositoryNotFound
                ),
                auditDetail: BookingCopy.Validation.repositoryNotFound
            )
            return
        }

        do {
            var request = URLRequest(url: bookingSiteConfigURL(for: url))
            request.httpMethod = "GET"
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode)
            else {
                throw BookingRelayClientError.invalidResponse
            }
            let servedFingerprint = try servedBookingFingerprint(from: data)
            let expectedFingerprint = bookingLastGeneratedFingerprintString.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !expectedFingerprint.isEmpty, servedFingerprint == expectedFingerprint else {
                recordBookingServedVersion(fingerprint: servedFingerprint, verifiedAt: nil)
                updateBookingSetupSnapshot(
                    BookingSetupSnapshot(
                        pageStatus: .publishFailed,
                        inboxStatus: bookingSetupSnapshot.inboxStatus,
                        pendingRequestCount: bookingSetupSnapshot.pendingRequestCount,
                        lastMessage: "The live page is reachable, but it is not serving the latest generated version."
                    ),
                    auditDetail: "Booking page verification failed because the served fingerprint did not match the expected version."
                )
                return
            }
            recordBookingServedVersion(fingerprint: servedFingerprint, verifiedAt: Date())

            updateBookingSetupSnapshot(
                BookingSetupSnapshot(
                    pageStatus: .published,
                    inboxStatus: bookingSetupSnapshot.inboxStatus,
                    pendingRequestCount: bookingSetupSnapshot.pendingRequestCount,
                    lastMessage: BookingCopy.Validation.publishSucceeded
                ),
                auditDetail: BookingCopy.Validation.publishSucceeded
            )
        } catch {
            updateBookingSetupSnapshot(
                BookingSetupSnapshot(
                    pageStatus: .publishFailed,
                    inboxStatus: bookingSetupSnapshot.inboxStatus,
                    pendingRequestCount: bookingSetupSnapshot.pendingRequestCount,
                    lastMessage: BookingCopy.Validation.publishFailed
                ),
                auditDetail: BookingCopy.Validation.publishFailed
            )
        }
    }

    func checkBookingInbox() async {
        let trimmedURL = bookingInboxURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedURL),
              let relayURL = try? BookingRelayURL(url)
        else {
            updateBookingSetupSnapshot(
                BookingSetupSnapshot(
                    pageStatus: bookingSetupSnapshot.pageStatus,
                    inboxStatus: .cannotReachInbox,
                    pendingRequestCount: bookingSetupSnapshot.pendingRequestCount,
                    lastMessage: BookingCopy.Validation.inboxUnreachable
                ),
                auditDetail: BookingCopy.Validation.inboxUnreachable
            )
            return
        }

        do {
            let request = BookingRelayRequestBuilder.healthRequest(relayURL: relayURL)
            let (data, response) = try await URLSession.shared.data(for: request)
            let health = try? JSONDecoder().decode(BookingRelayHealthResponse.self, from: data)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode)
            else {
                if health?.storageReady == false {
                    throw BookingConfigurationError.invalidField(
                        "Vercel Blob storage is not ready. Redeploy the Vercel inbox so the app can create and connect Blob storage."
                    )
                }
                throw BookingRelayClientError.invalidResponse
            }
            if health?.storageReady == false {
                throw BookingConfigurationError.invalidField(
                    "Vercel Blob storage is not ready. Redeploy the Vercel inbox so the app can create and connect Blob storage."
                )
            }
            let expectedOrigin = bookingExpectedAllowedOriginString
            if let allowedOrigin = health?.allowedOrigin,
               !expectedOrigin.isEmpty,
               allowedOrigin != expectedOrigin
            {
                updateBookingSetupSnapshot(
                    BookingSetupSnapshot(
                        pageStatus: bookingSetupSnapshot.pageStatus,
                        inboxStatus: .allowedOriginMismatch,
                        pendingRequestCount: bookingSetupSnapshot.pendingRequestCount,
                        lastMessage: "Inbox is reachable, but ALLOWED_ORIGIN is \(allowedOrigin) instead of \(expectedOrigin)."
                    ),
                    auditDetail: "Booking inbox allowed origin mismatch."
                )
                return
            }

            let nextStatus: BookingInboxStatus = bookingInboxAdminTokenString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? .reachable
                : .connected

            updateBookingSetupSnapshot(
                BookingSetupSnapshot(
                    pageStatus: bookingSetupSnapshot.pageStatus,
                    inboxStatus: nextStatus,
                    pendingRequestCount: bookingSetupSnapshot.pendingRequestCount,
                    lastMessage: BookingCopy.Validation.inboxReachable
                ),
                auditDetail: BookingCopy.Validation.inboxReachable
            )
        } catch {
            updateBookingSetupSnapshot(
                BookingSetupSnapshot(
                    pageStatus: bookingSetupSnapshot.pageStatus,
                    inboxStatus: .cannotReachInbox,
                    pendingRequestCount: bookingSetupSnapshot.pendingRequestCount,
                    lastMessage: BookingCopy.Validation.inboxUnreachable
                ),
                auditDetail: BookingCopy.Validation.inboxUnreachable
            )
        }
    }

    func deployBookingVercelInbox() async {
        guard !isBookingVercelDeploymentInFlight else { return }

        isBookingVercelDeploymentInFlight = true
        defer { isBookingVercelDeploymentInFlight = false }

        do {
            let adminToken = try bookingInboxAdminTokenForVercelDeployment()
            let configuration = try BookingVercelDeploymentConfiguration(
                token: bookingVercelTokenString,
                project: BookingVercelProjectReference(bookingVercelProjectNameString),
                team: BookingVercelTeamReference(bookingVercelScopeString),
                allowedOrigin: bookingExpectedAllowedOriginString,
                inboxAdminToken: adminToken
            )
            let templateDirectory = try BookingVercelDeploymentClient.defaultTemplateDirectory(fileManager: fileManager)
            let result = try await BookingVercelDeploymentClient().deploy(
                configuration: configuration,
                templateDirectory: templateDirectory,
                fileManager: fileManager
            )

            bookingInboxAdminTokenString = adminToken
            bookingInboxURLString = result.inboxURL.absoluteString
            updateBookingSetupSnapshot(
                BookingSetupSnapshot(
                    pageStatus: bookingSetupSnapshot.pageStatus,
                    inboxStatus: .configured,
                    pendingRequestCount: bookingSetupSnapshot.pendingRequestCount,
                    lastMessage: "Vercel inbox deployed with Blob storage. Checking the inbox now."
                ),
                auditDetail: "Vercel booking inbox deployed as \(result.deploymentID) with Blob store \(result.blobStoreID)."
            )
            await checkBookingInbox()
        } catch {
            let message = Self.bookingConfigurationErrorMessage(error)
            updateBookingSetupSnapshot(
                BookingSetupSnapshot(
                    pageStatus: bookingSetupSnapshot.pageStatus,
                    inboxStatus: .cannotReachInbox,
                    pendingRequestCount: bookingSetupSnapshot.pendingRequestCount,
                    lastMessage: message
                ),
                auditDetail: "Vercel booking inbox deployment failed. \(message)"
            )
        }
    }

    func sendBookingTestRequest() async {
        guard !isBookingTestRequestInFlight else { return }
        guard bookingSetupSnapshot.isReady,
              let bookingPageURL = URL(string: bookingPageURLString.trimmingCharacters(in: .whitespacesAndNewlines)),
              let inboxURL = URL(string: bookingInboxURLString.trimmingCharacters(in: .whitespacesAndNewlines)),
              let relayURL = try? BookingRelayURL(inboxURL)
        else {
            updateBookingSetupSnapshot(
                BookingSetupSnapshot(
                    pageStatus: bookingSetupSnapshot.pageStatus,
                    inboxStatus: bookingSetupSnapshot.inboxStatus,
                    pendingRequestCount: bookingSetupSnapshot.pendingRequestCount,
                    lastMessage: BookingCopy.Validation.testRequestMissing
                ),
                auditDetail: BookingCopy.Validation.testRequestMissing
            )
            return
        }

        isBookingTestRequestInFlight = true
        defer { isBookingTestRequestInFlight = false }

        do {
            try await BookingTestRequestSender().sendTestRequest(
                bookingPageURL: bookingPageURL,
                inboxURL: relayURL
            )
            updateBookingSetupSnapshot(
                BookingSetupSnapshot(
                    pageStatus: bookingSetupSnapshot.pageStatus,
                    inboxStatus: bookingSetupSnapshot.inboxStatus,
                    pendingRequestCount: max(1, bookingSetupSnapshot.pendingRequestCount + 1),
                    lastMessage: BookingCopy.Validation.testRequestSent
                ),
                auditDetail: BookingCopy.Validation.testRequestSent
            )
        } catch {
            updateBookingSetupSnapshot(
                BookingSetupSnapshot(
                    pageStatus: bookingSetupSnapshot.pageStatus,
                    inboxStatus: bookingSetupSnapshot.inboxStatus,
                    pendingRequestCount: bookingSetupSnapshot.pendingRequestCount,
                    lastMessage: BookingCopy.Validation.testRequestFailed
                ),
                auditDetail: BookingCopy.Validation.testRequestFailed
            )
        }
    }

    func importBookingRequests() async {
        guard !isBookingImportInFlight else { return }
        guard let inboxURL = URL(string: bookingInboxURLString.trimmingCharacters(in: .whitespacesAndNewlines)),
              let relayURL = try? BookingRelayURL(inboxURL)
        else {
            updateBookingSetupSnapshot(
                BookingSetupSnapshot(
                    pageStatus: bookingSetupSnapshot.pageStatus,
                    inboxStatus: .cannotReachInbox,
                    pendingRequestCount: bookingSetupSnapshot.pendingRequestCount,
                    lastMessage: BookingCopy.Validation.inboxUnreachable
                ),
                auditDetail: BookingCopy.Validation.inboxUnreachable
            )
            return
        }

        let adminTokenValue = bookingInboxAdminTokenString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !adminTokenValue.isEmpty else {
            updateBookingSetupSnapshot(
                BookingSetupSnapshot(
                    pageStatus: bookingSetupSnapshot.pageStatus,
                    inboxStatus: bookingSetupSnapshot.inboxStatus,
                    pendingRequestCount: bookingSetupSnapshot.pendingRequestCount,
                    lastMessage: "Deploy the Vercel inbox before importing requests."
                ),
                auditDetail: "Vercel inbox secret is missing."
            )
            return
        }

        isBookingImportInFlight = true
        defer { isBookingImportInFlight = false }

        do {
            let secrets = try loadExistingBookingSecrets()
            let client = BookingRelayClient(
                relayURL: relayURL,
                adminToken: BookingRelayAdminToken(rawValue: adminTokenValue)
            )
            var cursor: String?
            var importedCount = 0
            var skippedCount = 0
            var importedRequestIDs: [BookingRequestID] = []
            repeat {
                let page = try await client.fetchRequests(
                    inboxID: secrets.inboxID,
                    cursor: cursor
                )
                for envelope in page.requests {
                    guard !importedBookingRequests.contains(where: { $0.id == envelope.requestID }) else {
                        continue
                    }
                    do {
                        importedBookingRequests.append(
                            try importBookingRequestEnvelope(
                                envelope,
                                secrets: secrets,
                                now: Date()
                            )
                        )
                        importedRequestIDs.append(envelope.requestID)
                        importedCount += 1
                    } catch {
                        skippedCount += 1
                        appendAuditTrailEntry(
                            title: "Skipped booking request",
                            detail: "Request \(envelope.requestID.rawValue) could not be imported. \(error.localizedDescription)",
                            status: "warning"
                        )
                    }
                }
                cursor = page.cursor
            } while cursor?.isEmpty == false

            for requestID in importedRequestIDs {
                guard let request = importedBookingRequests.first(where: { $0.id == requestID }),
                      shouldAutomaticallyApproveBookingRequest(request)
                else {
                    continue
                }

                await approveBookingRequest(requestID)
            }

            let automaticallyApprovedCount = importedRequestIDs.filter { requestID in
                importedBookingRequests.first { $0.id == requestID }?.status == .approved
            }.count
            let pendingCount = importedBookingRequests.filter(\.canApprove).count
            updateBookingSetupSnapshot(
                BookingSetupSnapshot(
                    pageStatus: bookingSetupSnapshot.pageStatus,
                    inboxStatus: .connected,
                    pendingRequestCount: pendingCount,
                    lastMessage: bookingImportMessage(
                        importedCount: importedCount,
                        automaticallyApprovedCount: automaticallyApprovedCount,
                        skippedCount: skippedCount
                    )
                ),
                auditDetail: bookingImportAuditDetail(
                    importedCount: importedCount,
                    automaticallyApprovedCount: automaticallyApprovedCount,
                    skippedCount: skippedCount
                )
            )
        } catch {
            updateBookingSetupSnapshot(
                BookingSetupSnapshot(
                    pageStatus: bookingSetupSnapshot.pageStatus,
                    inboxStatus: bookingSetupSnapshot.inboxStatus,
                    pendingRequestCount: bookingSetupSnapshot.pendingRequestCount,
                    lastMessage: "Could not import booking requests. Check the inbox token, then try again."
                ),
                auditDetail: "Could not import booking requests. \(error.localizedDescription)"
            )
        }
    }

    private func bookingImportMessage(
        importedCount: Int,
        automaticallyApprovedCount: Int,
        skippedCount: Int
    ) -> String {
        if importedCount == 0, skippedCount > 0 {
            return "Skipped \(skippedCount) booking request(s) that no longer match this device."
        }

        guard importedCount > 0 else {
            return BookingCopy.Validation.testRequestMissing
        }

        let skipSuffix = skippedCount > 0 ? " Skipped \(skippedCount) incompatible request(s)." : ""

        guard automaticallyApprovedCount > 0 else {
            return "Imported \(importedCount) booking request(s).\(skipSuffix)"
        }

        return "Imported \(importedCount) booking request(s) and automatically accepted \(automaticallyApprovedCount).\(skipSuffix)"
    }

    private func bookingImportAuditDetail(
        importedCount: Int,
        automaticallyApprovedCount: Int,
        skippedCount: Int
    ) -> String {
        if importedCount == 0, skippedCount > 0 {
            return "Skipped \(skippedCount) encrypted booking request(s) that could not be imported."
        }

        guard importedCount > 0 else {
            return "No new booking requests were available."
        }

        let skipSuffix = skippedCount > 0 ? " Skipped \(skippedCount) incompatible encrypted request(s)." : ""

        guard automaticallyApprovedCount > 0 else {
            return "Imported \(importedCount) encrypted booking request(s).\(skipSuffix)"
        }

        return "Imported \(importedCount) encrypted booking request(s) and automatically accepted \(automaticallyApprovedCount).\(skipSuffix)"
    }

    func approveBookingRequest(_ requestID: BookingRequestID) async {
        guard !isBookingApprovalInFlight else { return }
        guard let requestIndex = importedBookingRequests.firstIndex(where: { $0.id == requestID }) else {
            return
        }
        guard importedBookingRequests[requestIndex].canApprove else {
            return
        }

        isBookingApprovalInFlight = true
        defer { isBookingApprovalInFlight = false }

        do {
            let request = importedBookingRequests[requestIndex]
            let approval = try await createApprovedBookingEvent(for: request)
            do {
                try await deleteBookingRequestFromInbox(request)
            } catch {
                appendAuditTrailEntry(
                    title: "Booking",
                    detail: "Booking was added to the calendar, but the app could not remove the encrypted inbox record.",
                    status: "failed"
                )
            }
            markBookingRequest(
                requestID,
                status: .approved,
                message: approvalMessage(for: approval),
                calendarEventID: approval.event.eventID
            )
        } catch BookingApprovalError.slotUnavailable {
            markBookingRequest(
                requestID,
                status: .unavailable,
                message: BookingCopy.Validation.slotNoLongerOpen
            )
        } catch BookingApprovalError.missingCalendar {
            markBookingRequest(
                requestID,
                status: .failed,
                message: "Select an Apple or Google calendar before approving this request."
            )
        } catch {
            markBookingRequest(
                requestID,
                status: .failed,
                message: BookingCopy.Validation.calendarWriteFailed
            )
        }
    }

    private func createApprovedBookingEvent(for request: BookingImportedRequest) async throws -> BookingApprovalResult {
        guard let appointmentType = bookingAppointmentType(for: request) else {
            throw BookingApprovalError.missingCalendar
        }

        if let calendar = bookingAppleCalendarTarget(for: appointmentType) {
            guard try bookingRequestSlotIsStillOpen(request) else {
                throw BookingApprovalError.slotUnavailable
            }

            let inviteFileURL: URL?
            if calendar.isLikelyICloud {
                inviteFileURL = try bookingInviteFileWriter.writeInviteFile(
                    for: request,
                    calendarName: calendar.displayName
                )
            } else {
                inviteFileURL = nil
            }

            let event = try appleCalendarService.createBookingEvent(
                in: calendar,
                request: request
            )
            return BookingApprovalResult(event: event, inviteFileURL: inviteFileURL)
        }

        guard let target = bookingGoogleCalendarTarget(for: appointmentType) else {
            throw BookingApprovalError.missingCalendar
        }

        let accountID = target.account.id
        let storedAccount = target.account
        let calendar = target.calendar
        let authorizedAccount = try await GoogleSignInService.authorizeStoredAccount(storedAccount)
        try replaceStoredGoogleAccount(authorizedAccount.storedAccount)
        guard try await bookingRequestSlotIsStillOpen(
            request,
            googleCalendar: calendar,
            accountID: accountID,
            accessToken: authorizedAccount.accessToken
        ) else {
            throw BookingApprovalError.slotUnavailable
        }

        let event = try await googleCalendarService.createBookingEvent(
            in: calendar,
            accessToken: authorizedAccount.accessToken,
            request: request,
            createsGoogleMeet: appointmentType.location.mode == .googleMeet
        )
        return BookingApprovalResult(
            event: AppleManagedEventRecord(
                calendarID: event.calendarID,
                calendarName: event.calendarName,
                eventID: event.eventID,
                summary: event.summary,
                windowDescription: event.windowDescription
            ),
            inviteFileURL: nil
        )
    }

    private func bookingAppointmentType(for request: BookingImportedRequest) -> BookingAppointmentType? {
        bookingAppointmentTypes.first { $0.id == request.plaintext.appointmentTypeID }
    }

    private func shouldAutomaticallyApproveBookingRequest(_ request: BookingImportedRequest) -> Bool {
        isAutomaticBookingApprovalEnabled
            || bookingAppointmentType(for: request)?.isAutoConfirmEnabled == true
    }

    private func approvalMessage(for approval: BookingApprovalResult) -> String {
        var message = "\(BookingCopy.Validation.calendarWriteSucceeded) Added \(approval.event.windowDescription)."
        if let inviteFileURL = approval.inviteFileURL {
            message += " Invite file saved to \(inviteFileURL.lastPathComponent)."
        }
        return message
    }

    func declineBookingRequest(_ requestID: BookingRequestID) async {
        guard !isBookingApprovalInFlight else { return }
        guard let request = importedBookingRequests.first(where: { $0.id == requestID }) else {
            return
        }

        isBookingApprovalInFlight = true
        defer { isBookingApprovalInFlight = false }

        do {
            let decline = try await createDeclinedBookingNotice(for: request)
            do {
                try await deleteBookingRequestFromInbox(request)
            } catch {
                appendAuditTrailEntry(
                    title: "Booking",
                    detail: "Decline notice was prepared, but the app could not remove the encrypted inbox record.",
                    status: "failed"
                )
            }
            markBookingRequest(
                requestID,
                status: .declined,
                message: declineMessage(for: decline)
            )
        } catch BookingApprovalError.missingCalendar {
            markBookingRequest(
                requestID,
                status: .failed,
                message: "Select an Apple or Google calendar before declining this request."
            )
        } catch {
            markBookingRequest(
                requestID,
                status: .failed,
                message: "Could not decline the request. Check calendar access and the inbox token, then try again."
            )
        }
    }

    private func createDeclinedBookingNotice(for request: BookingImportedRequest) async throws -> BookingDeclineResult {
        guard let appointmentType = bookingAppointmentType(for: request) else {
            throw BookingApprovalError.missingCalendar
        }

        if let calendar = bookingAppleCalendarTarget(for: appointmentType), isAppleCalendarEnabled {
            let inviteFileURL = try bookingInviteFileWriter.writeDeclineFile(
                for: request,
                calendarName: calendar.displayName
            )
            return BookingDeclineResult(event: nil, inviteFileURL: inviteFileURL)
        }

        guard let target = bookingGoogleCalendarTarget(for: appointmentType)
        else {
            throw BookingApprovalError.missingCalendar
        }

        let storedAccount = target.account
        let calendar = target.calendar
        let authorizedAccount = try await GoogleSignInService.authorizeStoredAccount(storedAccount)
        try replaceStoredGoogleAccount(authorizedAccount.storedAccount)
        let event = try await googleCalendarService.createDeclinedBookingEvent(
            in: calendar,
            accessToken: authorizedAccount.accessToken,
            request: request,
            ownerEmail: authorizedAccount.storedAccount.email
        )
        return BookingDeclineResult(event: event, inviteFileURL: nil)
    }

    private func declineMessage(for decline: BookingDeclineResult) -> String {
        if let event = decline.event {
            return "Request declined, Google Calendar notice sent for \(event.windowDescription), and removed from the inbox."
        }

        if let inviteFileURL = decline.inviteFileURL {
            return "Request declined and removed from the inbox. Decline file saved to \(inviteFileURL.lastPathComponent)."
        }

        return "Request declined and removed from the inbox."
    }

    func connectAppleCalendar() async {
        guard !isAppleCalendarOperationInFlight else { return }

        isAppleCalendarEnabled = true
        persistSettings()
        appleCalendarMessage = nil
        await refreshAppleCalendars()
    }

    func disconnectAppleCalendar() {
        guard !isAppleCalendarOperationInFlight else { return }

        let previousCalendarID = selectedAppleCalendarID
        isAppleCalendarEnabled = false
        clearAppleCalendarState()
        appleCalendarMessage = "Apple Calendar was disconnected for this app. System calendar permission remains managed in Settings."
        refreshAppleCalendarAuthorizationState()
        persistSettings()

        Task { @MainActor [weak self] in
            await self?.cleanupDeselectedAppleCalendar(calendarID: previousCalendarID)
            await self?.syncAfterParticipantConfigurationChange()
        }
    }

    func openAppleCalendarSettings() async {
        guard canOpenAppleCalendarSettings else { return }

        let authorizationStateBeforeOpening = appleCalendarAuthorizationState
        if authorizationStateBeforeOpening == .notDetermined {
            do {
                _ = try await appleCalendarService.requestAccessIfNeeded()
            } catch {
                refreshAppleCalendarAuthorizationState()
            }
        }

        refreshAppleCalendarAuthorizationState()

        if appleCalendarSettingsOpener.openCalendarAccessSettings() {
            if authorizationStateBeforeOpening == .notDetermined && appleCalendarAuthorizationState == .notDetermined {
                appleCalendarMessage = "Opened System Settings to Privacy & Security > Calendars. If this app still is not listed there, click Connect Apple Calendar from the app to trigger the macOS permission prompt first."
            } else {
                appleCalendarMessage = "Opened System Settings to Privacy & Security > Calendars."
            }
        } else {
            appleCalendarMessage = "Calendar privacy settings could not be opened from this app. Open System Settings > Privacy & Security > Calendars manually."
        }
    }

    func refreshAppleCalendars() async {
        guard isAppleCalendarEnabled else {
            appleCalendarMessage = "Connect Apple Calendar before loading calendars."
            return
        }
        guard !isAppleCalendarOperationInFlight else { return }

        isAppleCalendarOperationInFlight = true
        appleCalendarMessage = nil
        refreshAppleCalendarAuthorizationState()

        defer {
            isAppleCalendarOperationInFlight = false
        }

        do {
            _ = try await appleCalendarService.requestAccessIfNeeded()
            refreshAppleCalendarAuthorizationState()
            let calendars = try appleCalendarService.listWritableCalendars()
            appleCalendars = calendars
            let previousCalendarID = selectedAppleCalendarID
            selectedAppleCalendarID = AppleCalendarSelectionResolver.resolvedCalendarID(
                availableCalendars: calendars,
                persistedCalendarID: selectedAppleCalendarID,
                sharedReference: persistedAppleCalendarReference
            )
            persistedAppleCalendarReference = selectedAppleCalendar.map(SharedAppleCalendarReference.init(calendar:))
            if let selectedAppleCalendar {
                appleCalendarMessage = "Loaded \(calendars.count) writable Apple calendars. Selected \(selectedAppleCalendar.displayName)."
            } else {
                appleCalendarMessage = "No writable Apple calendars were found on this device."
            }
            if previousCalendarID == selectedAppleCalendarID {
                await syncAfterParticipantConfigurationChange()
            }
        } catch let error as AppleCalendarServiceError {
            refreshAppleCalendarAuthorizationState()
            appleCalendarMessage = error.localizedDescription
        } catch {
            refreshAppleCalendarAuthorizationState()
            appleCalendarMessage = "Apple Calendar could not be loaded from this app session."
        }
    }

    func createManagedAppleEvent() async {
        guard let calendar = selectedAppleCalendar else {
            appleCalendarMessage = "Select a writable Apple calendar before creating a managed busy slot."
            return
        }

        await performAppleCalendarOperation {
            let event = try appleCalendarService.createManagedBusyEvent(in: calendar)
            lastManagedAppleEvent = event
            appleCalendarMessage = "Created a managed busy slot in \(calendar.displayName) for \(event.windowDescription)."
        }
    }

    func deleteManagedAppleEvent() async {
        guard let event = lastManagedAppleEvent else {
            appleCalendarMessage = "There is no managed busy slot to delete yet."
            return
        }

        await performAppleCalendarOperation {
            try appleCalendarService.deleteManagedBusyEvent(event)
            lastManagedAppleEvent = nil
            appleCalendarMessage = "Deleted the managed busy slot from \(event.calendarName)."
        }
    }

    func syncNow() async {
        guard !isSyncInFlight else { return }

        isSyncInFlight = true
        syncMessage = nil
        appendAuditTrailEntry(
            title: "Busy mirror sync",
            detail: "Started reconciling selected calendars.",
            status: "working"
        )

        defer {
            isSyncInFlight = false
        }

        do {
            let participantsBundle = try await collectSyncParticipants()
            guard !participantsBundle.participants.isEmpty else {
                lastBusyMirrorSyncSummary = nil
                syncMessage = "Select calendars to manage mirrored busy holds. Two or more selected calendars create new mirrors."
                return
            }

            let window = BusyMirrorSyncWindow.defaultWindow()
            var sourceEvents: [BusyMirrorSourceEvent] = []
            var existingMirrors: [ExistingBusyMirrorEvent] = []
            var existingBusyBlocks: [BusyMirrorTargetBusyBlock] = []

            for participant in participantsBundle.participants {
                await yieldForIOSSyncResponsivenessIfNeeded()
                switch participant.provider {
                case .google:
                    guard
                        let accountID = participant.accountID,
                        let authorizedAccount = participantsBundle.googleAccountsByID[accountID],
                        let googleCalendar = participantsBundle.googleCalendarsByAccountID[accountID]
                    else {
                        continue
                    }

                    sourceEvents.append(
                        contentsOf: try await googleCalendarService.listBusySourceEvents(
                            in: participant,
                            calendarTimeZone: googleCalendar.timeZone,
                            window: window,
                            accessToken: authorizedAccount.accessToken
                        )
                    )
                    existingMirrors.append(
                        contentsOf: try await googleCalendarService.listManagedMirrorEvents(
                            in: participant,
                            calendarTimeZone: googleCalendar.timeZone,
                            window: window,
                            accessToken: authorizedAccount.accessToken
                        )
                    )
                    existingBusyBlocks.append(
                        contentsOf: try await googleCalendarService.listBusyTargetBlocks(
                            in: participant,
                            calendarTimeZone: googleCalendar.timeZone,
                            window: window,
                            accessToken: authorizedAccount.accessToken
                        )
                    )
                case .apple:
                    sourceEvents.append(
                        contentsOf: try appleCalendarService.listBusySourceEvents(
                            in: participant,
                            window: window
                        )
                    )
                    existingMirrors.append(
                        contentsOf: try appleCalendarService.listManagedMirrorEvents(
                            in: participant,
                            window: window
                        )
                    )
                    existingBusyBlocks.append(
                        contentsOf: try appleCalendarService.listBusyTargetBlocks(
                            in: participant,
                            window: window
                        )
                    )
                }
                await yieldForIOSSyncResponsivenessIfNeeded()
            }

            let desiredMirrors = BusyMirrorSyncPlanner.desiredMirrors(
                participants: participantsBundle.participants,
                sourceEvents: sourceEvents
            )
            let operations = BusyMirrorSyncPlanner.operations(
                desiredMirrors: desiredMirrors,
                existingMirrors: existingMirrors,
                existingBusyBlocks: existingBusyBlocks
            )

            var createdCount = 0
            var updatedCount = 0
            var deletedCount = 0
            var failureMessages: [String] = []

            for operation in operations {
                await yieldForIOSSyncResponsivenessIfNeeded()
                do {
                    try await applySyncOperation(operation, participantsBundle: participantsBundle)
                    switch operation {
                    case .create:
                        createdCount += 1
                    case .update:
                        updatedCount += 1
                    case .delete:
                        deletedCount += 1
                    }
                } catch {
                    let failureMessage = syncFailureMessage(for: operation, error: error)
                    failureMessages.append(failureMessage)
                }
                await yieldForIOSSyncResponsivenessIfNeeded()
            }

            let summary = BusyMirrorSyncSummary(
                participantCount: participantsBundle.participants.count,
                sourceEventCount: sourceEvents.count,
                createdCount: createdCount,
                updatedCount: updatedCount,
                deletedCount: deletedCount,
                failedCount: failureMessages.count,
                completedAt: Date(),
                failureMessages: failureMessages
            )

            lastBusyMirrorSyncSummary = summary
            if failureMessages.isEmpty {
                if summary.participantCount == 1 {
                    syncMessage = summary.deletedCount == 0
                        ? "Only one calendar is selected, so no new mirrored busy holds are needed."
                        : "Only one calendar is selected. Removed stale mirrored busy holds from the remaining calendar."
                } else {
                    syncMessage = "Syncing completed across \(summary.participantCount) calendars."
                }
            } else {
                syncMessage = "Busy mirroring completed with \(summary.failedCount) failed write(s)."
            }

            appendAuditTrailEntry(
                title: "Busy mirror sync",
                detail: "Created \(summary.createdCount), updated \(summary.updatedCount), deleted \(summary.deletedCount), failed \(summary.failedCount).",
                status: failureMessages.isEmpty ? "ready" : "failed",
                occurredAt: summary.completedAt
            )
            for failureMessage in failureMessages {
                appendAuditTrailEntry(
                    title: "Busy mirror sync failure",
                    detail: failureMessage,
                    status: "failed",
                    occurredAt: summary.completedAt
                )
            }
        } catch {
            lastBusyMirrorSyncSummary = BusyMirrorSyncSummary(
                participantCount: selectedParticipantCount,
                sourceEventCount: 0,
                createdCount: 0,
                updatedCount: 0,
                deletedCount: 0,
                failedCount: 1,
                completedAt: Date(),
                failureMessages: [error.localizedDescription]
            )
            syncMessage = error.localizedDescription
            appendAuditTrailEntry(
                title: "Busy mirror sync",
                detail: error.localizedDescription,
                status: "failed"
            )
        }
    }

    func connectGoogleAccount() async {
        await connectGoogleAccount(sharedDescriptor: nil)
    }

    func connectSharedGoogleAccount(_ descriptorID: String) async {
        guard let descriptor = sharedGoogleAccountDescriptors.first(where: { $0.id == descriptorID }) else {
            googleAuthMessage = "That shared Google account is no longer available."
            return
        }

        await connectGoogleAccount(sharedDescriptor: descriptor)
    }

    private func connectGoogleAccount(sharedDescriptor: SharedGoogleAccountDescriptor?) async {
        guard !isGoogleAuthInFlight else { return }
        if let blockingReason = googleSignInEnvironment.blockingReason {
            googleAuthMessage = blockingReason
            return
        }
        isGoogleAuthInFlight = true
        googleAuthMessage = nil

        defer {
            isGoogleAuthInFlight = false
        }

        do {
            let storedAccount = try await GoogleSignInService.signIn(
                using: googleOAuthResolution,
                hint: sharedDescriptor?.email ?? liveGoogleDebugConfiguration.preferredAccountEmail
            )
            if let sharedDescriptor,
               storedAccount.email.compare(sharedDescriptor.email, options: .caseInsensitive) != .orderedSame {
                GoogleSignInService.clearSavedSession()
                googleAuthMessage = "Google authorization completed as \(storedAccount.email), but this shared account expects \(sharedDescriptor.email)."
                return
            }
            if let mismatchMessage = liveGoogleEmailMismatchMessage(for: storedAccount) {
                GoogleSignInService.clearSavedSession()
                googleAuthMessage = mismatchMessage
                return
            }
            let accounts = try googleAccountStore.upsertAccount(storedAccount)
            googleSelectedCalendarIDs = GoogleSharedAccountHandoff.migratedSelectedCalendarIDs(
                currentSelectedCalendarIDs: googleSelectedCalendarIDs,
                connectedAccount: storedAccount,
                sharedDescriptors: sharedGoogleAccountDescriptors
            )
            updateGoogleStoredAccounts(accounts)
            activeGoogleAccountID = storedAccount.id
            reconcileSharedGoogleAccountDescriptorsWithLocalAccounts()
            persistSettings()
            googleAuthMessage = storedAccount.connectedAccount.serverAuthCodeAvailable
                ? "Google authorization succeeded. A server auth code was issued for backend exchange."
                : "Google authorization succeeded. Added \(storedAccount.displayName)."
            await refreshGoogleCalendars(
                for: storedAccount.id,
                preferredCalendarName: sharedDescriptor?.selectedCalendarDisplayName
            )
            await syncAfterParticipantConfigurationChange()
        } catch let error as GoogleSignInServiceError {
            googleAuthMessage = error.localizedDescription
        } catch let error as GoogleAccountStoreError {
            googleAuthMessage = error.localizedDescription
        } catch {
            googleAuthMessage = googleAuthorizationFailureMessage(for: error)
        }
    }

    func removeGoogleAccount(_ accountID: String) {
        guard !isGoogleAuthInFlight else { return }
        let previousCalendarID = googleSelectedCalendarIDs[accountID] ?? ""
        let removedAccountEmail = storedGoogleAccount(id: accountID)?.email
        do {
            GoogleSignInService.removeCurrentUserIfMatches(
                accountID: accountID,
                using: googleOAuthResolution
            )
            let accounts = try googleAccountStore.removeAccount(id: accountID)
            googleSelectedCalendarIDs[accountID] = nil
            updateGoogleStoredAccounts(accounts)
            removeSharedGoogleAccountDescriptor(
                matchingAccountID: accountID,
                email: removedAccountEmail
            )
            if activeGoogleAccountID == accountID {
                activeGoogleAccountID = accounts.first?.id
            }
            persistSettings()
            googleAuthMessage = accounts.isEmpty
                ? "Removed the Google account from this app."
                : "Removed the Google account from this app. \(accounts.count) Google account(s) remain connected."
            Task { @MainActor [weak self] in
                await self?.cleanupDeselectedGoogleCalendar(
                    accountID: accountID,
                    calendarID: previousCalendarID
                )
                await self?.syncAfterParticipantConfigurationChange()
            }
        } catch let error as GoogleAccountStoreError {
            googleAuthMessage = error.localizedDescription
        } catch {
            googleAuthMessage = "The Google account could not be removed from secure storage."
        }
    }

    func refreshGoogleCalendars(
        for accountID: String,
        preferredCalendarName: String? = nil
    ) async {
        guard let storedAccount = storedGoogleAccount(id: accountID) else {
            googleAuthMessage = "That Google account is no longer available in this app."
            return
        }
        guard !googleOperationAccountIDs.contains(accountID) else { return }

        googleOperationAccountIDs.insert(accountID)
        setGoogleMessage(nil, for: accountID)

        do {
            let authorizedAccount = try await GoogleSignInService.authorizeStoredAccount(storedAccount)
            try replaceStoredGoogleAccount(authorizedAccount.storedAccount)
            let calendars = try await googleCalendarService.listWritableCalendars(
                accessToken: authorizedAccount.accessToken
            )
            googleCalendarsByAccountID[accountID] = calendars
            let resolvedPreferredCalendarName = preferredCalendarName
                ?? sharedGoogleDescriptor(forAccountID: accountID, email: storedAccount.email)?.selectedCalendarDisplayName
                ?? (accountID == liveGoogleResolvedAccountID
                    ? liveGoogleDebugConfiguration.preferredCalendarName
                    : nil)
            let resolvedCalendarID = GoogleCalendarSelectionResolver.resolvedCalendarID(
                availableCalendars: calendars,
                persistedCalendarID: googleSelectedCalendarIDs[accountID] ?? "",
                preferredCalendarName: resolvedPreferredCalendarName
            )
            let previousCalendarID = googleSelectedCalendarIDs[accountID] ?? ""
            googleSelectedCalendarIDs[accountID] = resolvedCalendarID
            reconcileSharedGoogleAccountDescriptorsWithLocalAccounts()
            persistSettings()
            if let selectedGoogleCalendar = calendars.first(where: { $0.id == resolvedCalendarID }) {
                setGoogleMessage(
                    "Loaded \(calendars.count) writable Google calendars. Selected \(selectedGoogleCalendar.displayName).",
                    for: accountID
                )
            } else {
                setGoogleMessage("No writable Google calendars were found for this account.", for: accountID)
            }
            if previousCalendarID == resolvedCalendarID {
                await syncAfterParticipantConfigurationChange()
            } else {
                await handleGoogleCalendarSelectionChange(
                    for: accountID,
                    from: previousCalendarID,
                    to: resolvedCalendarID
                )
            }
            await runLiveGoogleSmokeIfNeeded()
        } catch let error as GoogleSignInServiceError {
            setGoogleMessage(error.localizedDescription, for: accountID)
        } catch let error as GoogleCalendarServiceError {
            setGoogleMessage(error.localizedDescription, for: accountID)
        } catch let error as GoogleAccountStoreError {
            setGoogleMessage(error.localizedDescription, for: accountID)
        } catch {
            setGoogleMessage("Google calendars could not be loaded.", for: accountID)
        }

        googleOperationAccountIDs.remove(accountID)
    }

    func createManagedBusyEvent(for accountID: String) async {
        guard
            let calendar = selectedGoogleCalendar(for: accountID),
            let storedAccount = storedGoogleAccount(id: accountID)
        else {
            setGoogleMessage(
                "Select a writable Google calendar before creating a managed busy slot.",
                for: accountID
            )
            return
        }

        await performGoogleCalendarOperation(accountID: accountID) { [self] in
            let authorizedAccount = try await GoogleSignInService.authorizeStoredAccount(storedAccount)
            try replaceStoredGoogleAccount(authorizedAccount.storedAccount)
            let event = try await self.googleCalendarService.createManagedBusyEvent(
                in: calendar,
                accessToken: authorizedAccount.accessToken
            )
            self.lastManagedGoogleEventsByAccountID[accountID] = event
            self.setGoogleMessage(
                "Created a managed busy slot in \(calendar.displayName) for \(event.windowDescription).",
                for: accountID
            )
        }
    }

    func deleteManagedBusyEvent(for accountID: String) async {
        guard
            let event = lastManagedGoogleEventsByAccountID[accountID],
            let storedAccount = storedGoogleAccount(id: accountID)
        else {
            setGoogleMessage("There is no managed busy slot to delete yet.", for: accountID)
            return
        }

        await performGoogleCalendarOperation(accountID: accountID) { [self] in
            let authorizedAccount = try await GoogleSignInService.authorizeStoredAccount(storedAccount)
            try replaceStoredGoogleAccount(authorizedAccount.storedAccount)
            try await self.googleCalendarService.deleteManagedBusyEvent(
                event,
                accessToken: authorizedAccount.accessToken
            )
            self.lastManagedGoogleEventsByAccountID[accountID] = nil
            self.setGoogleMessage(
                "Deleted the managed busy slot from \(event.calendarName).",
                for: accountID
            )
        }
    }

    private func performGoogleCalendarOperation(
        accountID: String,
        _ operation: @escaping () async throws -> Void
    ) async {
        guard !googleOperationAccountIDs.contains(accountID) else { return }
        googleOperationAccountIDs.insert(accountID)

        defer {
            googleOperationAccountIDs.remove(accountID)
        }

        do {
            try await operation()
        } catch let error as GoogleSignInServiceError {
            setGoogleMessage(error.localizedDescription, for: accountID)
        } catch let error as GoogleCalendarServiceError {
            setGoogleMessage(error.localizedDescription, for: accountID)
        } catch let error as GoogleAccountStoreError {
            setGoogleMessage(error.localizedDescription, for: accountID)
        } catch {
            setGoogleMessage("Google Calendar request failed. Try again from the current app window.", for: accountID)
        }
    }

    private func performAppleCalendarOperation(
        _ operation: () async throws -> Void
    ) async {
        guard !isAppleCalendarOperationInFlight else { return }
        isAppleCalendarOperationInFlight = true

        defer {
            isAppleCalendarOperationInFlight = false
        }

        do {
            try await operation()
        } catch let error as AppleCalendarServiceError {
            appleCalendarMessage = error.localizedDescription
        } catch {
            appleCalendarMessage = "Apple Calendar request failed. Try again from the current app window."
        }
    }

    private func syncNowIfReady() async {
        if selectedParticipantCount >= 1 {
            await syncNow()
        }

        await publishBookingAvailabilityIfNeeded(reason: "Background availability refresh")
    }

    private func publishBookingAvailabilityIfNeeded(reason: String) async {
        guard canPublishBookingPageToGitHub, hasActiveBookingAppointmentTypes else {
            return
        }

        await publishBookingPageToGitHub(reason: reason, updatesSnapshot: false)
    }

    private func syncAfterParticipantConfigurationChange() async {
        guard hasPrepared else { return }

        guard selectedParticipantCount >= 1 else {
            lastBusyMirrorSyncSummary = nil
            syncMessage = "Select calendars to manage mirrored busy holds. Two or more selected calendars create new mirrors."
            return
        }

        await syncNow()
    }

    private func restartSyncLoopIfNeeded() {
        syncLoopTask?.cancel()
        syncLoopTask = nil

        guard supportsPollingSettings else {
            return
        }

        syncLoopTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                let sleepSeconds = UInt64(max(1, self.pollIntervalMinutes) * 60)
                do {
                    try await Task.sleep(for: .seconds(sleepSeconds))
                } catch {
                    return
                }

                if Task.isCancelled {
                    return
                }

                await self.syncNowIfReady()
            }
        }
    }

    private func scheduleIOSBackgroundRefreshIfPossible() {
        guard launchOptions.platformTarget == .ios else {
            iosBackgroundRefreshState = .unsupported
            return
        }

        guard supportsIOSBackgroundRefresh else {
            iosBackgroundRefreshState = .unsupported
            return
        }

        switch iosBackgroundRefreshScheduler.availability {
        case .unsupported:
            iosBackgroundRefreshState = .unsupported
        case .denied:
            iosBackgroundRefreshState = .denied
        case .restricted:
            iosBackgroundRefreshState = .restricted
        case .available:
            let earliestBeginDate = Date().addingTimeInterval(IOSBackgroundRefreshConstants.earliestBeginInterval)
            do {
                iosBackgroundRefreshScheduler.cancelAppRefresh(identifier: IOSBackgroundRefreshConstants.taskIdentifier)
                try iosBackgroundRefreshScheduler.submitAppRefresh(
                    identifier: IOSBackgroundRefreshConstants.taskIdentifier,
                    earliestBeginDate: earliestBeginDate
                )
                iosBackgroundRefreshState = .scheduled(earliestBeginDate)
            } catch {
                iosBackgroundRefreshState = .failed(error.localizedDescription)
            }
        }
    }

    private func collectSyncParticipants() async throws -> SyncParticipantsBundle {
        var participants: [BusyMirrorParticipant] = []
        var googleAccountsByID: [String: GoogleAuthorizedAccount] = [:]
        var googleCalendarsByAccountID: [String: GoogleCalendarSummary] = [:]

        for storedAccount in googleStoredAccounts {
            let selectedCalendarID = googleSelectedCalendarIDs[storedAccount.id] ?? ""
            guard !selectedCalendarID.isEmpty else {
                continue
            }

            let authorizedAccount = try await GoogleSignInService.authorizeStoredAccount(storedAccount)
            try replaceStoredGoogleAccount(authorizedAccount.storedAccount)
            googleAccountsByID[storedAccount.id] = authorizedAccount

            let writableCalendars: [GoogleCalendarSummary]
            if
                let cachedCalendars = self.googleCalendarsByAccountID[storedAccount.id],
                cachedCalendars.contains(where: { $0.id == selectedCalendarID })
            {
                writableCalendars = cachedCalendars
            } else {
                writableCalendars = try await googleCalendarService.listWritableCalendars(
                    accessToken: authorizedAccount.accessToken
                )
                self.googleCalendarsByAccountID[storedAccount.id] = writableCalendars
            }

            guard let selectedCalendar = writableCalendars.first(where: { $0.id == selectedCalendarID }) else {
                continue
            }

            googleCalendarsByAccountID[storedAccount.id] = selectedCalendar
            participants.append(
                BusyMirrorParticipant(
                    provider: .google,
                    accountID: storedAccount.id,
                    calendarID: selectedCalendar.id,
                    displayName: "\(storedAccount.displayName) • \(selectedCalendar.displayName)"
                )
            )
        }

        if
            isAppleCalendarEnabled,
            appleCalendarAuthorizationState == .granted,
            let selectedAppleCalendar
        {
            participants.append(
                BusyMirrorParticipant(
                    provider: .apple,
                    accountID: nil,
                    calendarID: selectedAppleCalendar.id,
                    displayName: selectedAppleCalendar.displayName
                )
            )
        }

        return SyncParticipantsBundle(
            participants: participants,
            googleAccountsByID: googleAccountsByID,
            googleCalendarsByAccountID: googleCalendarsByAccountID
        )
    }

    private func applySyncOperation(
        _ operation: BusyMirrorOperation,
        participantsBundle: SyncParticipantsBundle
    ) async throws {
        switch operation {
        case let .create(desiredMirror):
            try await createManagedMirror(desiredMirror, participantsBundle: participantsBundle)
        case let .update(existingMirror, desiredMirror):
            try await updateManagedMirror(
                existingMirror,
                desiredMirror: desiredMirror,
                participantsBundle: participantsBundle
            )
        case let .delete(existingMirror):
            try await deleteManagedMirror(existingMirror, participantsBundle: participantsBundle)
        }
    }

    private func createManagedMirror(
        _ desiredMirror: DesiredBusyMirrorEvent,
        participantsBundle: SyncParticipantsBundle
    ) async throws {
        switch desiredMirror.targetParticipant.provider {
        case .google:
            guard
                let accountID = desiredMirror.targetParticipant.accountID,
                let authorizedAccount = participantsBundle.googleAccountsByID[accountID]
            else {
                throw GoogleSignInServiceError.missingAccessToken
            }

            try await googleCalendarService.createManagedMirrorEvent(
                desiredMirror: desiredMirror,
                accessToken: authorizedAccount.accessToken
            )
        case .apple:
            guard let calendar = appleCalendarSummary(for: desiredMirror.targetParticipant.calendarID) else {
                throw AppleCalendarServiceError.calendarNotFound
            }

            try appleCalendarService.createManagedMirrorEvent(
                in: calendar,
                desiredMirror: desiredMirror
            )
        }
    }

    private func updateManagedMirror(
        _ existingMirror: ExistingBusyMirrorEvent,
        desiredMirror: DesiredBusyMirrorEvent,
        participantsBundle: SyncParticipantsBundle
    ) async throws {
        switch existingMirror.targetParticipant.provider {
        case .google:
            guard
                let accountID = existingMirror.targetParticipant.accountID,
                let authorizedAccount = participantsBundle.googleAccountsByID[accountID]
            else {
                throw GoogleSignInServiceError.missingAccessToken
            }

            try await googleCalendarService.updateManagedMirrorEvent(
                existingMirror,
                desiredMirror: desiredMirror,
                accessToken: authorizedAccount.accessToken
            )
        case .apple:
            try appleCalendarService.updateManagedMirrorEvent(
                existingMirror,
                desiredMirror: desiredMirror
            )
        }
    }

    private func deleteManagedMirror(
        _ existingMirror: ExistingBusyMirrorEvent,
        participantsBundle: SyncParticipantsBundle
    ) async throws {
        switch existingMirror.targetParticipant.provider {
        case .google:
            guard
                let accountID = existingMirror.targetParticipant.accountID,
                let authorizedAccount = participantsBundle.googleAccountsByID[accountID]
            else {
                throw GoogleSignInServiceError.missingAccessToken
            }

            try await googleCalendarService.deleteManagedMirrorEvent(
                existingMirror,
                accessToken: authorizedAccount.accessToken
            )
        case .apple:
            try appleCalendarService.deleteManagedMirrorEvent(existingMirror)
        }
    }

    private func appleCalendarSummary(for calendarID: String) -> AppleCalendarSummary? {
        appleCalendars.first(where: { $0.id == calendarID })
            ?? selectedAppleCalendar.flatMap { $0.id == calendarID ? $0 : nil }
    }

    private func yieldForIOSSyncResponsivenessIfNeeded() async {
        guard usesCooperativeIOSSyncScheduling else {
            return
        }

        await Task.yield()
    }

    private func syncFailureMessage(for operation: BusyMirrorOperation, error: Error) -> String {
        BusyMirrorSyncAuditFormatter.failureMessage(for: operation, error: error)
    }

    private func loadInitialState() throws -> ScenarioState {
        guard launchOptions.scenarioRoot != nil || launchOptions.scenarioName != nil else {
            return .emptyLiveShell
        }

        return try loader.load(using: launchOptions)
    }

    private func appendAuditTrailEntry(
        title: String,
        detail: String,
        status: String,
        occurredAt: Date = Date()
    ) {
        let entry = AuditTrailEntry(
            occurredAt: occurredAt,
            title: title,
            detail: detail,
            status: status
        )

        if let latestEntry = runtimeAuditTrailEntries.first,
           latestEntry.title == entry.title,
           latestEntry.detail == entry.detail,
           latestEntry.status == entry.status
        {
            return
        }

        runtimeAuditTrailEntries.insert(entry, at: 0)
        trimAuditTrailEntriesIfNeeded()
    }

    private func trimAuditTrailEntriesIfNeeded() {
        guard let limit = auditTrailLogLength.limit, runtimeAuditTrailEntries.count > limit else {
            return
        }

        runtimeAuditTrailEntries = Array(runtimeAuditTrailEntries.prefix(limit))
    }

    private func persistSettings() {
        guard !isApplyingSharedConfiguration else { return }

        let updatedAt = Date()
        lastSettingsMutationAt = updatedAt
        writeSettingsToUserDefaults(updatedAt: updatedAt)
        guard isSharedConfigurationEnabled else {
            return
        }
        sharedConfigurationStore.saveConfiguration(currentSharedConfiguration(updatedAt: updatedAt))
    }

    private func persistSettingsAndRefreshGoogleConfiguration() {
        persistSettings()
        refreshGoogleConfiguration()
    }

    private func updateBookingSetupSnapshot(
        _ snapshot: BookingSetupSnapshot,
        auditDetail: String
    ) {
        bookingSetupSnapshot = snapshot
        if let data = try? JSONEncoder().encode(snapshot) {
            userDefaults.set(data, forKey: SettingKey.bookingSetupSnapshot)
        }

        appendAuditTrailEntry(
            title: "Booking",
            detail: auditDetail,
            status: snapshot.isReady ? "configured" : "working"
        )
    }

    private func persistBookingSettings() {
        writeBookingSettingsToUserDefaults()
        persistSettings()
    }

    private func writeBookingSettingsToUserDefaults() {
        userDefaults.set(bookingPageURLString, forKey: SettingKey.bookingPageURL)
        userDefaults.set(bookingInboxURLString, forKey: SettingKey.bookingInboxURL)
        userDefaults.set(bookingGitHubRepositoryString, forKey: SettingKey.bookingGitHubRepository)
        userDefaults.set(bookingGitHubBranchString, forKey: SettingKey.bookingGitHubBranch)
        userDefaults.set(bookingVercelScopeString, forKey: SettingKey.bookingVercelScope)
        userDefaults.set(bookingVercelProjectNameString, forKey: SettingKey.bookingVercelProjectName)
        userDefaults.set(bookingPublicNameString, forKey: SettingKey.bookingPublicName)
        userDefaults.set(bookingPageTitleString, forKey: SettingKey.bookingPageTitle)
        userDefaults.set(bookingPageSubtitleString, forKey: SettingKey.bookingPageSubtitle)
        userDefaults.set(bookingTimeZoneIdentifierString, forKey: SettingKey.bookingTimeZoneIdentifier)
        userDefaults.set(bookingThemeAccentColorString, forKey: SettingKey.bookingThemeAccentColor)
        userDefaults.set(bookingThemeBackgroundColorString, forKey: SettingKey.bookingThemeBackgroundColor)
        userDefaults.set(bookingThemeTextColorString, forKey: SettingKey.bookingThemeTextColor)
        userDefaults.set(bookingCalendarTargetProviderString, forKey: SettingKey.bookingCalendarTargetProvider)
        userDefaults.set(bookingAppleTargetCalendarIDString, forKey: SettingKey.bookingAppleTargetCalendarID)
        userDefaults.set(bookingGoogleTargetAccountIDString, forKey: SettingKey.bookingGoogleTargetAccountID)
        userDefaults.set(bookingGoogleTargetCalendarIDString, forKey: SettingKey.bookingGoogleTargetCalendarID)
        userDefaults.set(selectedBookingAppointmentTypeIDString, forKey: SettingKey.selectedBookingAppointmentTypeID)
        userDefaults.set(isAutomaticBookingApprovalEnabled, forKey: SettingKey.isAutomaticBookingApprovalEnabled)
    }

    private func persistBookingAppointmentTypes() {
        do {
            try BookingConfigurationValidator.validateAppointmentTypes(bookingAppointmentTypes)
            let data = try JSONEncoder().encode(bookingAppointmentTypes)
            userDefaults.set(data, forKey: SettingKey.bookingAppointmentTypes)
            persistSettings()
        } catch {
            appendAuditTrailEntry(
                title: "Booking",
                detail: "Appointment types could not be saved. \(error.localizedDescription)",
                status: "failed"
            )
        }
    }

    private func setBookingAppointmentTypePaused(_ id: AppointmentTypeID, isPaused: Bool) {
        guard let index = bookingAppointmentTypes.firstIndex(where: { $0.id == id }) else {
            return
        }

        bookingAppointmentTypes[index].isPaused = isPaused
        selectedBookingAppointmentTypeIDString = id.rawValue
        persistBookingAppointmentTypes()
        let message = isPaused
            ? "Appointment type paused. Publish changes to hide it from the public page."
            : "Appointment type resumed. Publish changes to make it live again."
        markBookingPageNeedsPublish(message: message)
    }

    private func recordBookingGeneratedVersion(fingerprint: String, generatedAt: Date) {
        bookingLastGeneratedFingerprintString = fingerprint
        bookingLastGeneratedAt = generatedAt
        userDefaults.set(fingerprint, forKey: SettingKey.bookingLastGeneratedFingerprint)
        userDefaults.set(generatedAt, forKey: SettingKey.bookingLastGeneratedAt)
    }

    private func recordBookingUploadedVersion(uploadedAt: Date) {
        bookingLastUploadedAt = uploadedAt
        userDefaults.set(uploadedAt, forKey: SettingKey.bookingLastUploadedAt)
    }

    private func recordBookingServedVersion(fingerprint: String, verifiedAt: Date?) {
        bookingLastServedFingerprintString = fingerprint
        userDefaults.set(fingerprint, forKey: SettingKey.bookingLastServedFingerprint)
        bookingLastVerifiedAt = verifiedAt
        if let verifiedAt {
            userDefaults.set(verifiedAt, forKey: SettingKey.bookingLastVerifiedAt)
        } else {
            userDefaults.removeObject(forKey: SettingKey.bookingLastVerifiedAt)
        }
    }

    private func recordBookingRemoteDriftWarningIfNeeded(
        _ summary: BookingGitHubPublisher.PublishSummary,
        repository: BookingGitHubRepository
    ) {
        guard !summary.remoteChangedPaths.isEmpty else { return }

        let pathList = summary.remoteChangedPaths.prefix(4).joined(separator: ", ")
        let extraCount = max(0, summary.remoteChangedPaths.count - 4)
        let suffix = extraCount == 0 ? "" : " and \(extraCount) more"
        appendAuditTrailEntry(
            title: "Booking availability warning",
            detail: "Remote generated file(s) in \(repository.slug) changed before this app overwrote them: \(pathList)\(suffix).",
            status: "warning"
        )
    }

    private func bookingSiteConfigURL(for pageURL: URL) -> URL {
        var components = URLComponents(url: pageURL, resolvingAgainstBaseURL: false)
        let basePath = components?.path ?? ""
        let normalizedBasePath = basePath.hasSuffix("/") ? basePath : "\(basePath)/"
        components?.path = "\(normalizedBasePath)public/site-config.json"
        components?.query = nil
        components?.fragment = nil
        return components?.url ?? pageURL.appendingPathComponent("public/site-config.json")
    }

    private func servedBookingFingerprint(from data: Data) throws -> String {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any],
              let version = dictionary["version"] as? [String: Any],
              let fingerprint = version["fingerprint"] as? String,
              !fingerprint.isEmpty
        else {
            throw BookingRelayClientError.invalidResponse
        }
        return fingerprint
    }

    private func uniqueAppointmentSlug(base: String) -> String {
        let normalizedBase = Self.normalizedAppointmentSlug(base)
        let existing = Set(bookingAppointmentTypes.map(\.slug))
        guard existing.contains(normalizedBase) else {
            return normalizedBase
        }

        for index in 2...999 {
            let candidate = "\(normalizedBase)-\(index)"
            if !existing.contains(candidate) {
                return candidate
            }
        }

        return "\(normalizedBase)-\(UUID().uuidString.prefix(8).lowercased())"
    }

    private func markBookingPageNeedsPublish(message: String) {
        guard !isApplyingSharedConfiguration else { return }

        let status: BookingPublicationStatus
        switch bookingSetupSnapshot.pageStatus {
        case .published, .uploaded:
            status = .needsPublish
        case .generatedLocally, .needsPublish, .publishFailed:
            status = .generatedLocally
        case .notPublished, .disabled:
            status = .notPublished
        }
        updateBookingSetupSnapshot(
            BookingSetupSnapshot(
                pageStatus: status,
                inboxStatus: bookingSetupSnapshot.inboxStatus,
                pendingRequestCount: bookingSetupSnapshot.pendingRequestCount,
                lastMessage: message
            ),
            auditDetail: message
        )
    }

    private func markBookingCustomizationChanged(oldValue: String, newValue: String) {
        guard !isApplyingSharedConfiguration else { return }
        guard oldValue != newValue else { return }
        markBookingPageNeedsPublish(message: "Public page customization changed. Generate page files before sharing changes.")
    }

    private func markBookingInboxConfigured(oldValue: String, newValue: String) {
        guard !isApplyingSharedConfiguration else { return }

        let trimmedOldValue = oldValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNewValue = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedOldValue != trimmedNewValue else { return }

        let status: BookingInboxStatus = trimmedNewValue.isEmpty ? .notConnected : .configured
        updateBookingSetupSnapshot(
            BookingSetupSnapshot(
                pageStatus: bookingSetupSnapshot.pageStatus,
                inboxStatus: status,
                pendingRequestCount: bookingSetupSnapshot.pendingRequestCount,
                lastMessage: trimmedNewValue.isEmpty
                    ? "Request inbox URL removed."
                    : "Request inbox URL configured. Check the inbox before importing requests."
            ),
            auditDetail: trimmedNewValue.isEmpty
                ? "Booking request inbox URL removed."
                : "Booking request inbox URL configured."
        )
    }

    private static func normalizedHexColor(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = trimmed.hasPrefix("#") ? trimmed : "#\(trimmed)"
        guard candidate.range(of: #"^#[0-9A-Fa-f]{6}$"#, options: .regularExpression) != nil else {
            return fallback
        }

        return candidate.uppercased()
    }

    private static func originString(for url: URL) -> String {
        guard let scheme = url.scheme?.lowercased(),
              let host = url.host
        else {
            return ""
        }

        var origin = "\(scheme)://\(host)"
        if let port = url.port {
            origin += ":\(port)"
        }
        return origin
    }

    private func persistBookingAdminToken() {
        do {
            try bookingSecretStore.saveAdminToken(bookingInboxAdminTokenString)
        } catch {
            appendAuditTrailEntry(
                title: "Booking",
                detail: "Could not save the inbox admin token to secure storage.",
                status: "failed"
            )
        }
    }

    private func persistBookingVercelToken() {
        do {
            try bookingSecretStore.saveVercelToken(bookingVercelTokenString)
        } catch {
            appendAuditTrailEntry(
                title: "Booking",
                detail: "Could not save the Vercel token to secure storage.",
                status: "failed"
            )
        }
    }

    private func bookingInboxAdminTokenForVercelDeployment() throws -> String {
        let existingToken = bookingInboxAdminTokenString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !existingToken.isEmpty {
            return existingToken
        }
        return try BookingVercelDeploymentClient.generateAdminToken()
    }

    private static func bookingConfigurationErrorMessage(_ error: Error) -> String {
        if let error = error as? BookingConfigurationError {
            return error.localizedDescription
        }
        if let error = error as? BookingVercelDeploymentError {
            return error.errorDescription ?? error.localizedDescription
        }
        return error.localizedDescription
    }

    private static func bookingConfigurationFailureMessage(_ error: Error, fallback: String) -> String {
        if let error = error as? BookingConfigurationError {
            return error.localizedDescription
        }
        return fallback
    }

    private func recordBookingGitHubDeployKey(
        publicKey: String,
        fingerprint: String,
        repository: String,
        verifiedAt: Date?
    ) {
        bookingGitHubDeployKeyPublicKeyString = publicKey
        bookingGitHubDeployKeyFingerprintString = fingerprint
        bookingGitHubDeployKeyRepositoryString = repository
        bookingGitHubDeployKeyVerifiedAt = verifiedAt
        userDefaults.set(publicKey, forKey: SettingKey.bookingGitHubDeployKeyPublicKey)
        userDefaults.set(fingerprint, forKey: SettingKey.bookingGitHubDeployKeyFingerprint)
        userDefaults.set(repository, forKey: SettingKey.bookingGitHubDeployKeyRepository)
        if let verifiedAt {
            userDefaults.set(verifiedAt, forKey: SettingKey.bookingGitHubDeployKeyVerifiedAt)
        } else {
            userDefaults.removeObject(forKey: SettingKey.bookingGitHubDeployKeyVerifiedAt)
        }
    }

    private func loadBookingGitHubDeployKeyPrivateKey() throws -> String {
        guard let privateKey = try bookingSecretStore.loadGitHubDeployKeyPrivateKey(),
              !privateKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw BookingConfigurationError.invalidField(
                "Generate a new deploy key on this Mac, then add it to GitHub with write access. The private key is missing from Keychain."
            )
        }
        return privateKey
    }

    private func loadOrCreateBookingSecrets() throws -> BookingLocalSecrets {
        if let secrets = try bookingSecretStore.loadSecrets() {
            return secrets
        }

        let secrets = BookingLocalSecrets.generate()
        try bookingSecretStore.saveSecrets(secrets)
        return secrets
    }

    private func loadExistingBookingSecrets() throws -> BookingLocalSecrets {
        guard let secrets = try bookingSecretStore.loadSecrets() else {
            throw BookingSecretStoreError.missingSecrets
        }

        return secrets
    }

    private func importBookingRequestEnvelope(
        _ envelope: EncryptedBookingRequestEnvelope,
        secrets: BookingLocalSecrets,
        now: Date
    ) throws -> BookingImportedRequest {
        try BookingRequestImporter.importEnvelope(
            envelope,
            secrets: secrets,
            now: now
        ) { claim in
            try bookingSlotIsStillOpen(claim, now: now)
        }
    }

    private func bookingRequestSlotIsStillOpen(_ request: BookingImportedRequest) throws -> Bool {
        try bookingSlotIsStillOpen(request.slotClaim, now: Date())
    }

    private func bookingRequestSlotIsStillOpen(
        _ request: BookingImportedRequest,
        googleCalendar: GoogleCalendarSummary,
        accountID: String,
        accessToken: String
    ) async throws -> Bool {
        let claim = request.slotClaim
        guard claim.expiresAt > Date(), claim.endsAt > claim.startsAt else {
            return false
        }

        let participant = BusyMirrorParticipant(
            provider: .google,
            accountID: accountID,
            calendarID: googleCalendar.id,
            displayName: googleCalendar.displayName
        )
        let requestedInterval = DateInterval(start: claim.startsAt, end: claim.endsAt)
        let busyBlocks = try await googleCalendarService.listBusyTargetBlocks(
            in: participant,
            calendarTimeZone: googleCalendar.timeZone,
            window: requestedInterval,
            accessToken: accessToken
        )
        return !busyBlocks.contains { block in
            block.startDate < requestedInterval.end && requestedInterval.start < block.endDate
        }
    }

    private func bookingSlotIsStillOpen(_ claim: BookingSlotClaim, now: Date) throws -> Bool {
        guard claim.expiresAt > now, claim.endsAt > claim.startsAt else {
            return false
        }
        guard isAppleCalendarEnabled else {
            if let accountID = activeResolvedGoogleAccountID,
               selectedGoogleCalendar(for: accountID) != nil
            {
                return true
            }
            throw AppleCalendarServiceError.notConnected
        }
        guard appleCalendarAuthorizationState == .granted,
              let selectedAppleCalendar
        else {
            throw AppleCalendarServiceError.notConnected
        }

        let participant = BusyMirrorParticipant(
            provider: .apple,
            accountID: nil,
            calendarID: selectedAppleCalendar.id,
            displayName: selectedAppleCalendar.displayName
        )
        let requestedInterval = DateInterval(start: claim.startsAt, end: claim.endsAt)
        let busyBlocks = try appleCalendarService.listBusyTargetBlocks(
            in: participant,
            window: requestedInterval
        )
        return !busyBlocks.contains { block in
            block.startDate < requestedInterval.end && requestedInterval.start < block.endDate
        }
    }

    private func deleteBookingRequestFromInbox(_ request: BookingImportedRequest) async throws {
        guard let inboxURL = URL(string: bookingInboxURLString.trimmingCharacters(in: .whitespacesAndNewlines)),
              let relayURL = try? BookingRelayURL(inboxURL)
        else {
            throw BookingConfigurationError.invalidRelayURL("Vercel inbox URL is not valid.")
        }

        let adminToken = bookingInboxAdminTokenString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !adminToken.isEmpty else {
            throw BookingConfigurationError.invalidField("Vercel inbox secret is required.")
        }

        try await BookingRelayClient(
            relayURL: relayURL,
            adminToken: BookingRelayAdminToken(rawValue: adminToken)
        ).deleteRequest(
            inboxID: request.envelope.inboxID,
            requestID: request.id
        )
    }

    private func markBookingRequest(
        _ requestID: BookingRequestID,
        status: BookingImportedRequestStatus,
        message: String,
        calendarEventID: String? = nil
    ) {
        guard let index = importedBookingRequests.firstIndex(where: { $0.id == requestID }) else {
            return
        }

        importedBookingRequests[index].status = status
        importedBookingRequests[index].message = message
        if let calendarEventID {
            importedBookingRequests[index].calendarEventID = calendarEventID
        }

        let pendingCount = importedBookingRequests.filter(\.canApprove).count
        updateBookingSetupSnapshot(
            BookingSetupSnapshot(
                pageStatus: bookingSetupSnapshot.pageStatus,
                inboxStatus: bookingSetupSnapshot.inboxStatus,
                pendingRequestCount: pendingCount,
                lastMessage: message
            ),
            auditDetail: message
        )
    }

    private var bookingSiteBuildOutputURL: URL {
        bookingApplicationSupportURL
            .appendingPathComponent("BookingSiteBuild", isDirectory: true)
    }

    private var bookingEditableTemplateURL: URL {
        bookingApplicationSupportURL
            .appendingPathComponent("BookingSiteTemplate", isDirectory: true)
    }

    private var bookingApplicationSupportURL: URL {
        let baseURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory

        return baseURL
            .appendingPathComponent("Calendar Busy Sync", isDirectory: true)
    }

    private func refreshGoogleConfiguration() {
        do {
            let configuration = try DefaultGoogleOAuthConfigurationLoader.load()
            defaultGoogleOAuthConfiguration = configuration
            googleOAuthResolution = GoogleOAuthConfigurationResolver.resolve(
                defaultConfiguration: configuration,
                overrideConfiguration: googleOAuthConfiguration
            )
        } catch {
            defaultGoogleOAuthConfiguration = nil
            googleOAuthResolution = .invalid(
                message: "The bundled Google OAuth configuration is missing. Run the harness sync step so `DefaultGoogleOAuth.plist` is copied into the app target."
            )
        }
    }

    private func startObservingSharedConfiguration() {
        sharedConfigurationStore.startObserving { [weak self] configuration in
            self?.applySharedConfigurationIfNewer(configuration)
        }
    }

    private func reconcileSharedConfigurationAtLaunch() {
        guard isSharedConfigurationEnabled else {
            updateSharedConfigurationSyncState(.disabled, logEvent: false)
            return
        }

        guard sharedConfigurationStore.isAvailable else {
            updateSharedConfigurationSyncState(.unavailable, logEvent: false)
            return
        }

        guard let sharedConfiguration = sharedConfigurationStore.loadConfiguration() else {
            sharedConfigurationStore.saveConfiguration(currentSharedConfiguration(updatedAt: lastSettingsMutationAt))
            updateSharedConfigurationSyncState(
                .succeeded(
                    message: "No shared iCloud settings were found, so this device requested an initial upload.",
                    at: Date()
                ),
                logEvent: true
            )
            return
        }

        if sharedConfiguration.updatedAt > lastSettingsMutationAt {
            applySharedConfigurationIfNewer(sharedConfiguration)
            return
        }

        if sharedConfiguration.updatedAt < lastSettingsMutationAt {
            sharedConfigurationStore.saveConfiguration(currentSharedConfiguration(updatedAt: lastSettingsMutationAt))
            updateSharedConfigurationSyncState(
                .succeeded(
                    message: "Requested an iCloud update with this device's newer settings during launch.",
                    at: Date()
                ),
                logEvent: true
            )
            return
        }

        updateSharedConfigurationSyncState(.idle, logEvent: false)
    }

    private func applySharedConfigurationIfNewer(_ configuration: SharedAppConfiguration) {
        guard isSharedConfigurationEnabled else {
            return
        }

        guard configuration.updatedAt > lastSettingsMutationAt else {
            return
        }

        let previousAppleCalendarEnabled = isAppleCalendarEnabled
        let previousAppleCalendarID = selectedAppleCalendarID
        let previousGoogleSelectedCalendarIDs = googleSelectedCalendarIDs

        isApplyingSharedConfiguration = true
        pollIntervalMinutes = max(1, min(60, configuration.pollIntervalMinutes))
        auditTrailLogLength = configuration.auditTrailLogLength
        isAppleCalendarEnabled = configuration.isAppleCalendarEnabled
        persistedAppleCalendarReference = configuration.selectedAppleCalendarReference
        usesCustomGoogleOAuthApp = configuration.usesCustomGoogleOAuthApp
        customGoogleOAuthClientID = configuration.customGoogleOAuthClientID
        customGoogleOAuthServerClientID = configuration.customGoogleOAuthServerClientID
        googleSelectedCalendarIDs = configuration.googleSelectedCalendarIDs
        activeGoogleAccountID = configuration.activeGoogleAccountID
        sharedGoogleAccountDescriptors = configuration.googleAccountDescriptors
        if let bookingConfiguration = configuration.bookingConfiguration {
            applySharedBookingConfiguration(bookingConfiguration)
        }
        selectedAppleCalendarID = isAppleCalendarEnabled
            ? AppleCalendarSelectionResolver.resolvedCalendarID(
                availableCalendars: appleCalendars,
                persistedCalendarID: selectedAppleCalendarID,
                sharedReference: persistedAppleCalendarReference
            )
            : ""
        isApplyingSharedConfiguration = false

        lastSettingsMutationAt = configuration.updatedAt
        writeSettingsToUserDefaults(updatedAt: configuration.updatedAt)
        refreshGoogleConfiguration()
        restartSyncLoopIfNeeded()
        updateSharedConfigurationSyncState(
            .succeeded(
                message: "Applied updated shared settings from iCloud.",
                at: Date()
            ),
            logEvent: true
        )

        guard hasPrepared else {
            return
        }

        Task { @MainActor [weak self] in
            await self?.applySharedConfigurationSideEffects(
                previousAppleCalendarEnabled: previousAppleCalendarEnabled,
                previousAppleCalendarID: previousAppleCalendarID,
                previousGoogleSelectedCalendarIDs: previousGoogleSelectedCalendarIDs
            )
        }
    }

    private func applySharedConfigurationSideEffects(
        previousAppleCalendarEnabled: Bool,
        previousAppleCalendarID: String,
        previousGoogleSelectedCalendarIDs: [String: String]
    ) async {
        var shouldSync = false

        if isAppleCalendarEnabled {
            await restoreAppleCalendarAccessIfNeeded()

            let resolvedAppleCalendarID = selectedAppleCalendarID
            if previousAppleCalendarEnabled, previousAppleCalendarID != resolvedAppleCalendarID {
                if !previousAppleCalendarID.isEmpty {
                    await cleanupDeselectedAppleCalendar(calendarID: previousAppleCalendarID)
                }
                lastManagedAppleEvent = nil
                shouldSync = true
            } else if !previousAppleCalendarEnabled && !resolvedAppleCalendarID.isEmpty {
                shouldSync = true
            }
        } else if previousAppleCalendarEnabled {
            if !previousAppleCalendarID.isEmpty {
                await cleanupDeselectedAppleCalendar(calendarID: previousAppleCalendarID)
            }
            lastManagedAppleEvent = nil
            shouldSync = true
        }

        let accountIDs = Set(previousGoogleSelectedCalendarIDs.keys).union(googleSelectedCalendarIDs.keys)
        for accountID in accountIDs {
            let previousCalendarID = previousGoogleSelectedCalendarIDs[accountID] ?? ""
            let nextCalendarID = googleSelectedCalendarIDs[accountID] ?? ""
            guard previousCalendarID != nextCalendarID else {
                continue
            }

            if !previousCalendarID.isEmpty {
                await cleanupDeselectedGoogleCalendar(
                    accountID: accountID,
                    calendarID: previousCalendarID
                )
            }

            lastManagedGoogleEventsByAccountID[accountID] = nil
            shouldSync = true
        }

        if shouldSync {
            await syncAfterParticipantConfigurationChange()
        }
    }

    private func currentSharedConfiguration(updatedAt: Date) -> SharedAppConfiguration {
        SharedAppConfiguration(
            updatedAt: updatedAt,
            pollIntervalMinutes: max(1, min(60, pollIntervalMinutes)),
            auditTrailLogLengthRawValue: auditTrailLogLength.rawValue,
            isAppleCalendarEnabled: isAppleCalendarEnabled,
            selectedAppleCalendarReference: currentAppleCalendarReference,
            usesCustomGoogleOAuthApp: usesCustomGoogleOAuthApp,
            customGoogleOAuthClientID: customGoogleOAuthClientID,
            customGoogleOAuthServerClientID: customGoogleOAuthServerClientID,
            googleSelectedCalendarIDs: googleSelectedCalendarIDs,
            activeGoogleAccountID: activeGoogleAccountID,
            googleAccountDescriptors: sharedGoogleAccountDescriptors,
            bookingConfiguration: currentSharedBookingConfiguration()
        )
    }

    private func currentSharedBookingConfiguration() -> SharedBookingConfiguration {
        SharedBookingConfiguration(
            pageURLString: bookingPageURLString,
            inboxURLString: bookingInboxURLString,
            gitHubRepositoryString: bookingGitHubRepositoryString,
            gitHubBranchString: bookingGitHubBranchString,
            vercelScopeString: bookingVercelScopeString,
            vercelProjectNameString: bookingVercelProjectNameString,
            publicNameString: bookingPublicNameString,
            pageTitleString: bookingPageTitleString,
            pageSubtitleString: bookingPageSubtitleString,
            timeZoneIdentifierString: bookingTimeZoneIdentifierString,
            themeAccentColorString: bookingThemeAccentColorString,
            themeBackgroundColorString: bookingThemeBackgroundColorString,
            themeTextColorString: bookingThemeTextColorString,
            selectedAppointmentTypeIDString: selectedBookingAppointmentTypeIDString,
            isAutomaticApprovalEnabled: isAutomaticBookingApprovalEnabled,
            appointmentTypes: bookingAppointmentTypes
        )
    }

    private func applySharedBookingConfiguration(_ configuration: SharedBookingConfiguration) {
        let sharedAppointmentTypes = Self.validSharedBookingAppointmentTypes(
            configuration.appointmentTypes,
            fallback: bookingAppointmentTypes
        )
        let selectedID = sharedAppointmentTypes.contains { $0.id.rawValue == configuration.selectedAppointmentTypeIDString }
            ? configuration.selectedAppointmentTypeIDString
            : sharedAppointmentTypes.first?.id.rawValue ?? ""

        bookingPageURLString = configuration.pageURLString
        bookingInboxURLString = configuration.inboxURLString
        bookingGitHubRepositoryString = configuration.gitHubRepositoryString
        bookingGitHubBranchString = configuration.gitHubBranchString.isEmpty ? "main" : configuration.gitHubBranchString
        bookingVercelScopeString = configuration.vercelScopeString
        bookingVercelProjectNameString = configuration.vercelProjectNameString
        bookingPublicNameString = configuration.publicNameString
        bookingPageTitleString = configuration.pageTitleString
        bookingPageSubtitleString = configuration.pageSubtitleString
        bookingTimeZoneIdentifierString = configuration.timeZoneIdentifierString
        bookingThemeAccentColorString = configuration.themeAccentColorString
        bookingThemeBackgroundColorString = configuration.themeBackgroundColorString
        bookingThemeTextColorString = configuration.themeTextColorString
        selectedBookingAppointmentTypeIDString = selectedID
        isAutomaticBookingApprovalEnabled = configuration.isAutomaticApprovalEnabled
        bookingAppointmentTypes = sharedAppointmentTypes
        persistBookingAppointmentTypes()
    }

    private func updateSharedConfigurationSyncState(
        _ newState: SharedConfigurationSyncState,
        logEvent: Bool
    ) {
        sharedConfigurationSyncState = newState

        guard logEvent else {
            return
        }

        let status: String
        switch newState {
        case .disabled:
            status = "blocked"
        case .unavailable:
            status = "blocked"
        case .idle:
            status = "ready"
        case .syncing:
            status = "working"
        case .succeeded:
            status = "configured"
        case .failed:
            status = "failed"
        }

        appendAuditTrailEntry(
            title: "iCloud settings sync",
            detail: newState.detail,
            status: status,
            occurredAt: newState.updatedAt ?? Date()
        )
    }

    private var currentAppleCalendarReference: SharedAppleCalendarReference? {
        if let selectedAppleCalendar {
            return SharedAppleCalendarReference(calendar: selectedAppleCalendar)
        }

        return selectedAppleCalendarID.isEmpty ? nil : persistedAppleCalendarReference
    }

    private func writeSettingsToUserDefaults(updatedAt: Date) {
        userDefaults.set(max(1, min(60, pollIntervalMinutes)), forKey: SettingKey.pollIntervalMinutes)
        userDefaults.set(auditTrailLogLength.rawValue, forKey: SettingKey.auditTrailLogLength)
        userDefaults.set(isSharedConfigurationEnabled, forKey: SettingKey.isSharedConfigurationEnabled)
        userDefaults.set(isAppleCalendarEnabled, forKey: SettingKey.usesAppleCalendar)
        userDefaults.set(selectedAppleCalendarID, forKey: SettingKey.selectedAppleCalendarID)
        userDefaults.set(usesCustomGoogleOAuthApp, forKey: SettingKey.usesCustomGoogleOAuthApp)
        userDefaults.set(customGoogleOAuthClientID, forKey: SettingKey.customGoogleOAuthClientID)
        userDefaults.set(customGoogleOAuthServerClientID, forKey: SettingKey.customGoogleOAuthServerClientID)
        userDefaults.set(googleSelectedCalendarIDs, forKey: SettingKey.selectedGoogleCalendarIDs)
        userDefaults.set(activeGoogleAccountID, forKey: SettingKey.activeGoogleAccountID)
        if let descriptorData = Self.encodeSharedGoogleAccountDescriptors(sharedGoogleAccountDescriptors) {
            userDefaults.set(descriptorData, forKey: SettingKey.sharedGoogleAccountDescriptors)
        } else {
            userDefaults.removeObject(forKey: SettingKey.sharedGoogleAccountDescriptors)
        }
        userDefaults.set(updatedAt, forKey: SettingKey.lastModifiedAt)

        if let referenceData = Self.encodeAppleCalendarReference(currentAppleCalendarReference) {
            userDefaults.set(referenceData, forKey: SettingKey.selectedAppleCalendarReference)
        } else {
            userDefaults.removeObject(forKey: SettingKey.selectedAppleCalendarReference)
        }
    }

    private func restoreGoogleAccountsIfPossible() async {
        guard googleSignInEnvironment.allowsInteractiveSignIn else {
            googleAuthMessage = googleSignInEnvironment.blockingReason
            return
        }

        GoogleSignInService.clearSavedSession()

        do {
            let storedAccounts = try googleAccountStore.loadAccounts()
            updateGoogleStoredAccounts(storedAccounts)
            reconcileSharedGoogleAccountDescriptorsWithLocalAccounts()
            if !storedAccounts.isEmpty {
                if activeGoogleAccountID == nil || !storedAccounts.contains(where: { $0.id == activeGoogleAccountID }) {
                    activeGoogleAccountID = storedAccounts.first?.id
                    persistSettings()
                }

                for storedAccount in storedAccounts {
                    await refreshGoogleCalendars(for: storedAccount.id)
                }
                return
            }
        } catch let error as GoogleAccountStoreError {
            googleAuthMessage = error.localizedDescription
            return
        } catch {
            googleAuthMessage = "Saved Google accounts could not be restored from secure storage."
            return
        }
    }

    private func restoreAppleCalendarAccessIfNeeded() async {
        guard isAppleCalendarEnabled else {
            return
        }

        refreshAppleCalendarAuthorizationState()
        guard appleCalendarAuthorizationState == .granted else {
            return
        }

        do {
            let calendars = try appleCalendarService.listWritableCalendars()
            appleCalendars = calendars
            selectedAppleCalendarID = AppleCalendarSelectionResolver.resolvedCalendarID(
                availableCalendars: calendars,
                persistedCalendarID: selectedAppleCalendarID,
                sharedReference: persistedAppleCalendarReference
            )
            persistedAppleCalendarReference = selectedAppleCalendar.map(SharedAppleCalendarReference.init(calendar:))
            if let selectedAppleCalendar {
                appleCalendarMessage = "Restored Apple Calendar access with \(selectedAppleCalendar.displayName) selected."
            } else {
                appleCalendarMessage = "Apple Calendar access is enabled, but no writable calendars are currently available."
            }
        } catch let error as AppleCalendarServiceError {
            appleCalendarMessage = error.localizedDescription
        } catch {
            appleCalendarMessage = "Apple Calendar access could not be restored from the current device state."
        }
    }

    private func clearAppleCalendarState() {
        appleCalendars = []
        selectedAppleCalendarID = ""
        persistedAppleCalendarReference = nil
        lastManagedAppleEvent = nil
    }

    private func refreshAppleCalendarAuthorizationState() {
        appleCalendarAuthorizationState = appleCalendarService.authorizationState()
    }

    private func clearLiveGoogleState() {
        googleCalendarsByAccountID = [:]
        googleSelectedCalendarIDs = [:]
        lastManagedGoogleEventsByAccountID = [:]
        googleMessagesByAccountID = [:]
        googleMessageUpdatedAtByAccountID = [:]
        googleOperationAccountIDs = []
        activeGoogleAccountID = nil
        hasAttemptedLiveGoogleSmoke = false
        liveGoogleSmokeStatus = liveGoogleDebugConfiguration.isEnabled ? .awaitingAuthentication : .idle
    }

    private func handleSharedConfigurationEnabledChange(from oldValue: Bool, to newValue: Bool) {
        guard oldValue != newValue else {
            return
        }

        persistSettings()

        guard newValue else {
            updateSharedConfigurationSyncState(.disabled, logEvent: true)
            return
        }

        updateSharedConfigurationSyncState(.idle, logEvent: true)
        reconcileSharedConfigurationAtLaunch()
    }

    private var activeResolvedGoogleAccountID: String? {
        if let activeGoogleAccountID, googleStoredAccounts.contains(where: { $0.id == activeGoogleAccountID }) {
            return activeGoogleAccountID
        }

        return googleStoredAccounts.first?.id
    }

    private var liveGoogleResolvedAccountID: String? {
        LiveGoogleAccountResolver.resolvedAccountID(
            accounts: googleStoredAccounts,
            activeAccountID: activeResolvedGoogleAccountID,
            preferredEmail: liveGoogleDebugConfiguration.preferredAccountEmail
        )
    }

    private func storedGoogleAccount(id: String) -> StoredGoogleAccount? {
        googleStoredAccounts.first(where: { $0.id == id })
    }

    private func selectedGoogleCalendar(for accountID: String) -> GoogleCalendarSummary? {
        let selectedCalendarID = googleSelectedCalendarIDs[accountID] ?? ""
        return googleCalendarsByAccountID[accountID]?.first(where: { $0.id == selectedCalendarID })
    }

    private func setGoogleMessage(_ message: String?, for accountID: String) {
        googleMessagesByAccountID[accountID] = message
        googleMessageUpdatedAtByAccountID[accountID] = message == nil ? nil : Date()

        guard let message else {
            return
        }

        let titlePrefix: String
        if let account = storedGoogleAccount(id: accountID) {
            titlePrefix = "Google calendar • \(account.displayName)"
        } else {
            titlePrefix = "Google calendar"
        }

        appendAuditTrailEntry(
            title: titlePrefix,
            detail: message,
            status: googleOperationAccountIDs.contains(accountID) ? "working" : "ready"
        )
    }

    func googleMessageTimestampLabel(for accountID: String) -> String? {
        Self.messageTimestampLabel(for: googleMessageUpdatedAtByAccountID[accountID])
    }

    func selectedGoogleCalendarID(for accountID: String) -> String {
        googleSelectedCalendarIDs[accountID] ?? ""
    }

    func selectedBookingGoogleCalendarID(for accountID: String) -> String {
        guard bookingTargetProvider == .google,
              bookingGoogleTargetAccountIDString == accountID
        else {
            return ""
        }

        return bookingGoogleTargetCalendarIDString
    }

    func setBookingCalendarTargetOptionID(_ optionID: String) {
        let parts = optionID.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard let provider = parts.first else {
            return
        }

        switch provider {
        case "apple":
            guard parts.count == 2 else { return }
            setBookingAppleCalendarID(parts[1])
        case "google":
            guard parts.count == 3 else { return }
            setBookingGoogleCalendarID(parts[2], for: parts[1])
        default:
            return
        }
    }

    func setBookingAppleCalendarID(_ calendarID: String) {
        guard appleCalendars.contains(where: { $0.id == calendarID }) else {
            return
        }

        bookingCalendarTargetProviderString = BookingCalendarTargetProvider.apple.rawValue
        bookingAppleTargetCalendarIDString = calendarID
        bookingGoogleTargetAccountIDString = ""
        bookingGoogleTargetCalendarIDString = ""
    }

    func setAppleCalendarAsBookingTarget() {
        guard let selectedAppleCalendar else {
            return
        }

        setBookingAppleCalendarID(selectedAppleCalendar.id)
    }

    func setBookingGoogleCalendarID(_ calendarID: String, for accountID: String) {
        guard googleCalendarsByAccountID[accountID]?.contains(where: { $0.id == calendarID }) == true else {
            return
        }

        bookingCalendarTargetProviderString = BookingCalendarTargetProvider.google.rawValue
        bookingAppleTargetCalendarIDString = ""
        bookingGoogleTargetAccountIDString = accountID
        bookingGoogleTargetCalendarIDString = calendarID
    }

    func refreshBookingCalendarTargetOptions() async {
        refreshAppleCalendarAuthorizationState()
        if appleCalendarAuthorizationState == .granted {
            do {
                appleCalendars = try appleCalendarService.listWritableCalendars()
            } catch let error as AppleCalendarServiceError {
                appleCalendarMessage = error.localizedDescription
            } catch {
                appleCalendarMessage = "Apple Calendar targets could not be loaded from this device."
            }
        }

        for storedAccount in googleStoredAccounts {
            guard googleCalendarsByAccountID[storedAccount.id]?.isEmpty != false,
                  !googleOperationAccountIDs.contains(storedAccount.id)
            else {
                continue
            }

            googleOperationAccountIDs.insert(storedAccount.id)
            defer {
                googleOperationAccountIDs.remove(storedAccount.id)
            }

            do {
                let authorizedAccount = try await GoogleSignInService.authorizeStoredAccount(storedAccount)
                try replaceStoredGoogleAccount(authorizedAccount.storedAccount)
                googleCalendarsByAccountID[storedAccount.id] = try await googleCalendarService.listWritableCalendars(
                    accessToken: authorizedAccount.accessToken
                )
            } catch {
                setGoogleMessage("Writable Google calendars could not be loaded for booking targets.", for: storedAccount.id)
            }
        }
    }

    func setSelectedGoogleCalendarID(_ calendarID: String, for accountID: String) {
        let previousCalendarID = googleSelectedCalendarIDs[accountID] ?? ""
        googleSelectedCalendarIDs[accountID] = calendarID
        activeGoogleAccountID = accountID
        reconcileSharedGoogleAccountDescriptorsWithLocalAccounts()
        persistSettings()

        guard hasPrepared, previousCalendarID != calendarID else { return }
        Task { @MainActor [weak self] in
            await self?.handleGoogleCalendarSelectionChange(
                for: accountID,
                from: previousCalendarID,
                to: calendarID
            )
        }
    }

    private func updateGoogleStoredAccounts(_ accounts: [StoredGoogleAccount]) {
        googleStoredAccounts = accounts

        let accountIDs = Set(accounts.map(\.id))
        googleCalendarsByAccountID = googleCalendarsByAccountID.filter { accountIDs.contains($0.key) }
        googleMessagesByAccountID = googleMessagesByAccountID.filter { accountIDs.contains($0.key) }
        googleMessageUpdatedAtByAccountID = googleMessageUpdatedAtByAccountID.filter { accountIDs.contains($0.key) }
        lastManagedGoogleEventsByAccountID = lastManagedGoogleEventsByAccountID.filter { accountIDs.contains($0.key) }
        googleOperationAccountIDs = googleOperationAccountIDs.filter { accountIDs.contains($0) }
        if let activeGoogleAccountID, !accountIDs.contains(activeGoogleAccountID) {
            self.activeGoogleAccountID = accounts.first?.id
        }
        if accounts.isEmpty {
            hasAttemptedLiveGoogleSmoke = false
            liveGoogleSmokeStatus = liveGoogleDebugConfiguration.isEnabled ? .awaitingAuthentication : .idle
        }
    }

    private func replaceStoredGoogleAccount(_ account: StoredGoogleAccount) throws {
        let accounts = try googleAccountStore.upsertAccount(account)
        updateGoogleStoredAccounts(accounts)
        reconcileSharedGoogleAccountDescriptorsWithLocalAccounts()
    }

    private func sharedGoogleDescriptor(
        forAccountID accountID: String,
        email: String
    ) -> SharedGoogleAccountDescriptor? {
        GoogleSharedAccountHandoff.matchingDescriptor(
            forAccountID: accountID,
            email: email,
            descriptors: sharedGoogleAccountDescriptors
        )
    }

    private func reconcileSharedGoogleAccountDescriptorsWithLocalAccounts() {
        sharedGoogleAccountDescriptors = GoogleSharedAccountHandoff.reconciledDescriptors(
            currentDescriptors: sharedGoogleAccountDescriptors,
            localAccounts: googleStoredAccounts,
            googleSelectedCalendarIDs: googleSelectedCalendarIDs,
            googleCalendarsByAccountID: googleCalendarsByAccountID
        )
    }

    private func removeSharedGoogleAccountDescriptor(
        matchingAccountID accountID: String,
        email: String?
    ) {
        let normalizedEmail = email?.lowercased()
        sharedGoogleAccountDescriptors.removeAll { descriptor in
            descriptor.id == accountID
                || (normalizedEmail != nil && descriptor.email.lowercased() == normalizedEmail)
        }
    }

    private func googleAuthorizationFailureMessage(for error: Error) -> String {
        let description = error.localizedDescription
        if description.localizedCaseInsensitiveContains("keychain") {
            return "Google authorization did not complete: \(description). On macOS this usually means the app is running unsigned or local Xcode signing credentials/provisioning are not valid."
        }

        return "Google authorization did not complete: \(description)"
    }

    private func liveGoogleEmailMismatchMessage(for account: StoredGoogleAccount) -> String? {
        guard
            liveGoogleDebugConfiguration.isEnabled,
            let preferredAccountEmail = liveGoogleDebugConfiguration.preferredAccountEmail,
            account.email.compare(preferredAccountEmail, options: .caseInsensitive) != .orderedSame
        else {
            return nil
        }

        return "Google authorization completed as \(account.email), but live verification requires \(preferredAccountEmail)."
    }

    private func runLiveGoogleSmokeIfNeeded() async {
        guard liveGoogleDebugConfiguration.isEnabled, !hasAttemptedLiveGoogleSmoke else {
            return
        }

        guard let accountID = liveGoogleResolvedAccountID else {
            liveGoogleSmokeStatus = .awaitingAuthentication
            return
        }

        hasAttemptedLiveGoogleSmoke = true

        let targetCalendar = selectedGoogleCalendarForLiveSmoke(accountID: accountID)
        guard let targetCalendar else {
            let calendarName = liveGoogleDebugConfiguration.preferredCalendarName ?? "(missing target calendar)"
            let message = "Live verification could not find a writable calendar named \(calendarName)."
            liveGoogleSmokeStatus = .failed(message)
            setGoogleMessage(message, for: accountID)
            return
        }

        googleSelectedCalendarIDs[accountID] = targetCalendar.id
        persistSettings()
        googleOperationAccountIDs.insert(accountID)
        liveGoogleSmokeStatus = .running("Creating a managed busy slot in \(targetCalendar.displayName)…")

        do {
            guard let storedAccount = storedGoogleAccount(id: accountID) else {
                throw GoogleSignInServiceError.storedAccountCorrupt
            }
            let authorizedAccount = try await GoogleSignInService.authorizeStoredAccount(storedAccount)
            try replaceStoredGoogleAccount(authorizedAccount.storedAccount)
            let event = try await googleCalendarService.createManagedBusyEvent(
                in: targetCalendar,
                accessToken: authorizedAccount.accessToken
            )
            lastManagedGoogleEventsByAccountID[accountID] = event
            liveGoogleSmokeStatus = .running("Deleting the managed busy slot from \(targetCalendar.displayName)…")
            try await googleCalendarService.deleteManagedBusyEvent(
                event,
                accessToken: authorizedAccount.accessToken
            )
            lastManagedGoogleEventsByAccountID[accountID] = nil
            let message = "Created and deleted a managed busy slot in \(targetCalendar.displayName)."
            setGoogleMessage(message, for: accountID)
            liveGoogleSmokeStatus = .passed(message)
        } catch let error as GoogleSignInServiceError {
            let message = error.localizedDescription
            setGoogleMessage(message, for: accountID)
            liveGoogleSmokeStatus = .failed(message)
        } catch let error as GoogleCalendarServiceError {
            let message = error.localizedDescription
            setGoogleMessage(message, for: accountID)
            liveGoogleSmokeStatus = .failed(message)
        } catch let error as GoogleAccountStoreError {
            let message = error.localizedDescription
            setGoogleMessage(message, for: accountID)
            liveGoogleSmokeStatus = .failed(message)
        } catch {
            let message = "Live Google verification failed before the busy slot round-trip completed."
            setGoogleMessage(message, for: accountID)
            liveGoogleSmokeStatus = .failed(message)
        }

        googleOperationAccountIDs.remove(accountID)
    }

    private func selectedGoogleCalendarForLiveSmoke(accountID: String) -> GoogleCalendarSummary? {
        if let preferredCalendarName = liveGoogleDebugConfiguration.preferredCalendarName {
            return googleCalendarsByAccountID[accountID]?.first(where: { $0.matches(name: preferredCalendarName) })
        }

        return selectedGoogleCalendar(for: accountID)
    }

    private func handleAppleCalendarSelectionChange(
        from previousCalendarID: String,
        to nextCalendarID: String
    ) async {
        if !previousCalendarID.isEmpty {
            await cleanupDeselectedAppleCalendar(calendarID: previousCalendarID)
        }

        if previousCalendarID != nextCalendarID {
            lastManagedAppleEvent = nil
        }

        await syncAfterParticipantConfigurationChange()
    }

    private func handleGoogleCalendarSelectionChange(
        for accountID: String,
        from previousCalendarID: String,
        to nextCalendarID: String
    ) async {
        if !previousCalendarID.isEmpty {
            await cleanupDeselectedGoogleCalendar(
                accountID: accountID,
                calendarID: previousCalendarID
            )
        }

        if previousCalendarID != nextCalendarID {
            lastManagedGoogleEventsByAccountID[accountID] = nil
        }

        await syncAfterParticipantConfigurationChange()
    }

    private func cleanupDeselectedAppleCalendar(calendarID: String) async {
        guard !calendarID.isEmpty else { return }
        guard appleCalendarAuthorizationState == .granted else { return }

        let participant = BusyMirrorParticipant(
            provider: .apple,
            accountID: nil,
            calendarID: calendarID,
            displayName: appleCalendarSummary(for: calendarID)?.displayName ?? "Previous Apple calendar"
        )

        do {
            let mirrors = try appleCalendarService.listManagedMirrorEvents(
                in: participant,
                window: BusyMirrorSyncWindow.defaultWindow()
            )
            for mirror in mirrors {
                try appleCalendarService.deleteManagedMirrorEvent(mirror)
            }

            if !mirrors.isEmpty {
                appleCalendarMessage = "Removed \(mirrors.count) mirrored busy hold(s) from \(participant.displayName)."
            }
        } catch let error as AppleCalendarServiceError {
            appleCalendarMessage = error.localizedDescription
        } catch {
            appleCalendarMessage = "Apple Calendar cleanup failed from the current app session."
        }
    }

    private func cleanupDeselectedGoogleCalendar(
        accountID: String,
        calendarID: String
    ) async {
        guard !calendarID.isEmpty else { return }
        guard let storedAccount = storedGoogleAccount(id: accountID) else { return }

        do {
            let authorizedAccount = try await GoogleSignInService.authorizeStoredAccount(storedAccount)
            try replaceStoredGoogleAccount(authorizedAccount.storedAccount)
            let calendar = try await googleCalendarSummary(
                for: accountID,
                calendarID: calendarID,
                authorizedAccount: authorizedAccount
            )
            let participant = BusyMirrorParticipant(
                provider: .google,
                accountID: accountID,
                calendarID: calendarID,
                displayName: "\(storedAccount.displayName) • \(calendar?.displayName ?? "Previous Google calendar")"
            )
            let mirrors = try await googleCalendarService.listManagedMirrorEvents(
                in: participant,
                calendarTimeZone: calendar?.timeZone,
                window: BusyMirrorSyncWindow.defaultWindow(),
                accessToken: authorizedAccount.accessToken
            )
            for mirror in mirrors {
                try await googleCalendarService.deleteManagedMirrorEvent(
                    mirror,
                    accessToken: authorizedAccount.accessToken
                )
            }

            if !mirrors.isEmpty {
                setGoogleMessage(
                    "Removed \(mirrors.count) mirrored busy hold(s) from \(participant.displayName).",
                    for: accountID
                )
            }
        } catch let error as GoogleSignInServiceError {
            setGoogleMessage(error.localizedDescription, for: accountID)
        } catch let error as GoogleCalendarServiceError {
            setGoogleMessage(error.localizedDescription, for: accountID)
        } catch let error as GoogleAccountStoreError {
            setGoogleMessage(error.localizedDescription, for: accountID)
        } catch {
            setGoogleMessage(
                "Google Calendar cleanup failed. Try again from the current app window.",
                for: accountID
            )
        }
    }

    private func googleCalendarSummary(
        for accountID: String,
        calendarID: String,
        authorizedAccount: GoogleAuthorizedAccount
    ) async throws -> GoogleCalendarSummary? {
        if let cachedCalendar = googleCalendarsByAccountID[accountID]?.first(where: { $0.id == calendarID }) {
            return cachedCalendar
        }

        let calendars = try await googleCalendarService.listWritableCalendars(
            accessToken: authorizedAccount.accessToken
        )
        googleCalendarsByAccountID[accountID] = calendars
        return calendars.first(where: { $0.id == calendarID })
    }

    private static func loadPollInterval(from userDefaults: UserDefaults) -> Int {
        let storedValue = userDefaults.integer(forKey: SettingKey.pollIntervalMinutes)
        if storedValue == 0 {
            return AppSettingsDefaults.pollIntervalMinutes
        }
        return max(1, min(60, storedValue))
    }

    private static func initialSharedConfigurationSyncState(
        isSharedConfigurationEnabled: Bool,
        sharedConfigurationStore: any SharedAppConfigurationStoring
    ) -> SharedConfigurationSyncState {
        if !isSharedConfigurationEnabled {
            return .disabled
        }

        if !sharedConfigurationStore.isAvailable {
            return .unavailable
        }

        return .idle
    }

    private static func loadAuditTrailLogLength(
        from userDefaults: UserDefaults,
        platform: HarnessPlatformTarget
    ) -> AuditTrailLogLength {
        let storedValue = userDefaults.string(forKey: SettingKey.auditTrailLogLength)
        return storedValue.flatMap(AuditTrailLogLength.init(rawValue:)) ?? AuditTrailLogLength.defaultValue(for: platform)
    }

    private static func loadGoogleSelectedCalendarIDs(from userDefaults: UserDefaults) -> [String: String] {
        guard let dictionary = userDefaults.dictionary(forKey: SettingKey.selectedGoogleCalendarIDs) else {
            return [:]
        }

        return dictionary.reduce(into: [:]) { partialResult, element in
            if let value = element.value as? String {
                partialResult[element.key] = value
            }
        }
    }

    private static func loadSharedGoogleAccountDescriptors(from userDefaults: UserDefaults) -> [SharedGoogleAccountDescriptor] {
        guard let data = userDefaults.data(forKey: SettingKey.sharedGoogleAccountDescriptors) else {
            return []
        }

        return (try? JSONDecoder().decode([SharedGoogleAccountDescriptor].self, from: data)) ?? []
    }

    private static func loadUITestBookingInboxAdminToken(
        launchOptions: HarnessLaunchOptions,
        processInfo: ProcessInfo,
        fileManager: FileManager
    ) -> String {
        guard launchOptions.uiTestMode else {
            return ""
        }

        let environmentToken = processInfo.environment[EnvironmentKey.uiTestBookingInboxAdminToken] ?? ""
        let trimmedEnvironmentToken = environmentToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedEnvironmentToken.isEmpty {
            return trimmedEnvironmentToken
        }

        let environmentPath = processInfo.environment[EnvironmentKey.uiTestBookingInboxAdminTokenFile] ?? ""
        let tokenFileURL: URL
        if !environmentPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            tokenFileURL = URL(fileURLWithPath: environmentPath)
        } else if let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            tokenFileURL = applicationSupportURL
                .appendingPathComponent("Calendar Busy Sync", isDirectory: true)
                .appendingPathComponent("UI Test", isDirectory: true)
                .appendingPathComponent("booking-inbox-admin-token", isDirectory: false)
        } else {
            return ""
        }

        guard let data = try? Data(contentsOf: tokenFileURL),
              let token = String(data: data, encoding: .utf8)
        else {
            return ""
        }

        try? fileManager.removeItem(at: tokenFileURL)
        return token.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func loadBookingSetupSnapshot(from userDefaults: UserDefaults) -> BookingSetupSnapshot {
        guard let data = userDefaults.data(forKey: SettingKey.bookingSetupSnapshot) else {
            return .notStarted
        }

        return (try? JSONDecoder().decode(BookingSetupSnapshot.self, from: data)) ?? .notStarted
    }

    private static func loadBookingAppointmentTypes(from userDefaults: UserDefaults) -> [BookingAppointmentType] {
        guard let data = userDefaults.data(forKey: SettingKey.bookingAppointmentTypes),
              let appointmentTypes = try? JSONDecoder().decode([BookingAppointmentType].self, from: data),
              !appointmentTypes.isEmpty,
              (try? BookingConfigurationValidator.validateAppointmentTypes(appointmentTypes)) != nil
        else {
            return BookingDraftFactory.defaultAppointmentTypes
        }

        return appointmentTypes
    }

    private static func validSharedBookingAppointmentTypes(
        _ appointmentTypes: [BookingAppointmentType],
        fallback: [BookingAppointmentType]
    ) -> [BookingAppointmentType] {
        guard !appointmentTypes.isEmpty,
              (try? BookingConfigurationValidator.validateAppointmentTypes(appointmentTypes)) != nil
        else {
            return fallback.isEmpty ? BookingDraftFactory.defaultAppointmentTypes : fallback
        }

        return appointmentTypes
    }

    private static func normalizedAppointmentSlug(_ value: String) -> String {
        let lowercased = value.lowercased()
        let replaced = lowercased.replacingOccurrences(
            of: #"[^a-z0-9]+"#,
            with: "-",
            options: .regularExpression
        )
        let trimmed = replaced.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let clipped = String(trimmed.prefix(54)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return clipped.isEmpty ? "meeting" : clipped
    }

    private static func loadSettingsMutationDate(from userDefaults: UserDefaults) -> Date {
        userDefaults.object(forKey: SettingKey.lastModifiedAt) as? Date ?? .distantPast
    }

    private static func initialIOSBackgroundRefreshState(
        launchOptions: HarnessLaunchOptions,
        scheduler: any IOSBackgroundRefreshScheduling
    ) -> IOSBackgroundRefreshState {
        guard launchOptions.platformTarget == .ios else {
            return .unsupported
        }

        guard !launchOptions.uiTestMode, launchOptions.appStoreScreenshotMode == nil else {
            return .unsupported
        }

        switch scheduler.availability {
        case .unsupported:
            return .unsupported
        case .available:
            return .scheduled(Date().addingTimeInterval(IOSBackgroundRefreshConstants.earliestBeginInterval))
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        }
    }

    private static func loadAppleCalendarReference(from userDefaults: UserDefaults) -> SharedAppleCalendarReference? {
        guard let data = userDefaults.data(forKey: SettingKey.selectedAppleCalendarReference) else {
            return nil
        }

        return try? JSONDecoder().decode(SharedAppleCalendarReference.self, from: data)
    }

    private static func encodeAppleCalendarReference(_ reference: SharedAppleCalendarReference?) -> Data? {
        guard let reference else {
            return nil
        }

        return try? JSONEncoder().encode(reference)
    }

    private static func encodeSharedGoogleAccountDescriptors(
        _ descriptors: [SharedGoogleAccountDescriptor]
    ) -> Data? {
        guard !descriptors.isEmpty else {
            return nil
        }

        return try? JSONEncoder().encode(descriptors)
    }

    private static func bookingGitHubPublishMessage(
        _ summary: BookingGitHubPublisher.PublishSummary,
        reason: String
    ) -> String {
        if !summary.didChangeRemote {
            return "\(reason): no GitHub changes needed; \(summary.skippedCount) file(s) already matched."
        }

        var parts: [String] = []
        if summary.uploadedCount > 0 {
            parts.append("\(summary.uploadedCount) new")
        }
        if summary.overwrittenCount > 0 {
            parts.append("\(summary.overwrittenCount) overwritten")
        }
        if summary.skippedCount > 0 {
            parts.append("\(summary.skippedCount) unchanged")
        }
        let remoteWarning = summary.remoteChangedPaths.isEmpty ? "" : " Remote generated files changed before overwrite."
        return "\(reason): published \(parts.joined(separator: ", ")) file(s).\(remoteWarning)"
    }

    private static let syncTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d, HH:mm:ss"
        return formatter
    }()

    private static let olderMessageTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }()

    private static func messageTimestampLabel(for date: Date?, now: Date = Date()) -> String? {
        guard let date else {
            return nil
        }

        let calendar = Calendar.current
        let age = now.timeIntervalSince(date)

        if age < 60 {
            return "less than a minute ago"
        }

        if calendar.isDate(date, inSameDayAs: now) {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            return formatter.localizedString(for: date, relativeTo: now)
        }

        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }

        return olderMessageTimestampFormatter.string(from: date)
    }
}

private struct SyncParticipantsBundle {
    let participants: [BusyMirrorParticipant]
    let googleAccountsByID: [String: GoogleAuthorizedAccount]
    let googleCalendarsByAccountID: [String: GoogleCalendarSummary]
}

private struct BookingApprovalResult {
    let event: AppleManagedEventRecord
    let inviteFileURL: URL?
}

private struct BookingDeclineResult {
    let event: GoogleManagedEventRecord?
    let inviteFileURL: URL?
}

private enum BookingApprovalError: Error {
    case missingCalendar
    case slotUnavailable
}

struct LiveGoogleDebugConfiguration: Equatable {
    let isEnabled: Bool
    let preferredAccountEmail: String?
    let preferredCalendarName: String?

    static func from(processInfo: ProcessInfo) -> LiveGoogleDebugConfiguration {
        let environment = processInfo.environment
        let enabled = environment["CALENDAR_BUSY_SYNC_LIVE_E2E"] == "1"
        let preferredAccountEmail = environment["CALENDAR_BUSY_SYNC_E2E_ACCOUNT_EMAIL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        let preferredCalendarName = environment["CALENDAR_BUSY_SYNC_E2E_CALENDAR_NAME"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty

        return LiveGoogleDebugConfiguration(
            isEnabled: enabled,
            preferredAccountEmail: preferredAccountEmail,
            preferredCalendarName: preferredCalendarName
        )
    }
}

struct IOSBackgroundRefreshDebugConfiguration: Equatable {
    let runImmediately: Bool

    static func from(processInfo: ProcessInfo) -> IOSBackgroundRefreshDebugConfiguration {
        from(environment: processInfo.environment)
    }

    static func from(environment: [String: String]) -> IOSBackgroundRefreshDebugConfiguration {
        IOSBackgroundRefreshDebugConfiguration(
            runImmediately: environment["CALENDAR_BUSY_SYNC_RUN_IOS_BG_REFRESH_NOW"] == "1"
        )
    }
}

enum LiveGoogleAccountResolver {
    static func resolvedAccountID(
        accounts: [StoredGoogleAccount],
        activeAccountID: String?,
        preferredEmail: String?
    ) -> String? {
        if
            let preferredEmail = preferredEmail?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            let preferredAccount = accounts.first(where: {
                $0.email.compare(preferredEmail, options: .caseInsensitive) == .orderedSame
            })
        {
            return preferredAccount.id
        }

        if let activeAccountID, accounts.contains(where: { $0.id == activeAccountID }) {
            return activeAccountID
        }

        return accounts.first?.id
    }
}

private extension AppleCalendarAuthorizationState {
    var auditTrailStatus: String {
        switch self {
        case .granted:
            return "ready"
        case .denied:
            return "failed"
        case .restricted:
            return "blocked"
        case .notDetermined:
            return "pending"
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
