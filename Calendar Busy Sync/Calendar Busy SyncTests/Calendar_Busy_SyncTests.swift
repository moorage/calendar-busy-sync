import XCTest
@testable import Calendar_Busy_Sync

final class Calendar_Busy_SyncTests: XCTestCase {
    func testPlatformDefaultsUseMacUnlimitedAuditTrailAndTwoMinutePolling() {
        XCTAssertEqual(AppSettingsDefaults.pollIntervalMinutes, 2)
        XCTAssertEqual(AuditTrailLogLength.defaultValue(for: .macos), .unlimited)
        XCTAssertEqual(AuditTrailLogLength.defaultValue(for: .ios), .last1000)
    }

    func testLaunchOptionsParseScenarioArguments() {
        let stateURL = URL(fileURLWithPath: "/tmp/state.json")
        let perfURL = URL(fileURLWithPath: "/tmp/perf.json")
        let screenshotURL = URL(fileURLWithPath: "/tmp/window.png")

        let options = HarnessLaunchOptions.fromProcess(arguments: [
            "App",
            "--scenario-root", "/tmp/scenarios",
            "--scenario", "basic-cross-busy.json",
            "--window-size", "900x700",
            "--dump-visible-state", stateURL.path,
            "--dump-perf-state", perfURL.path,
            "--screenshot-path", screenshotURL.path,
            "--harness-command-dir", "/tmp/commands",
            "--platform-target", "ios",
            "--device-class", "ipad",
            "--ui-test-mode", "1",
        ])

        XCTAssertEqual(options.scenarioRoot?.path, "/tmp/scenarios")
        XCTAssertEqual(options.scenarioName, "basic-cross-busy.json")
        XCTAssertEqual(options.windowSize?.width, 900)
        XCTAssertEqual(options.windowSize?.height, 700)
        XCTAssertEqual(options.dumpVisibleStateURL, stateURL)
        XCTAssertEqual(options.dumpPerfStateURL, perfURL)
        XCTAssertEqual(options.screenshotPathURL, screenshotURL)
        XCTAssertEqual(options.commandDirectoryURL?.path, "/tmp/commands")
        XCTAssertEqual(options.platformTarget, .ios)
        XCTAssertEqual(options.deviceClass, .ipad)
        XCTAssertTrue(options.uiTestMode)
    }

    func testScenarioStateBuildsMirrorPreviewOnlyForBusyEvents() throws {
        let scenario = BusySyncScenario(
            scenarioName: "unit-test",
            accounts: [
                ConnectedAccountScenario(
                    id: "a",
                    provider: "google",
                    displayName: "Account A",
                    selectedCalendars: [
                        SelectedCalendar(id: "source", name: "Source", role: .sourceAndDestination),
                        SelectedCalendar(id: "dest1", name: "Destination 1", role: .destination),
                    ]
                ),
                ConnectedAccountScenario(
                    id: "b",
                    provider: "google",
                    displayName: "Account B",
                    selectedCalendars: [
                        SelectedCalendar(id: "dest2", name: "Destination 2", role: .destination),
                    ]
                ),
            ],
            sourceEvents: [
                SourceEventScenario(
                    calendarId: "source",
                    eventId: "evt-1",
                    title: "Busy event",
                    availability: "busy",
                    start: "2026-04-21T10:00:00-07:00",
                    end: "2026-04-21T11:00:00-07:00"
                ),
                SourceEventScenario(
                    calendarId: "source",
                    eventId: "evt-2",
                    title: "Free event",
                    availability: "free",
                    start: "2026-04-21T12:00:00-07:00",
                    end: "2026-04-21T13:00:00-07:00"
                ),
            ],
            expectedMirrorPreview: []
        )

        let state = ScenarioState.build(from: scenario)

        XCTAssertEqual(state.connectedAccountCount, 2)
        XCTAssertEqual(state.selectedCalendarCount, 3)
        XCTAssertEqual(state.mirrorPreview.count, 2)
        XCTAssertEqual(
            state.mirrorPreview,
            [
                MirrorPreviewEntry(sourceCalendar: "Source", targetCalendar: "Destination 1", availability: "busy"),
                MirrorPreviewEntry(sourceCalendar: "Source", targetCalendar: "Destination 2", availability: "busy"),
            ]
        )
    }

    func testIntegrationScenarioLoadsAndSnapshotMatches() throws {
        let state = try ScenarioLoader().load(
            rootURL: repoRootURL().appendingPathComponent("Fixtures/scenarios", isDirectory: true),
            scenarioName: "basic-cross-busy.json"
        )

        XCTAssertEqual(state.scenario.scenarioName, "basic-cross-busy")
        XCTAssertEqual(state.connectedAccountCount, 2)
        XCTAssertEqual(state.selectedCalendarCount, 4)
        XCTAssertEqual(state.pendingWriteCount, 3)
        XCTAssertEqual(state.failedWriteCount, 0)
        XCTAssertEqual(state.mirrorPreview, state.scenario.expectedMirrorPreview)
    }

    @MainActor
    func testAppModelFallsBackToEmptyLiveShellWhenNoScenarioArgumentsAreProvided() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let model = AppModel(
            launchOptions: HarnessLaunchOptions(
                scenarioRoot: nil,
                scenarioName: nil,
                windowSize: nil,
                dumpVisibleStateURL: nil,
                dumpPerfStateURL: nil,
                screenshotPathURL: nil,
                commandDirectoryURL: nil,
                uiTestMode: false,
                platformTarget: .macos,
                deviceClass: .mac
            ),
            userDefaults: defaults
        )

        await model.prepareIfNeeded()

        XCTAssertNil(model.lastErrorMessage)
        XCTAssertEqual(model.state, .emptyLiveShell)
        XCTAssertEqual(model.state?.connectedAccountCount, 0)
        XCTAssertEqual(model.googleCalendarStatusLabel, "Sign in required")
    }

    func testAuditTrailIncludesCustomGoogleOAuthModeEntry() throws {
        let state = try ScenarioLoader().load(
            rootURL: repoRootURL().appendingPathComponent("Fixtures/scenarios", isDirectory: true),
            scenarioName: "basic-cross-busy.json"
        )

        let entries = AuditTrailBuilder.entries(
            for: state,
            platform: .macos,
            pollIntervalMinutes: 2,
            auditTrailLogLength: .unlimited,
            googleOAuth: GoogleOAuthOverrideConfiguration(
                usesCustomApp: true,
                clientID: "custom-client-id",
                serverClientID: "custom-server-id"
            )
        )

        XCTAssertTrue(entries.contains(where: {
            $0.title == "Google OAuth provider mode" && $0.status == "custom"
        }))
        XCTAssertTrue(entries.contains(where: {
            $0.title == "Polling interval configured" && $0.detail.contains("2 minutes")
        }))
    }

    func testGoogleOAuthResolverRejectsMismatchedCustomNativeClientID() {
        let defaultConfiguration = DefaultGoogleOAuthConfiguration(
            clientID: "551260352529-b8bfn0u4c9tnj2lfg99so0njk93j26th.apps.googleusercontent.com",
            reversedClientID: "com.googleusercontent.apps.551260352529-b8bfn0u4c9tnj2lfg99so0njk93j26th",
            serverClientID: nil
        )

        let resolution = GoogleOAuthConfigurationResolver.resolve(
            defaultConfiguration: defaultConfiguration,
            overrideConfiguration: GoogleOAuthOverrideConfiguration(
                usesCustomApp: true,
                clientID: "different-client.apps.googleusercontent.com",
                serverClientID: "server-client.apps.googleusercontent.com"
            )
        )

        guard case let .invalid(message) = resolution else {
            return XCTFail("expected the mismatched custom native client ID to be rejected")
        }

        XCTAssertTrue(message.contains("requires rebuilding the app"))
    }

    func testGoogleOAuthResolverAllowsCustomServerClientOnBundledNativeClientID() {
        let defaultConfiguration = DefaultGoogleOAuthConfiguration(
            clientID: "551260352529-b8bfn0u4c9tnj2lfg99so0njk93j26th.apps.googleusercontent.com",
            reversedClientID: "com.googleusercontent.apps.551260352529-b8bfn0u4c9tnj2lfg99so0njk93j26th",
            serverClientID: nil
        )

        let resolution = GoogleOAuthConfigurationResolver.resolve(
            defaultConfiguration: defaultConfiguration,
            overrideConfiguration: GoogleOAuthOverrideConfiguration(
                usesCustomApp: true,
                clientID: defaultConfiguration.clientID,
                serverClientID: "server-client.apps.googleusercontent.com"
            )
        )

        guard case let .valid(configuration) = resolution else {
            return XCTFail("expected matching native client ID to be accepted")
        }

        XCTAssertTrue(configuration.usesCustomApp)
        XCTAssertEqual(configuration.serverClientID, "server-client.apps.googleusercontent.com")
    }

    func testGoogleCalendarSelectionResolverPrefersPersistedCalendarThenNamedCalendarThenPrimary() {
        let primary = GoogleCalendarSummary(
            id: "primary",
            summary: "Primary Calendar",
            accessRole: .owner,
            primary: true,
            timeZone: "America/Los_Angeles"
        )
        let work = GoogleCalendarSummary(
            id: "work",
            summary: "Work",
            accessRole: .writer,
            primary: false,
            timeZone: "America/Los_Angeles"
        )

        XCTAssertEqual(
            GoogleCalendarSelectionResolver.resolvedCalendarID(
                availableCalendars: [primary, work],
                persistedCalendarID: "work",
                preferredCalendarName: "Primary Calendar"
            ),
            "work"
        )

        XCTAssertEqual(
            GoogleCalendarSelectionResolver.resolvedCalendarID(
                availableCalendars: [primary, work],
                persistedCalendarID: "missing",
                preferredCalendarName: "work"
            ),
            "work"
        )

        XCTAssertEqual(
            GoogleCalendarSelectionResolver.resolvedCalendarID(
                availableCalendars: [primary, work],
                persistedCalendarID: "missing",
                preferredCalendarName: nil
            ),
            "primary"
        )
    }

    func testGoogleCalendarSummaryDecodesPrimaryWritableCalendar() throws {
        let data = """
        {
          "id": "team-calendar@group.calendar.google.com",
          "summary": "Team Calendar",
          "accessRole": "writer",
          "primary": true,
          "timeZone": "America/Los_Angeles"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(GoogleCalendarSummary.self, from: data)

        XCTAssertEqual(decoded.id, "team-calendar@group.calendar.google.com")
        XCTAssertEqual(decoded.summary, "Team Calendar")
        XCTAssertEqual(decoded.accessRole, .writer)
        XCTAssertTrue(decoded.isPrimary)
        XCTAssertEqual(decoded.displayName, "Team Calendar (Primary)")
    }

    func testAppleCalendarSelectionResolverPrefersPersistedCalendarThenICloudThenFirst() {
        let iCloud = AppleCalendarSummary(
            id: "icloud",
            title: "Busy Mirror",
            sourceTitle: "iCloud",
            sourceKind: .iCloud
        )
        let local = AppleCalendarSummary(
            id: "local",
            title: "Local",
            sourceTitle: "On My Mac",
            sourceKind: .local
        )

        XCTAssertEqual(
            AppleCalendarSelectionResolver.resolvedCalendarID(
                availableCalendars: [iCloud, local],
                persistedCalendarID: "local"
            ),
            "local"
        )

        XCTAssertEqual(
            AppleCalendarSelectionResolver.resolvedCalendarID(
                availableCalendars: [local, iCloud],
                persistedCalendarID: "missing"
            ),
            "icloud"
        )

        XCTAssertEqual(
            AppleCalendarSelectionResolver.resolvedCalendarID(
                availableCalendars: [local],
                persistedCalendarID: "missing"
            ),
            "local"
        )
    }

    @MainActor
    func testAppModelAppleCalendarConnectionLoadsCalendarsAndManagedEventLifecycle() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let iCloud = AppleCalendarSummary(
            id: "icloud",
            title: "Busy Mirror",
            sourceTitle: "iCloud",
            sourceKind: .iCloud
        )
        let work = AppleCalendarSummary(
            id: "work",
            title: "Work",
            sourceTitle: "On My Mac",
            sourceKind: .local
        )
        let createdEvent = AppleManagedEventRecord(
            calendarID: iCloud.id,
            calendarName: iCloud.displayName,
            eventID: "apple-event-1",
            summary: "Busy",
            windowDescription: "Apr 19, 10:00 PDT - Apr 19, 10:30 PDT"
        )
        let appleService = MockAppleCalendarService(
            authorizationState: .notDetermined,
            calendars: [iCloud, work],
            createdEvent: createdEvent
        )

        let model = AppModel(
            launchOptions: HarnessLaunchOptions(
                scenarioRoot: nil,
                scenarioName: nil,
                windowSize: nil,
                dumpVisibleStateURL: nil,
                dumpPerfStateURL: nil,
                screenshotPathURL: nil,
                commandDirectoryURL: nil,
                uiTestMode: false,
                platformTarget: .macos,
                deviceClass: .mac
            ),
            userDefaults: defaults,
            appleCalendarService: appleService
        )

        await model.prepareIfNeeded()
        XCTAssertEqual(model.appleConnectionStatusLabel, "Not connected")

        await model.connectAppleCalendar()

        XCTAssertTrue(model.isAppleCalendarEnabled)
        XCTAssertEqual(model.appleCalendarAuthorizationState, .granted)
        XCTAssertEqual(model.appleCalendars, [iCloud, work])
        XCTAssertEqual(model.selectedAppleCalendarID, "icloud")
        XCTAssertTrue(appleService.didRequestAccess)
        XCTAssertEqual(model.appleCalendarStatusLabel, "Ready")

        await model.createManagedAppleEvent()
        XCTAssertEqual(model.lastManagedAppleEvent, createdEvent)

        await model.deleteManagedAppleEvent()
        XCTAssertNil(model.lastManagedAppleEvent)
        XCTAssertEqual(appleService.deletedEventIDs, ["apple-event-1"])

        model.disconnectAppleCalendar()
        XCTAssertFalse(model.isAppleCalendarEnabled)
        XCTAssertEqual(model.selectedAppleCalendarID, "")
    }

    @MainActor
    func testAppModelAppleCalendarDeniedAccessSurfacesSettingsGuidance() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let appleService = MockAppleCalendarService(
            authorizationState: .denied,
            calendars: [],
            createdEvent: nil,
            requestAccessError: AppleCalendarServiceError.accessDenied
        )

        let model = AppModel(
            launchOptions: HarnessLaunchOptions(
                scenarioRoot: nil,
                scenarioName: nil,
                windowSize: nil,
                dumpVisibleStateURL: nil,
                dumpPerfStateURL: nil,
                screenshotPathURL: nil,
                commandDirectoryURL: nil,
                uiTestMode: false,
                platformTarget: .ios,
                deviceClass: .iphone
            ),
            userDefaults: defaults,
            appleCalendarService: appleService
        )

        await model.prepareIfNeeded()
        await model.connectAppleCalendar()

        XCTAssertTrue(model.isAppleCalendarEnabled)
        XCTAssertEqual(model.appleConnectionStatusLabel, "Permission denied")
        XCTAssertEqual(model.appleCalendarStatusLabel, "Permission denied")
        XCTAssertTrue(model.appleCalendarMessage?.contains("System Settings") == true)
    }

    private func repoRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

@MainActor
private final class MockAppleCalendarService: AppleCalendarProviding {
    var authorizationStateValue: AppleCalendarAuthorizationState
    var calendars: [AppleCalendarSummary]
    var createdEvent: AppleManagedEventRecord?
    var requestAccessError: Error?
    var didRequestAccess = false
    var deletedEventIDs: [String] = []

    init(
        authorizationState: AppleCalendarAuthorizationState,
        calendars: [AppleCalendarSummary],
        createdEvent: AppleManagedEventRecord?,
        requestAccessError: Error? = nil
    ) {
        self.authorizationStateValue = authorizationState
        self.calendars = calendars
        self.createdEvent = createdEvent
        self.requestAccessError = requestAccessError
    }

    func authorizationState() -> AppleCalendarAuthorizationState {
        authorizationStateValue
    }

    func requestAccessIfNeeded() async throws -> AppleCalendarAuthorizationState {
        didRequestAccess = true

        if let requestAccessError {
            throw requestAccessError
        }

        authorizationStateValue = .granted
        return .granted
    }

    func listWritableCalendars() throws -> [AppleCalendarSummary] {
        calendars
    }

    func createManagedBusyEvent(in calendar: AppleCalendarSummary) throws -> AppleManagedEventRecord {
        guard let createdEvent else {
            throw AppleCalendarServiceError.requestFailed("missing created event")
        }

        return createdEvent
    }

    func deleteManagedBusyEvent(_ event: AppleManagedEventRecord) throws {
        deletedEventIDs.append(event.eventID)
    }
}
