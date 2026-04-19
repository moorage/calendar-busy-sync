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
    @Published private(set) var googleConnectedAccount: GoogleConnectedAccount?
    @Published private(set) var googleAuthMessage: String?
    @Published private(set) var isGoogleAuthInFlight = false
    @Published private(set) var googleCalendars: [GoogleCalendarSummary] = []
    @Published private(set) var googleCalendarMessage: String?
    @Published private(set) var lastManagedGoogleEvent: GoogleManagedEventRecord?
    @Published private(set) var isGoogleCalendarOperationInFlight = false
    @Published private(set) var liveGoogleSmokeStatus: LiveGoogleSmokeStatus = .idle
    @Published var pollIntervalMinutes: Int {
        didSet { persistSettings() }
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
        didSet { persistSettings() }
    }
    @Published var selectedGoogleCalendarID: String {
        didSet { persistSettings() }
    }

    let launchOptions: HarnessLaunchOptions

    private let loader: ScenarioLoader
    private let fileManager: FileManager
    private let launchDate: Date
    private let userDefaults: UserDefaults
    private let appleCalendarService: any AppleCalendarProviding
    private let googleCalendarService: GoogleCalendarService
    private let liveGoogleDebugConfiguration: LiveGoogleDebugConfiguration
    private var hasPrepared = false
    private var hasAttemptedLiveGoogleSmoke = false

    private enum SettingKey {
        static let pollIntervalMinutes = "settings.pollIntervalMinutes"
        static let auditTrailLogLength = "settings.auditTrailLogLength"
        static let usesAppleCalendar = "settings.appleCalendar.enabled"
        static let selectedAppleCalendarID = "settings.appleCalendar.selectedCalendarID"
        static let usesCustomGoogleOAuthApp = "settings.googleOAuth.usesCustomApp"
        static let customGoogleOAuthClientID = "settings.googleOAuth.clientID"
        static let customGoogleOAuthServerClientID = "settings.googleOAuth.serverClientID"
        static let selectedGoogleCalendarID = "settings.googleCalendar.selectedCalendarID"
    }

    init(
        launchOptions: HarnessLaunchOptions,
        fileManager: FileManager = .default,
        launchDate: Date = Date(),
        userDefaults: UserDefaults = .standard,
        processInfo: ProcessInfo = .processInfo,
        appleCalendarService: (any AppleCalendarProviding)? = nil,
        googleCalendarService: GoogleCalendarService? = nil
    ) {
        self.launchOptions = launchOptions
        self.loader = ScenarioLoader()
        self.fileManager = fileManager
        self.launchDate = launchDate
        self.userDefaults = userDefaults
        let resolvedAppleCalendarService = appleCalendarService ?? AppleCalendarService()
        self.appleCalendarService = resolvedAppleCalendarService
        self.googleCalendarService = googleCalendarService ?? GoogleCalendarService()
        self.liveGoogleDebugConfiguration = LiveGoogleDebugConfiguration.from(processInfo: processInfo)
        self.pollIntervalMinutes = Self.loadPollInterval(from: userDefaults)
        self.auditTrailLogLength = Self.loadAuditTrailLogLength(from: userDefaults, platform: launchOptions.platformTarget)
        self.isAppleCalendarEnabled = userDefaults.object(forKey: SettingKey.usesAppleCalendar) as? Bool ?? false
        self.selectedAppleCalendarID = userDefaults.string(forKey: SettingKey.selectedAppleCalendarID) ?? ""
        self.appleCalendarAuthorizationState = resolvedAppleCalendarService.authorizationState()
        self.usesCustomGoogleOAuthApp = userDefaults.object(forKey: SettingKey.usesCustomGoogleOAuthApp) as? Bool ?? false
        self.customGoogleOAuthClientID = userDefaults.string(forKey: SettingKey.customGoogleOAuthClientID) ?? ""
        self.customGoogleOAuthServerClientID = userDefaults.string(forKey: SettingKey.customGoogleOAuthServerClientID) ?? ""
        self.selectedGoogleCalendarID = userDefaults.string(forKey: SettingKey.selectedGoogleCalendarID) ?? ""
        if liveGoogleDebugConfiguration.isEnabled {
            self.liveGoogleSmokeStatus = .awaitingAuthentication
        }
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
        await restoreGoogleSignInIfPossible()
    }

    var supportsPollingSettings: Bool {
        launchOptions.platformTarget == .macos
    }

    var googleOAuthConfiguration: GoogleOAuthOverrideConfiguration {
        GoogleOAuthOverrideConfiguration(
            usesCustomApp: usesCustomGoogleOAuthApp,
            clientID: customGoogleOAuthClientID,
            serverClientID: customGoogleOAuthServerClientID
        )
    }

    var appleConnectButtonTitle: String {
        isAppleCalendarEnabled ? "Reconnect Apple Calendar" : "Connect Apple Calendar"
    }

    var selectedAppleCalendar: AppleCalendarSummary? {
        appleCalendars.first(where: { $0.id == selectedAppleCalendarID })
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

    var googleConnectionStatusLabel: String {
        if isGoogleAuthInFlight {
            return googleConnectedAccount == nil ? "Connecting…" : "Updating…"
        }

        if googleConnectedAccount != nil {
            return "Connected"
        }

        return "Not connected"
    }

    var googleConnectionDetail: String {
        if let account = googleConnectedAccount {
            let scopeCount = account.grantedScopes.count
            let scopeSummary = scopeCount == 1 ? "1 Google scope granted." : "\(scopeCount) Google scopes granted."

            if account.serverAuthCodeAvailable {
                return "\(account.email) • \(scopeSummary) Server auth code captured for backend exchange."
            }

            return "\(account.email) • \(scopeSummary)"
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
        !isGoogleAuthInFlight && googleOAuthResolutionMessage == nil
    }

    var googleConnectButtonTitle: String {
        googleConnectedAccount == nil ? "Connect Google" : "Reconnect Google"
    }

    var selectedGoogleCalendar: GoogleCalendarSummary? {
        googleCalendars.first(where: { $0.id == selectedGoogleCalendarID })
    }

    var googleCalendarStatusLabel: String {
        if isGoogleCalendarOperationInFlight {
            return "Working…"
        }

        if googleConnectedAccount == nil {
            return "Sign in required"
        }

        if googleCalendars.isEmpty {
            return "No calendars loaded"
        }

        if selectedGoogleCalendar == nil {
            return "Select a calendar"
        }

        return "Ready"
    }

    var googleCalendarDetail: String {
        if googleConnectedAccount == nil {
            return "Connect Google to load writable calendars from the signed-in account."
        }

        if let selectedGoogleCalendar {
            return "Busy slots will be written to \(selectedGoogleCalendar.displayName)."
        }

        if googleCalendars.isEmpty {
            return "No writable Google calendars are loaded yet."
        }

        return "Select which writable Google calendar should receive busy slots."
    }

    var canRefreshGoogleCalendars: Bool {
        googleConnectedAccount != nil && !isGoogleAuthInFlight && !isGoogleCalendarOperationInFlight
    }

    var canCreateManagedBusyEvent: Bool {
        selectedGoogleCalendar != nil && !isGoogleCalendarOperationInFlight
    }

    var canDeleteManagedBusyEvent: Bool {
        lastManagedGoogleEvent != nil && !isGoogleCalendarOperationInFlight
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

        isAppleCalendarEnabled = false
        clearAppleCalendarState()
        appleCalendarMessage = "Apple Calendar was disconnected for this app. System calendar permission remains managed in Settings."
        refreshAppleCalendarAuthorizationState()
        persistSettings()
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
            selectedAppleCalendarID = AppleCalendarSelectionResolver.resolvedCalendarID(
                availableCalendars: calendars,
                persistedCalendarID: selectedAppleCalendarID
            )
            if let selectedAppleCalendar {
                appleCalendarMessage = "Loaded \(calendars.count) writable Apple calendars. Selected \(selectedAppleCalendar.displayName)."
            } else {
                appleCalendarMessage = "No writable Apple calendars were found on this device."
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

    func connectGoogleAccount() async {
        guard !isGoogleAuthInFlight else { return }
        isGoogleAuthInFlight = true
        googleAuthMessage = nil

        defer {
            isGoogleAuthInFlight = false
        }

        do {
            let connectedAccount = try await GoogleSignInService.signIn(using: googleOAuthResolution)
            googleConnectedAccount = connectedAccount
            googleAuthMessage = connectedAccount.serverAuthCodeAvailable
                ? "Google authorization succeeded. A server auth code was issued for backend exchange."
                : "Google authorization succeeded."
            await refreshGoogleCalendars()
        } catch let error as GoogleSignInServiceError {
            googleAuthMessage = error.localizedDescription
        } catch {
            googleAuthMessage = "Google authorization did not complete: \(error.localizedDescription)"
        }
    }

    func disconnectGoogleAccount() async {
        guard !isGoogleAuthInFlight else { return }
        isGoogleAuthInFlight = true
        googleAuthMessage = nil

        defer {
            isGoogleAuthInFlight = false
        }

        do {
            try await GoogleSignInService.disconnectCurrentUser()
            googleConnectedAccount = nil
            googleAuthMessage = "Google access was disconnected for this device."
            clearLiveGoogleState()
        } catch {
            googleAuthMessage = "Google access could not be disconnected. Try again from the current app window."
        }
    }

    func refreshGoogleCalendars() async {
        guard googleConnectedAccount != nil else {
            googleCalendarMessage = "Connect Google before loading calendars."
            return
        }
        guard !isGoogleCalendarOperationInFlight else { return }

        isGoogleCalendarOperationInFlight = true
        defer {
            isGoogleCalendarOperationInFlight = false
        }

        do {
            let calendars = try await googleCalendarService.listWritableCalendars()
            googleCalendars = calendars
            selectedGoogleCalendarID = GoogleCalendarSelectionResolver.resolvedCalendarID(
                availableCalendars: calendars,
                persistedCalendarID: selectedGoogleCalendarID,
                preferredCalendarName: liveGoogleDebugConfiguration.preferredCalendarName
            )
            if let selectedGoogleCalendar {
                googleCalendarMessage = "Loaded \(calendars.count) writable Google calendars. Selected \(selectedGoogleCalendar.displayName)."
            } else {
                googleCalendarMessage = "No writable Google calendars were found for this account."
            }
        } catch let error as GoogleCalendarServiceError {
            googleCalendarMessage = error.localizedDescription
        } catch {
            googleCalendarMessage = "Google calendars could not be loaded."
        }

        await runLiveGoogleSmokeIfNeeded()
    }

    func createManagedBusyEvent() async {
        guard let calendar = selectedGoogleCalendar else {
            googleCalendarMessage = "Select a writable Google calendar before creating a managed busy slot."
            return
        }

        await performGoogleCalendarOperation { [self] in
            let event = try await self.googleCalendarService.createManagedBusyEvent(in: calendar)
            self.lastManagedGoogleEvent = event
            self.googleCalendarMessage = "Created a managed busy slot in \(calendar.displayName) for \(event.windowDescription)."
        }
    }

    func deleteManagedBusyEvent() async {
        guard let event = lastManagedGoogleEvent else {
            googleCalendarMessage = "There is no managed busy slot to delete yet."
            return
        }

        await performGoogleCalendarOperation { [self] in
            try await self.googleCalendarService.deleteManagedBusyEvent(event)
            self.lastManagedGoogleEvent = nil
            self.googleCalendarMessage = "Deleted the managed busy slot from \(event.calendarName)."
        }
    }

    private func performGoogleCalendarOperation(
        _ operation: @escaping () async throws -> Void
    ) async {
        guard !isGoogleCalendarOperationInFlight else { return }
        isGoogleCalendarOperationInFlight = true

        defer {
            isGoogleCalendarOperationInFlight = false
        }

        do {
            try await operation()
        } catch let error as GoogleCalendarServiceError {
            googleCalendarMessage = error.localizedDescription
        } catch {
            googleCalendarMessage = "Google Calendar request failed. Try again from the current app window."
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
        userDefaults.set(selectedGoogleCalendarID, forKey: SettingKey.selectedGoogleCalendarID)
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

    private func restoreGoogleSignInIfPossible() async {
        guard case .valid = googleOAuthResolution else {
            return
        }

        do {
            googleConnectedAccount = try await GoogleSignInService.restorePreviousSignIn(using: googleOAuthResolution)
            if googleConnectedAccount != nil {
                await refreshGoogleCalendars()
            }
        } catch {
            googleConnectedAccount = nil
            googleAuthMessage = "A stored Google session could not be restored. Connect Google again if you want live calendar access."
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
        googleCalendars = []
        selectedGoogleCalendarID = ""
        lastManagedGoogleEvent = nil
        googleCalendarMessage = nil
        hasAttemptedLiveGoogleSmoke = false
        liveGoogleSmokeStatus = liveGoogleDebugConfiguration.isEnabled ? .awaitingAuthentication : .idle
    }

    private func runLiveGoogleSmokeIfNeeded() async {
        guard liveGoogleDebugConfiguration.isEnabled, !hasAttemptedLiveGoogleSmoke else {
            return
        }

        guard googleConnectedAccount != nil else {
            liveGoogleSmokeStatus = .awaitingAuthentication
            return
        }

        hasAttemptedLiveGoogleSmoke = true

        let targetCalendar = selectedGoogleCalendarForLiveSmoke()
        guard let targetCalendar else {
            let calendarName = liveGoogleDebugConfiguration.preferredCalendarName ?? "(missing target calendar)"
            let message = "Live verification could not find a writable calendar named \(calendarName)."
            liveGoogleSmokeStatus = .failed(message)
            googleCalendarMessage = message
            return
        }

        selectedGoogleCalendarID = targetCalendar.id
        isGoogleCalendarOperationInFlight = true
        liveGoogleSmokeStatus = .running("Creating a managed busy slot in \(targetCalendar.displayName)…")

        do {
            let event = try await googleCalendarService.createManagedBusyEvent(in: targetCalendar)
            lastManagedGoogleEvent = event
            liveGoogleSmokeStatus = .running("Deleting the managed busy slot from \(targetCalendar.displayName)…")
            try await googleCalendarService.deleteManagedBusyEvent(event)
            lastManagedGoogleEvent = nil
            let message = "Created and deleted a managed busy slot in \(targetCalendar.displayName)."
            googleCalendarMessage = message
            liveGoogleSmokeStatus = .passed(message)
        } catch let error as GoogleCalendarServiceError {
            let message = error.localizedDescription
            googleCalendarMessage = message
            liveGoogleSmokeStatus = .failed(message)
        } catch {
            let message = "Live Google verification failed before the busy slot round-trip completed."
            googleCalendarMessage = message
            liveGoogleSmokeStatus = .failed(message)
        }

        isGoogleCalendarOperationInFlight = false
    }

    private func selectedGoogleCalendarForLiveSmoke() -> GoogleCalendarSummary? {
        if let preferredCalendarName = liveGoogleDebugConfiguration.preferredCalendarName {
            return googleCalendars.first(where: { $0.matches(name: preferredCalendarName) })
        }

        return selectedGoogleCalendar
    }

    private var googleAuditEntries: [AuditTrailEntry] {
        var entries: [AuditTrailEntry] = []

        entries.append(
            AuditTrailEntry(
                timestampLabel: "Google",
                title: googleConnectedAccount == nil ? "Google account status" : "Google account connected",
                detail: googleConnectedAccount?.email ?? "No Google account is currently connected.",
                status: googleConnectedAccount == nil ? "signed-out" : "connected"
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
                    status: googleConnectedAccount == nil ? "pending" : "ready"
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
                detail: googleConnectedAccount == nil
                    ? "Connect Google to load writable calendars."
                    : "\(googleCalendars.count) writable calendars loaded.",
                status: googleConnectedAccount == nil ? "signed-out" : (googleCalendars.isEmpty ? "pending" : "ready")
            )
        )

        if let selectedGoogleCalendar {
            entries.append(
                AuditTrailEntry(
                    timestampLabel: "Calendars",
                    title: "Selected Google calendar",
                    detail: selectedGoogleCalendar.displayName,
                    status: "selected"
                )
            )
        }

        if let lastManagedGoogleEvent {
            entries.append(
                AuditTrailEntry(
                    timestampLabel: "Write",
                    title: "Managed busy slot created",
                    detail: "\(lastManagedGoogleEvent.calendarName) • \(lastManagedGoogleEvent.windowDescription)",
                    status: "created"
                )
            )
        }

        if let message = googleCalendarMessage {
            entries.append(
                AuditTrailEntry(
                    timestampLabel: "Write",
                    title: "Google Calendar status",
                    detail: message,
                    status: isGoogleCalendarOperationInFlight ? "working" : "ready"
                )
            )
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
}

private struct LiveGoogleDebugConfiguration {
    let isEnabled: Bool
    let preferredCalendarName: String?

    static func from(processInfo: ProcessInfo) -> LiveGoogleDebugConfiguration {
        let environment = processInfo.environment
        let enabled = environment["CALENDAR_BUSY_SYNC_LIVE_E2E"] == "1"
        let preferredCalendarName = environment["CALENDAR_BUSY_SYNC_E2E_CALENDAR_NAME"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty

        return LiveGoogleDebugConfiguration(
            isEnabled: enabled,
            preferredCalendarName: preferredCalendarName
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
