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
    @Published private(set) var appleCalendarMessage: String?
    @Published private(set) var appleCalendars: [AppleCalendarSummary] = []
    @Published private(set) var lastManagedAppleEvent: AppleManagedEventRecord?
    @Published private(set) var isAppleCalendarOperationInFlight = false
    @Published private(set) var googleStoredAccounts: [StoredGoogleAccount] = []
    @Published private(set) var googleAuthMessage: String?
    @Published private(set) var isGoogleAuthInFlight = false
    @Published private(set) var googleCalendarsByAccountID: [String: [GoogleCalendarSummary]] = [:]
    @Published private(set) var googleMessagesByAccountID: [String: String] = [:]
    @Published private(set) var lastManagedGoogleEventsByAccountID: [String: GoogleManagedEventRecord] = [:]
    @Published private(set) var googleOperationAccountIDs: Set<String> = []
    @Published private(set) var activeGoogleAccountID: String?
    @Published private(set) var liveGoogleSmokeStatus: LiveGoogleSmokeStatus = .idle
    @Published private(set) var isSyncInFlight = false
    @Published private(set) var lastBusyMirrorSyncSummary: BusyMirrorSyncSummary?
    @Published private(set) var syncMessage: String?
    @Published var pollIntervalMinutes: Int {
        didSet {
            persistSettings()
            restartSyncLoopIfNeeded()
        }
    }
    @Published var auditTrailLogLength: AuditTrailLogLength {
        didSet { persistSettings() }
    }
    @Published var usesCustomGoogleOAuthApp: Bool {
        didSet { persistSettingsAndRefreshGoogleConfiguration() }
    }
    @Published var customGoogleOAuthClientID: String {
        didSet { persistSettingsAndRefreshGoogleConfiguration() }
    }
    @Published var customGoogleOAuthServerClientID: String {
        didSet { persistSettingsAndRefreshGoogleConfiguration() }
    }
    @Published var selectedAppleCalendarID: String {
        didSet {
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
    private let appleCalendarService: any AppleCalendarProviding
    private let appleCalendarSettingsOpener: any AppleCalendarSettingsOpening
    private let googleCalendarService: GoogleCalendarService
    private let googleAccountStore: any GoogleAccountStoring
    private let googleSignInEnvironment: GoogleSignInEnvironment
    private let liveGoogleDebugConfiguration: LiveGoogleDebugConfiguration
    private var hasPrepared = false
    private var hasAttemptedLiveGoogleSmoke = false
    private var syncLoopTask: Task<Void, Never>?

    private enum SettingKey {
        static let pollIntervalMinutes = "settings.pollIntervalMinutes"
        static let auditTrailLogLength = "settings.auditTrailLogLength"
        static let usesAppleCalendar = "settings.appleCalendar.enabled"
        static let selectedAppleCalendarID = "settings.appleCalendar.selectedCalendarID"
        static let usesCustomGoogleOAuthApp = "settings.googleOAuth.usesCustomApp"
        static let customGoogleOAuthClientID = "settings.googleOAuth.clientID"
        static let customGoogleOAuthServerClientID = "settings.googleOAuth.serverClientID"
        static let selectedGoogleCalendarIDs = "settings.googleCalendar.selectedCalendarIDs"
        static let activeGoogleAccountID = "settings.googleCalendar.activeAccountID"
    }

    init(
        launchOptions: HarnessLaunchOptions,
        fileManager: FileManager = .default,
        launchDate: Date = Date(),
        userDefaults: UserDefaults = .standard,
        processInfo: ProcessInfo = .processInfo,
        appleCalendarService: (any AppleCalendarProviding)? = nil,
        appleCalendarSettingsOpener: (any AppleCalendarSettingsOpening)? = nil,
        googleCalendarService: GoogleCalendarService? = nil,
        googleAccountStore: (any GoogleAccountStoring)? = nil,
        googleSignInEnvironment: GoogleSignInEnvironment? = nil,
        liveGoogleDebugConfiguration: LiveGoogleDebugConfiguration? = nil
    ) {
        self.launchOptions = launchOptions
        self.loader = ScenarioLoader()
        self.fileManager = fileManager
        self.launchDate = launchDate
        self.userDefaults = userDefaults
        let resolvedAppleCalendarService = appleCalendarService ?? AppleCalendarService()
        self.appleCalendarService = resolvedAppleCalendarService
        self.appleCalendarSettingsOpener = appleCalendarSettingsOpener ?? AppleCalendarSettingsOpener()
        self.googleCalendarService = googleCalendarService ?? GoogleCalendarService()
        self.googleAccountStore = googleAccountStore ?? GoogleAccountStore()
        self.googleSignInEnvironment = googleSignInEnvironment ?? GoogleSignInEnvironment.current()
        self.liveGoogleDebugConfiguration = liveGoogleDebugConfiguration ?? LiveGoogleDebugConfiguration.from(processInfo: processInfo)
        self.pollIntervalMinutes = Self.loadPollInterval(from: userDefaults)
        self.auditTrailLogLength = Self.loadAuditTrailLogLength(from: userDefaults, platform: launchOptions.platformTarget)
        self.isAppleCalendarEnabled = userDefaults.object(forKey: SettingKey.usesAppleCalendar) as? Bool ?? false
        self.selectedAppleCalendarID = userDefaults.string(forKey: SettingKey.selectedAppleCalendarID) ?? ""
        self.appleCalendarAuthorizationState = resolvedAppleCalendarService.authorizationState()
        self.usesCustomGoogleOAuthApp = userDefaults.object(forKey: SettingKey.usesCustomGoogleOAuthApp) as? Bool ?? false
        self.customGoogleOAuthClientID = userDefaults.string(forKey: SettingKey.customGoogleOAuthClientID) ?? ""
        self.customGoogleOAuthServerClientID = userDefaults.string(forKey: SettingKey.customGoogleOAuthServerClientID) ?? ""
        self.googleSelectedCalendarIDs = Self.loadGoogleSelectedCalendarIDs(from: userDefaults)
        self.activeGoogleAccountID = userDefaults.string(forKey: SettingKey.activeGoogleAccountID)
        if self.liveGoogleDebugConfiguration.isEnabled {
            self.liveGoogleSmokeStatus = .awaitingAuthentication
        }
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
        }

        refreshGoogleConfiguration()
        refreshAppleCalendarAuthorizationState()
        await restoreAppleCalendarAccessIfNeeded()
        await restoreGoogleAccountsIfPossible()
        restartSyncLoopIfNeeded()
        await syncNowIfReady()
    }

    var supportsPollingSettings: Bool {
        launchOptions.platformTarget == .macos
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

    var canOpenAppleCalendarSettings: Bool {
        launchOptions.platformTarget == .macos
    }

    var selectedAppleCalendar: AppleCalendarSummary? {
        appleCalendars.first(where: { $0.id == selectedAppleCalendarID })
    }

    var selectedParticipantCount: Int {
        googleAccountCards.filter { $0.selectedCalendar != nil }.count
            + (selectedAppleCalendar == nil ? 0 : 1)
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

    var googleAccountCards: [GoogleAccountCardModel] {
        let activeAccountID = activeResolvedGoogleAccountID

        return googleStoredAccounts.sorted { lhs, rhs in
            if lhs.id == activeAccountID { return true }
            if rhs.id == activeAccountID { return false }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }.map { storedAccount in
            GoogleAccountCardModel(
                account: storedAccount.connectedAccount,
                calendars: googleCalendarsByAccountID[storedAccount.id] ?? [],
                selectedCalendarID: googleSelectedCalendarIDs[storedAccount.id] ?? "",
                message: googleMessagesByAccountID[storedAccount.id],
                lastManagedEvent: lastManagedGoogleEventsByAccountID[storedAccount.id],
                isOperationInFlight: googleOperationAccountIDs.contains(storedAccount.id),
                isActive: storedAccount.id == activeAccountID
            )
        }
    }

    var googleReadyAccountCount: Int {
        googleAccountCards.filter { !$0.needsAttention }.count
    }

    var googleNeedsAttentionCount: Int {
        googleAccountCards.filter(\.needsAttention).count
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
        !isGoogleAuthInFlight && googleOAuthResolutionMessage == nil && googleSignInEnvironment.allowsInteractiveSignIn
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
        if googleStoredAccounts.isEmpty {
            return "Connect Google to load writable calendars from each signed-in account."
        }

        let readyCount = googleAccountCards.filter { $0.selectedCalendar != nil }.count
        let total = googleAccountCards.count
        return "\(readyCount) of \(total) Google accounts have a participating calendar selected."
    }

    var liveGoogleSmokeStatusLabel: String? {
        liveGoogleSmokeStatus.statusLabel
    }

    var liveGoogleSmokeSummary: String? {
        liveGoogleSmokeStatus.summary
    }

    var auditTrailEntries: [AuditTrailEntry] {
        var entries = AuditTrailBuilder.entries(
            for: state,
            platform: launchOptions.platformTarget,
            pollIntervalMinutes: pollIntervalMinutes,
            auditTrailLogLength: auditTrailLogLength,
            googleOAuth: googleOAuthConfiguration
        )

        entries.insert(contentsOf: appleCalendarAuditEntries, at: min(2, entries.count))
        entries.insert(contentsOf: googleCalendarAuditEntries, at: min(2, entries.count))
        entries.insert(contentsOf: googleAuditEntries, at: min(2, entries.count))
        entries.insert(contentsOf: syncAuditEntries, at: min(2, entries.count))

        if let limit = auditTrailLogLength.limit, entries.count > limit {
            return Array(entries.suffix(limit))
        }

        return entries
    }

    func handleIncomingURL(_ url: URL) {
        _ = GoogleSignInService.handle(url: url)
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
                persistedCalendarID: selectedAppleCalendarID
            )
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

            for participant in participantsBundle.participants {
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
                }
            }

            let desiredMirrors = BusyMirrorSyncPlanner.desiredMirrors(
                participants: participantsBundle.participants,
                sourceEvents: sourceEvents
            )
            let operations = BusyMirrorSyncPlanner.operations(
                desiredMirrors: desiredMirrors,
                existingMirrors: existingMirrors
            )

            var createdCount = 0
            var updatedCount = 0
            var deletedCount = 0
            var failureMessages: [String] = []

            for operation in operations {
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
                    failureMessages.append(error.localizedDescription)
                }
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
                    syncMessage = "Busy mirroring is up to date across \(summary.participantCount) selected calendars."
                }
            } else {
                syncMessage = "Busy mirroring completed with \(summary.failedCount) failed write(s)."
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
        }
    }

    func connectGoogleAccount() async {
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
                hint: liveGoogleDebugConfiguration.preferredAccountEmail
            )
            if let mismatchMessage = liveGoogleEmailMismatchMessage(for: storedAccount) {
                GoogleSignInService.clearSavedSession()
                googleAuthMessage = mismatchMessage
                return
            }
            let accounts = try googleAccountStore.upsertAccount(storedAccount)
            updateGoogleStoredAccounts(accounts)
            activeGoogleAccountID = storedAccount.id
            persistSettings()
            googleAuthMessage = storedAccount.connectedAccount.serverAuthCodeAvailable
                ? "Google authorization succeeded. A server auth code was issued for backend exchange."
                : "Google authorization succeeded. Added \(storedAccount.displayName)."
            await refreshGoogleCalendars(for: storedAccount.id)
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
        do {
            GoogleSignInService.removeCurrentUserIfMatches(
                accountID: accountID,
                using: googleOAuthResolution
            )
            let accounts = try googleAccountStore.removeAccount(id: accountID)
            updateGoogleStoredAccounts(accounts)
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

    func refreshGoogleCalendars(for accountID: String) async {
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
            let preferredCalendarName = accountID == liveGoogleResolvedAccountID
                ? liveGoogleDebugConfiguration.preferredCalendarName
                : nil
            let resolvedCalendarID = GoogleCalendarSelectionResolver.resolvedCalendarID(
                availableCalendars: calendars,
                persistedCalendarID: googleSelectedCalendarIDs[accountID] ?? "",
                preferredCalendarName: preferredCalendarName
            )
            let previousCalendarID = googleSelectedCalendarIDs[accountID] ?? ""
            googleSelectedCalendarIDs[accountID] = resolvedCalendarID
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
        guard selectedParticipantCount >= 1 else {
            return
        }

        await syncNow()
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

    private func loadInitialState() throws -> ScenarioState {
        guard launchOptions.scenarioRoot != nil || launchOptions.scenarioName != nil else {
            return .emptyLiveShell
        }

        return try loader.load(using: launchOptions)
    }

    private func persistSettings() {
        userDefaults.set(max(1, min(60, pollIntervalMinutes)), forKey: SettingKey.pollIntervalMinutes)
        userDefaults.set(auditTrailLogLength.rawValue, forKey: SettingKey.auditTrailLogLength)
        userDefaults.set(isAppleCalendarEnabled, forKey: SettingKey.usesAppleCalendar)
        userDefaults.set(selectedAppleCalendarID, forKey: SettingKey.selectedAppleCalendarID)
        userDefaults.set(usesCustomGoogleOAuthApp, forKey: SettingKey.usesCustomGoogleOAuthApp)
        userDefaults.set(customGoogleOAuthClientID, forKey: SettingKey.customGoogleOAuthClientID)
        userDefaults.set(customGoogleOAuthServerClientID, forKey: SettingKey.customGoogleOAuthServerClientID)
        userDefaults.set(googleSelectedCalendarIDs, forKey: SettingKey.selectedGoogleCalendarIDs)
        userDefaults.set(activeGoogleAccountID, forKey: SettingKey.activeGoogleAccountID)
    }

    private func persistSettingsAndRefreshGoogleConfiguration() {
        persistSettings()
        refreshGoogleConfiguration()
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

    private func restoreGoogleAccountsIfPossible() async {
        GoogleSignInService.clearSavedSession()

        do {
            let storedAccounts = try googleAccountStore.loadAccounts()
            updateGoogleStoredAccounts(storedAccounts)
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
                persistedCalendarID: selectedAppleCalendarID
            )
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
        googleOperationAccountIDs = []
        activeGoogleAccountID = nil
        hasAttemptedLiveGoogleSmoke = false
        liveGoogleSmokeStatus = liveGoogleDebugConfiguration.isEnabled ? .awaitingAuthentication : .idle
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
    }

    func selectedGoogleCalendarID(for accountID: String) -> String {
        googleSelectedCalendarIDs[accountID] ?? ""
    }

    func setSelectedGoogleCalendarID(_ calendarID: String, for accountID: String) {
        let previousCalendarID = googleSelectedCalendarIDs[accountID] ?? ""
        googleSelectedCalendarIDs[accountID] = calendarID
        activeGoogleAccountID = accountID
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

    func setActiveGoogleAccount(_ accountID: String) {
        guard googleStoredAccounts.contains(where: { $0.id == accountID }) else { return }
        activeGoogleAccountID = accountID
        persistSettings()
    }

    private func updateGoogleStoredAccounts(_ accounts: [StoredGoogleAccount]) {
        googleStoredAccounts = accounts

        let accountIDs = Set(accounts.map(\.id))
        googleCalendarsByAccountID = googleCalendarsByAccountID.filter { accountIDs.contains($0.key) }
        googleSelectedCalendarIDs = googleSelectedCalendarIDs.filter { accountIDs.contains($0.key) }
        googleMessagesByAccountID = googleMessagesByAccountID.filter { accountIDs.contains($0.key) }
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

    private var googleAuditEntries: [AuditTrailEntry] {
        var entries: [AuditTrailEntry] = []

        entries.append(
            AuditTrailEntry(
                timestampLabel: "Google",
                title: googleStoredAccounts.isEmpty ? "Google account status" : "Google accounts connected",
                detail: googleStoredAccounts.isEmpty
                    ? "No Google account is currently connected."
                    : "\(googleStoredAccounts.count) Google account(s) are connected.",
                status: googleStoredAccounts.isEmpty ? "signed-out" : "connected"
            )
        )

        if let message = googleOAuthResolutionMessage {
            entries.append(
                AuditTrailEntry(
                    timestampLabel: "Google",
                    title: "Custom OAuth validation",
                    detail: message,
                    status: "blocked"
                )
            )
        }

        if let message = googleAuthMessage {
            entries.append(
                AuditTrailEntry(
                    timestampLabel: "Google",
                    title: "Authorization status",
                    detail: message,
                    status: googleStoredAccounts.isEmpty ? "pending" : "ready"
                )
            )
        }

        return entries
    }

    private var syncAuditEntries: [AuditTrailEntry] {
        var entries: [AuditTrailEntry] = [
            AuditTrailEntry(
                timestampLabel: "Sync",
                title: "Participant calendars",
                detail: selectedParticipantCount == 0
                    ? "Select calendars to manage mirrored busy holds."
                    : (selectedParticipantCount == 1
                        ? "One calendar is selected. Existing mirrored holds can be cleaned up, but new mirrors require at least two calendars."
                        : "\(selectedParticipantCount) calendars participate in full-mesh busy mirroring."),
                status: selectedParticipantCount == 0 ? "pending" : (selectedParticipantCount == 1 ? "limited" : "ready")
            )
        ]

        if let lastBusyMirrorSyncSummary {
            entries.append(
                AuditTrailEntry(
                    timestampLabel: "Sync",
                    title: "Last reconciliation run",
                    detail: "Created \(lastBusyMirrorSyncSummary.createdCount), updated \(lastBusyMirrorSyncSummary.updatedCount), deleted \(lastBusyMirrorSyncSummary.deletedCount), failed \(lastBusyMirrorSyncSummary.failedCount).",
                    status: lastBusyMirrorSyncSummary.status
                )
            )
        }

        if let syncMessage {
            entries.append(
                AuditTrailEntry(
                    timestampLabel: "Sync",
                    title: "Sync status",
                    detail: syncMessage,
                    status: isSyncInFlight ? "working" : (lastBusyMirrorSyncSummary?.status ?? "pending")
                )
            )
        }

        return entries
    }

    private var googleCalendarAuditEntries: [AuditTrailEntry] {
        var entries: [AuditTrailEntry] = []

        entries.append(
            AuditTrailEntry(
                timestampLabel: "Calendars",
                title: "Writable Google calendars",
                detail: googleStoredAccounts.isEmpty
                    ? "Connect Google to load writable calendars."
                    : "\(googleAccountCards.reduce(0) { $0 + $1.calendars.count }) writable calendars loaded across \(googleStoredAccounts.count) account(s).",
                status: googleStoredAccounts.isEmpty ? "signed-out" : (googleAccountCards.allSatisfy { !$0.calendars.isEmpty } ? "ready" : "pending")
            )
        )

        for card in googleAccountCards {
            if let selectedCalendar = card.selectedCalendar {
                entries.append(
                    AuditTrailEntry(
                        timestampLabel: "Calendars",
                        title: "Selected Google calendar",
                        detail: "\(card.account.displayName) • \(selectedCalendar.displayName)",
                        status: "selected"
                    )
                )
            }

            if let lastManagedGoogleEvent = card.lastManagedEvent {
                entries.append(
                    AuditTrailEntry(
                        timestampLabel: "Write",
                        title: "Managed busy slot created",
                        detail: "\(card.account.displayName) • \(lastManagedGoogleEvent.calendarName) • \(lastManagedGoogleEvent.windowDescription)",
                        status: "created"
                    )
                )
            }

            if let message = card.message {
                entries.append(
                    AuditTrailEntry(
                        timestampLabel: "Write",
                        title: "Google Calendar status",
                        detail: "\(card.account.displayName) • \(message)",
                        status: card.isOperationInFlight ? "working" : "ready"
                    )
                )
            }
        }

        if let status = liveGoogleSmokeStatus.statusLabel, let summary = liveGoogleSmokeStatus.summary {
            entries.append(
                AuditTrailEntry(
                    timestampLabel: "E2E",
                    title: "Live Google smoke",
                    detail: summary,
                    status: status.lowercased()
                )
            )
        }

        return entries
    }

    private var appleCalendarAuditEntries: [AuditTrailEntry] {
        var entries: [AuditTrailEntry] = []

        let status = isAppleCalendarEnabled ? appleConnectionStatusLabel.lowercased() : "signed-out"
        entries.append(
            AuditTrailEntry(
                timestampLabel: "Apple",
                title: isAppleCalendarEnabled ? "Apple calendar status" : "Apple calendar disconnected",
                detail: appleConnectionDetail,
                status: status
            )
        )

        entries.append(
            AuditTrailEntry(
                timestampLabel: "Calendars",
                title: "Writable Apple calendars",
                detail: isAppleCalendarEnabled
                    ? "\(appleCalendars.count) writable Apple calendars loaded."
                    : "Connect Apple Calendar to load writable Apple or iCloud calendars.",
                status: isAppleCalendarEnabled ? (appleCalendars.isEmpty ? "pending" : "ready") : "signed-out"
            )
        )

        if let selectedAppleCalendar {
            entries.append(
                AuditTrailEntry(
                    timestampLabel: "Calendars",
                    title: "Selected Apple calendar",
                    detail: selectedAppleCalendar.displayName,
                    status: "selected"
                )
            )
        }

        if let lastManagedAppleEvent {
            entries.append(
                AuditTrailEntry(
                    timestampLabel: "Write",
                    title: "Managed Apple busy slot created",
                    detail: "\(lastManagedAppleEvent.calendarName) • \(lastManagedAppleEvent.windowDescription)",
                    status: "created"
                )
            )
        }

        if let message = appleCalendarMessage {
            entries.append(
                AuditTrailEntry(
                    timestampLabel: "Write",
                    title: "Apple Calendar status",
                    detail: message,
                    status: isAppleCalendarOperationInFlight ? "working" : "ready"
                )
            )
        }

        return entries
    }

    private static func loadPollInterval(from userDefaults: UserDefaults) -> Int {
        let storedValue = userDefaults.integer(forKey: SettingKey.pollIntervalMinutes)
        if storedValue == 0 {
            return AppSettingsDefaults.pollIntervalMinutes
        }
        return max(1, min(60, storedValue))
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

    private static let syncTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d, HH:mm:ss"
        return formatter
    }()
}

private struct SyncParticipantsBundle {
    let participants: [BusyMirrorParticipant]
    let googleAccountsByID: [String: GoogleAuthorizedAccount]
    let googleCalendarsByAccountID: [String: GoogleCalendarSummary]
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

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
