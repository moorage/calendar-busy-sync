import XCTest
@testable import Calendar_Busy_Sync

#if os(macOS)
import EventKit
import ServiceManagement
#endif

final class Calendar_Busy_SyncTests: XCTestCase {
    func testPlatformDefaultsUseMacUnlimitedAuditTrailAndTwoMinutePolling() {
        XCTAssertEqual(AppSettingsDefaults.pollIntervalMinutes, 2)
        XCTAssertEqual(AuditTrailLogLength.defaultValue(for: .macos), .unlimited)
        XCTAssertEqual(AuditTrailLogLength.defaultValue(for: .ios), .last1000)
    }

    func testAppleManagedMirrorMarkerRoundTripsURLToken() {
        let marker = AppleManagedMirrorMarker(token: "mirror-token")

        XCTAssertEqual(marker.url.absoluteString, "calendarbusysync://mirror/mirror-token")
        XCTAssertEqual(AppleManagedMirrorMarker(url: marker.url)?.token, "mirror-token")
        XCTAssertNil(AppleManagedMirrorMarker(url: URL(string: "https://example.com")))
    }

    func testAppleMirrorIdentityStorePersistsAndRemovesSourceKeys() throws {
        let suiteName = "CalendarBusySyncTests.\(#function)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create isolated UserDefaults suite for Apple mirror metadata tests.")
        }
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let store = AppleMirrorIdentityStore(
            userDefaults: userDefaults,
            storageKey: "apple-mirror-test-store"
        )
        let sourceKey = BusyMirrorSourceKey(
            provider: .google,
            calendarID: "calendar-id",
            eventID: "event-id"
        )

        XCTAssertNil(try store.sourceKey(for: "mirror-token"))

        try store.setSourceKey(sourceKey, for: "mirror-token")

        XCTAssertEqual(try store.sourceKey(for: "mirror-token"), sourceKey)

        try store.removeSourceKey(for: "mirror-token")

        XCTAssertNil(try store.sourceKey(for: "mirror-token"))
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
            userDefaults: defaults,
            googleAccountStore: MockGoogleAccountStore()
        )

        await model.prepareIfNeeded()

        XCTAssertNil(model.lastErrorMessage)
        XCTAssertEqual(model.state, .emptyLiveShell)
        XCTAssertEqual(model.state?.connectedAccountCount, 0)
        XCTAssertEqual(model.googleCalendarStatusLabel, "Sign in required")
    }

    @MainActor
    func testAppModelBlocksMacGoogleSignInWhenBuildIsUnsigned() async {
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
            userDefaults: defaults,
            googleAccountStore: MockGoogleAccountStore(),
            googleSignInEnvironment: GoogleSignInEnvironment(
                blockingReason: "Google Sign-In on macOS requires a signed app build."
            )
        )

        await model.prepareIfNeeded()

        XCTAssertEqual(model.googleConnectionStatusLabel, "Signed build required")
        XCTAssertEqual(model.googleConnectionDetail, "Google Sign-In on macOS requires a signed app build.")
        XCTAssertFalse(model.canStartGoogleSignIn)
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

    @MainActor
    func testMacUtilityShellModelUsesFilledMenuBarIconWhenSettingsWindowIsOpen() {
        let shellModel = MacUtilityShellModel(
            launchAtLoginService: MockLaunchAtLoginService(status: .notRegistered)
        )
        retainForHostedXCTest(shellModel)

        XCTAssertEqual(shellModel.menuBarIconName, "calendar.circle")

        shellModel.setWindowOpen(true, for: AppSceneIDs.settings)

        XCTAssertEqual(shellModel.menuBarIconName, "calendar.circle.fill")
        XCTAssertEqual(shellModel.settingsMenuTitle, "Bring Settings Forward")
    }

    @MainActor
    func testMacUtilityShellModelUpdatesLaunchAtLoginStateFromService() {
        let service = MockLaunchAtLoginService(status: .notRegistered)
        let shellModel = MacUtilityShellModel(launchAtLoginService: service)
        retainForHostedXCTest(shellModel)

        XCTAssertFalse(shellModel.launchAtLoginEnabled)

        shellModel.setLaunchAtLoginEnabled(true)

        XCTAssertTrue(shellModel.launchAtLoginEnabled)
        XCTAssertNil(shellModel.launchAtLoginStatusMessage)
    }

    @MainActor
    func testMacUtilityShellModelOnlySuppressesInitialWindowOnceOutsideUITests() {
        let shellModel = MacUtilityShellModel(
            launchAtLoginService: MockLaunchAtLoginService(status: .notRegistered)
        )
        retainForHostedXCTest(shellModel)

        XCTAssertTrue(shellModel.shouldSuppressInitialSettingsWindow(uiTestMode: false))
        XCTAssertFalse(shellModel.shouldSuppressInitialSettingsWindow(uiTestMode: false))
        XCTAssertFalse(shellModel.shouldSuppressInitialSettingsWindow(uiTestMode: true))
    }

    @MainActor
    func testStatusLineShowsPendingSetupWhenNoCalendarsAreReady() async {
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
            userDefaults: defaults,
            googleAccountStore: MockGoogleAccountStore(),
            liveGoogleDebugConfiguration: LiveGoogleDebugConfiguration(
                isEnabled: false,
                preferredAccountEmail: nil,
                preferredCalendarName: nil
            )
        )

        await model.prepareIfNeeded()

        XCTAssertEqual(model.selectedCalendarSummary, "No calendars selected")
        XCTAssertEqual(model.pendingActivityLabel, "2 pending items")
        XCTAssertEqual(model.currentActivitySummary, "Choose calendars to sync")
        XCTAssertEqual(model.failureCountLabel, "0 failures")
    }

    @MainActor
    func testStatusLineShowsPendingSetupWhenStoredGoogleAccountsNeedCalendarRefresh() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defaults.set(["alpha": "alpha-calendar", "beta": "beta-calendar"], forKey: "settings.googleCalendar.selectedCalendarIDs")

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
            googleAccountStore: MockGoogleAccountStore(accounts: [
                StoredGoogleAccount(
                    id: "alpha",
                    email: "alpha@example.com",
                    displayName: "Alpha",
                    grantedScopes: ["calendar.events"],
                    usesCustomOAuthApp: false,
                    archivedUserData: Data("alpha".utf8)
                ),
                StoredGoogleAccount(
                    id: "beta",
                    email: "beta@example.com",
                    displayName: "Beta",
                    grantedScopes: ["calendar.events"],
                    usesCustomOAuthApp: false,
                    archivedUserData: Data("beta".utf8)
                ),
            ]),
            liveGoogleDebugConfiguration: LiveGoogleDebugConfiguration(
                isEnabled: false,
                preferredAccountEmail: nil,
                preferredCalendarName: nil
            )
        )

        await model.prepareIfNeeded()

        XCTAssertEqual(model.selectedCalendarSummary, "No calendars selected")
        XCTAssertEqual(model.pendingActivityLabel, "3 pending items")
        XCTAssertEqual(model.currentActivitySummary, "Choose calendars to sync")
        XCTAssertEqual(model.failureCountLabel, "0 failures")
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

    @MainActor
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

    func testLiveGoogleAccountResolverPrefersMatchingEmailThenActiveAccountThenFirstStoredAccount() {
        let alpha = StoredGoogleAccount(
            id: "alpha",
            email: "alpha@example.com",
            displayName: "Alpha",
            grantedScopes: ["calendar.events"],
            usesCustomOAuthApp: false,
            archivedUserData: Data("alpha".utf8)
        )
        let beta = StoredGoogleAccount(
            id: "beta",
            email: "beta@example.com",
            displayName: "Beta",
            grantedScopes: ["calendar.events"],
            usesCustomOAuthApp: false,
            archivedUserData: Data("beta".utf8)
        )

        XCTAssertEqual(
            LiveGoogleAccountResolver.resolvedAccountID(
                accounts: [alpha, beta],
                activeAccountID: "alpha",
                preferredEmail: "BETA@example.com"
            ),
            "beta"
        )
        XCTAssertEqual(
            LiveGoogleAccountResolver.resolvedAccountID(
                accounts: [alpha, beta],
                activeAccountID: "beta",
                preferredEmail: "missing@example.com"
            ),
            "beta"
        )
        XCTAssertEqual(
            LiveGoogleAccountResolver.resolvedAccountID(
                accounts: [alpha, beta],
                activeAccountID: "missing",
                preferredEmail: nil
            ),
            "alpha"
        )
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

    func testGoogleMirrorEligibilityRequiresBusyAndAcceptedWhenAttendeeResponseExists() {
        XCTAssertTrue(
            GoogleMirrorEligibility.shouldMirror(
                blocksTime: true,
                organizerIsCurrentUser: false,
                attendees: nil
            )
        )
        XCTAssertTrue(
            GoogleMirrorEligibility.shouldMirror(
                blocksTime: true,
                organizerIsCurrentUser: true,
                attendees: [
                    GoogleMirrorAttendee(isCurrentUser: true, responseStatus: "tentative")
                ]
            )
        )
        XCTAssertTrue(
            GoogleMirrorEligibility.shouldMirror(
                blocksTime: true,
                organizerIsCurrentUser: false,
                attendees: [
                    GoogleMirrorAttendee(isCurrentUser: true, responseStatus: "accepted")
                ]
            )
        )
        XCTAssertFalse(
            GoogleMirrorEligibility.shouldMirror(
                blocksTime: true,
                organizerIsCurrentUser: false,
                attendees: [
                    GoogleMirrorAttendee(isCurrentUser: true, responseStatus: "tentative")
                ]
            )
        )
        XCTAssertFalse(
            GoogleMirrorEligibility.shouldMirror(
                blocksTime: true,
                organizerIsCurrentUser: false,
                attendees: [
                    GoogleMirrorAttendee(isCurrentUser: true, responseStatus: "declined")
                ]
            )
        )
        XCTAssertFalse(
            GoogleMirrorEligibility.shouldMirror(
                blocksTime: true,
                organizerIsCurrentUser: false,
                attendees: [
                    GoogleMirrorAttendee(isCurrentUser: true, responseStatus: "needsAction")
                ]
            )
        )
        XCTAssertFalse(
            GoogleMirrorEligibility.shouldMirror(
                blocksTime: false,
                organizerIsCurrentUser: true,
                attendees: nil
            )
        )
    }

    func testAppleMirrorEligibilityRequiresBusyAndAcceptedWhenParticipantResponseExists() {
        XCTAssertTrue(
            AppleMirrorEligibility.shouldMirror(
                blocksTime: true,
                organizerIsCurrentUser: false,
                hasAttendees: false,
                currentUserParticipantStatus: nil
            )
        )
        XCTAssertTrue(
            AppleMirrorEligibility.shouldMirror(
                blocksTime: true,
                organizerIsCurrentUser: true,
                hasAttendees: true,
                currentUserParticipantStatus: .tentative
            )
        )
        XCTAssertTrue(
            AppleMirrorEligibility.shouldMirror(
                blocksTime: true,
                organizerIsCurrentUser: false,
                hasAttendees: true,
                currentUserParticipantStatus: .accepted
            )
        )
        XCTAssertFalse(
            AppleMirrorEligibility.shouldMirror(
                blocksTime: true,
                organizerIsCurrentUser: false,
                hasAttendees: true,
                currentUserParticipantStatus: .tentative
            )
        )
        XCTAssertFalse(
            AppleMirrorEligibility.shouldMirror(
                blocksTime: true,
                organizerIsCurrentUser: false,
                hasAttendees: true,
                currentUserParticipantStatus: .declined
            )
        )
        XCTAssertFalse(
            AppleMirrorEligibility.shouldMirror(
                blocksTime: true,
                organizerIsCurrentUser: false,
                hasAttendees: true,
                currentUserParticipantStatus: .pending
            )
        )
        XCTAssertFalse(
            AppleMirrorEligibility.shouldMirror(
                blocksTime: false,
                organizerIsCurrentUser: true,
                hasAttendees: false,
                currentUserParticipantStatus: nil
            )
        )
    }

    func testConnectedAccountListBuilderIncludesLiveAccounts() {
        let scenarioAccounts = [
            ConnectedAccountScenario(
                id: "scenario-google",
                provider: "google",
                displayName: "Fixture Account",
                selectedCalendars: [
                    SelectedCalendar(id: "fixture-calendar", name: "Fixture Calendar", role: .sourceAndDestination),
                ]
            )
        ]

        let appleCalendar = AppleCalendarSummary(
            id: "apple-calendar",
            title: "Busy Mirror",
            sourceTitle: "iCloud",
            sourceKind: .iCloud
        )
        let googleCalendar = GoogleCalendarSummary(
            id: "google-calendar",
            summary: "Consulting",
            accessRole: .writer,
            primary: false,
            timeZone: "America/Los_Angeles"
        )
        let googleAccount = GoogleConnectedAccount(
            id: "google-account",
            email: "person@example.com",
            displayName: "Person Example",
            grantedScopes: ["calendar.events"],
            usesCustomOAuthApp: false,
            serverAuthCodeAvailable: false
        )
        let googleCard = GoogleAccountCardModel(
            account: googleAccount,
            calendars: [googleCalendar],
            selectedCalendarID: googleCalendar.id,
            message: nil,
            messageTimestampLabel: nil,
            lastManagedEvent: nil,
            isOperationInFlight: false
        )

        let accounts = ConnectedAccountListBuilder.build(
            scenarioAccounts: scenarioAccounts,
            appleCalendarEnabled: true,
            appleCalendarAuthorizationState: .granted,
            selectedAppleCalendar: appleCalendar,
            googleAccountCards: [googleCard]
        )

        XCTAssertEqual(accounts.count, 3)
        XCTAssertEqual(accounts[0].displayName, "Fixture Account")
        XCTAssertEqual(accounts[1].providerLabel, "Apple / iCloud")
        XCTAssertEqual(accounts[1].selectedCalendars.first?.name, "Busy Mirror • iCloud")
        XCTAssertEqual(accounts[2].displayName, "Person Example")
        XCTAssertEqual(accounts[2].detail, "person@example.com")
        XCTAssertEqual(accounts[2].selectedCalendars.first?.name, "Consulting")
    }

    func testGoogleAccountStoreUpsertsAndRemovesAccounts() throws {
        let store = GoogleAccountStore(
            service: "test.google-account-store.\(#function)",
            accountName: "connected-google-accounts"
        )

        try store.saveAccounts([])

        let first = StoredGoogleAccount(
            id: "first",
            email: "first@example.com",
            displayName: "First",
            grantedScopes: ["calendar.events"],
            usesCustomOAuthApp: false,
            archivedUserData: Data("first".utf8)
        )
        let second = StoredGoogleAccount(
            id: "second",
            email: "second@example.com",
            displayName: "Second",
            grantedScopes: ["calendar.events", "calendar.calendarlist.readonly"],
            usesCustomOAuthApp: true,
            archivedUserData: Data("second".utf8)
        )

        XCTAssertEqual(try store.upsertAccount(first), [first])
        XCTAssertEqual(try store.upsertAccount(second), [second, first])
        XCTAssertEqual(try store.upsertAccount(first), [first, second])
        XCTAssertEqual(try store.removeAccount(id: second.id), [first])
        XCTAssertEqual(try store.loadAccounts(), [first])

        try store.saveAccounts([])
        XCTAssertEqual(try store.loadAccounts(), [])
    }

    func testBusyMirrorPlannerOnlyMirrorsPresentAndFutureTime() {
        let now = Date(timeIntervalSince1970: 1_713_600_000)
        let sourceParticipant = BusyMirrorParticipant(
            provider: .google,
            accountID: "source-account",
            calendarID: "source-calendar",
            displayName: "Source"
        )
        let targetParticipant = BusyMirrorParticipant(
            provider: .apple,
            accountID: nil,
            calendarID: "target-calendar",
            displayName: "Target"
        )

        let ongoingSourceEvent = BusyMirrorSourceEvent(
            key: BusyMirrorSourceKey(provider: .google, calendarID: "source-calendar", eventID: "evt-ongoing"),
            participantID: sourceParticipant.id,
            startDate: now.addingTimeInterval(-30 * 60),
            endDate: now.addingTimeInterval(30 * 60),
            isAllDay: false
        )
        let pastSourceEvent = BusyMirrorSourceEvent(
            key: BusyMirrorSourceKey(provider: .google, calendarID: "source-calendar", eventID: "evt-past"),
            participantID: sourceParticipant.id,
            startDate: now.addingTimeInterval(-2 * 60 * 60),
            endDate: now.addingTimeInterval(-60 * 60),
            isAllDay: false
        )

        let desiredMirrors = BusyMirrorSyncPlanner.desiredMirrors(
            participants: [sourceParticipant, targetParticipant],
            sourceEvents: [ongoingSourceEvent, pastSourceEvent],
            now: now
        )

        XCTAssertEqual(desiredMirrors.count, 1)
        XCTAssertEqual(desiredMirrors[0].startDate, now)
        XCTAssertEqual(desiredMirrors[0].endDate, ongoingSourceEvent.endDate)
        XCTAssertEqual(desiredMirrors[0].identity.sourceKey.eventID, "evt-ongoing")
    }

    func testBusyMirrorSyncPlannerBuildsFullMeshMirrorsAcrossParticipants() {
        let alpha = testParticipant(provider: .apple, calendarID: "alpha", displayName: "Alpha")
        let beta = testParticipant(provider: .google, accountID: "acct-beta", calendarID: "beta", displayName: "Beta")
        let gamma = testParticipant(provider: .google, accountID: "acct-gamma", calendarID: "gamma", displayName: "Gamma")
        let start = testDate(hour: 9)
        let end = testDate(hour: 10)

        let desiredMirrors = BusyMirrorSyncPlanner.desiredMirrors(
            participants: [alpha, beta, gamma],
            sourceEvents: [
                BusyMirrorSourceEvent(
                    key: BusyMirrorSourceKey(provider: .apple, calendarID: alpha.calendarID, eventID: "event-alpha"),
                    participantID: alpha.id,
                    startDate: start,
                    endDate: end,
                    isAllDay: false
                ),
                BusyMirrorSourceEvent(
                    key: BusyMirrorSourceKey(provider: .google, calendarID: beta.calendarID, eventID: "event-beta"),
                    participantID: beta.id,
                    startDate: start.addingTimeInterval(3600),
                    endDate: end.addingTimeInterval(3600),
                    isAllDay: false
                ),
            ],
            now: testDate(hour: 0)
        )

        XCTAssertEqual(desiredMirrors.count, 4)
        XCTAssertEqual(Set(desiredMirrors.map(\.targetParticipant.id)), Set([alpha.id, beta.id, gamma.id]))
        XCTAssertFalse(desiredMirrors.contains(where: { $0.identity.sourceKey.calendarID == $0.targetParticipant.calendarID }))
    }

    func testBusyMirrorSyncPlannerProducesCreateUpdateAndDeleteOperations() {
        let alpha = testParticipant(provider: .apple, calendarID: "alpha", displayName: "Alpha")
        let beta = testParticipant(provider: .google, accountID: "acct-beta", calendarID: "beta", displayName: "Beta")
        let gamma = testParticipant(provider: .google, accountID: "acct-gamma", calendarID: "gamma", displayName: "Gamma")

        let retainedIdentity = BusyMirrorIdentity(
            sourceKey: BusyMirrorSourceKey(provider: .apple, calendarID: alpha.calendarID, eventID: "kept"),
            targetParticipantID: beta.id
        )
        let staleIdentity = BusyMirrorIdentity(
            sourceKey: BusyMirrorSourceKey(provider: .google, calendarID: gamma.calendarID, eventID: "stale"),
            targetParticipantID: alpha.id
        )
        let updatedStart = testDate(hour: 11)
        let updatedEnd = testDate(hour: 12)
        let staleStart = testDate(hour: 13)
        let staleEnd = testDate(hour: 14)

        let desiredMirrors = [
            DesiredBusyMirrorEvent(
                identity: retainedIdentity,
                targetParticipant: beta,
                startDate: updatedStart,
                endDate: updatedEnd,
                isAllDay: false
            ),
            DesiredBusyMirrorEvent(
                identity: BusyMirrorIdentity(
                    sourceKey: BusyMirrorSourceKey(provider: .google, calendarID: beta.calendarID, eventID: "new"),
                    targetParticipantID: gamma.id
                ),
                targetParticipant: gamma,
                startDate: staleStart,
                endDate: staleEnd,
                isAllDay: false
            ),
        ]
        let existingMirrors = [
            ExistingBusyMirrorEvent(
                identity: retainedIdentity,
                targetParticipant: beta,
                eventID: "existing-updated",
                startDate: updatedStart.addingTimeInterval(-1800),
                endDate: updatedEnd.addingTimeInterval(-1800),
                isAllDay: false
            ),
            ExistingBusyMirrorEvent(
                identity: staleIdentity,
                targetParticipant: alpha,
                eventID: "existing-stale",
                startDate: staleStart,
                endDate: staleEnd,
                isAllDay: false
            ),
        ]

        let operations = BusyMirrorSyncPlanner.operations(
            desiredMirrors: desiredMirrors,
            existingMirrors: existingMirrors
        )

        XCTAssertEqual(operations.count, 3)
        XCTAssertEqual(operations.filterCreate.count, 1)
        XCTAssertEqual(operations.filterUpdate.count, 1)
        XCTAssertEqual(operations.filterDelete.count, 1)
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
            appleCalendarService: appleService,
            googleAccountStore: MockGoogleAccountStore()
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
            appleCalendarService: appleService,
            googleAccountStore: MockGoogleAccountStore()
        )

        await model.prepareIfNeeded()
        await model.connectAppleCalendar()

        XCTAssertTrue(model.isAppleCalendarEnabled)
        XCTAssertEqual(model.appleConnectionStatusLabel, "Permission denied")
        XCTAssertEqual(model.appleCalendarStatusLabel, "Permission denied")
        XCTAssertTrue(model.appleCalendarMessage?.contains("System Settings") == true)
    }

    @MainActor
    func testAppModelOpensAppleCalendarSettingsOnMacOS() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let settingsOpener = MockAppleCalendarSettingsOpener(openResult: true)
        let appleService = MockAppleCalendarService(
            authorizationState: .granted,
            calendars: [],
            createdEvent: nil
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
            appleCalendarService: appleService,
            appleCalendarSettingsOpener: settingsOpener,
            googleAccountStore: MockGoogleAccountStore()
        )

        await model.openAppleCalendarSettings()

        XCTAssertTrue(settingsOpener.didOpenCalendarAccessSettings)
        XCTAssertFalse(appleService.didRequestAccess)
        XCTAssertEqual(model.appleCalendarMessage, "Opened System Settings to Privacy & Security > Calendars.")
    }

    @MainActor
    func testAppModelSurfacesFailureWhenAppleCalendarSettingsCannotOpen() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let settingsOpener = MockAppleCalendarSettingsOpener(openResult: false)
        let appleService = MockAppleCalendarService(
            authorizationState: .granted,
            calendars: [],
            createdEvent: nil
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
            appleCalendarService: appleService,
            appleCalendarSettingsOpener: settingsOpener,
            googleAccountStore: MockGoogleAccountStore()
        )

        await model.openAppleCalendarSettings()

        XCTAssertTrue(settingsOpener.didOpenCalendarAccessSettings)
        XCTAssertFalse(appleService.didRequestAccess)
        XCTAssertEqual(
            model.appleCalendarMessage,
            "Calendar privacy settings could not be opened from this app. Open System Settings > Privacy & Security > Calendars manually."
        )
    }

    @MainActor
    func testAppModelRequestsAppleCalendarAccessBeforeOpeningSettingsWhenPermissionIsUndetermined() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let settingsOpener = MockAppleCalendarSettingsOpener(openResult: true)
        let appleService = MockAppleCalendarService(
            authorizationState: .notDetermined,
            calendars: [],
            createdEvent: nil
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
            appleCalendarService: appleService,
            appleCalendarSettingsOpener: settingsOpener,
            googleAccountStore: MockGoogleAccountStore()
        )

        await model.openAppleCalendarSettings()

        XCTAssertTrue(appleService.didRequestAccess)
        XCTAssertTrue(settingsOpener.didOpenCalendarAccessSettings)
        XCTAssertEqual(model.appleCalendarAuthorizationState, .granted)
        XCTAssertEqual(model.appleCalendarMessage, "Opened System Settings to Privacy & Security > Calendars.")
    }

    @MainActor
    func testAppModelSyncRemovesStaleMirrorsWhenOnlyOneParticipantRemains() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defaults.set(true, forKey: "settings.appleCalendar.enabled")
        defaults.set("icloud", forKey: "settings.appleCalendar.selectedCalendarID")

        let iCloud = AppleCalendarSummary(
            id: "icloud",
            title: "Busy Mirror",
            sourceTitle: "iCloud",
            sourceKind: .iCloud
        )
        let participant = testParticipant(provider: .apple, calendarID: iCloud.id, displayName: iCloud.displayName)
        let appleService = MockAppleCalendarService(
            authorizationState: .granted,
            calendars: [iCloud],
            createdEvent: nil
        )
        appleService.existingMirrors = [
            ExistingBusyMirrorEvent(
                identity: BusyMirrorIdentity(
                    sourceKey: BusyMirrorSourceKey(provider: .google, calendarID: "google-work", eventID: "orphaned"),
                    targetParticipantID: participant.id
                ),
                targetParticipant: participant,
                eventID: "mirror-1",
                startDate: testDate(hour: 8),
                endDate: testDate(hour: 9),
                isAllDay: false
            )
        ]

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
            appleCalendarService: appleService,
            googleAccountStore: MockGoogleAccountStore()
        )

        await model.prepareIfNeeded()

        XCTAssertEqual(appleService.deletedMirrorEventIDs, ["mirror-1"])
        XCTAssertEqual(model.syncFailureCountLabel, "Failed writes: 0")
        XCTAssertEqual(
            model.syncStatusDetail,
            "Only one calendar is selected. Removed stale mirrored busy holds from the remaining calendar."
        )
    }

    @MainActor
    func testAppModelChangingAppleCalendarSelectionCleansOldDestinationMirrors() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defaults.set(true, forKey: "settings.appleCalendar.enabled")
        defaults.set("old-calendar", forKey: "settings.appleCalendar.selectedCalendarID")

        let oldCalendar = AppleCalendarSummary(
            id: "old-calendar",
            title: "Old",
            sourceTitle: "iCloud",
            sourceKind: .iCloud
        )
        let newCalendar = AppleCalendarSummary(
            id: "new-calendar",
            title: "New",
            sourceTitle: "iCloud",
            sourceKind: .iCloud
        )
        let oldParticipant = testParticipant(provider: .apple, calendarID: oldCalendar.id, displayName: oldCalendar.displayName)
        let appleService = MockAppleCalendarService(
            authorizationState: .granted,
            calendars: [oldCalendar, newCalendar],
            createdEvent: nil
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
            appleCalendarService: appleService,
            googleAccountStore: MockGoogleAccountStore()
        )

        await model.prepareIfNeeded()
        appleService.existingMirrors = [
            ExistingBusyMirrorEvent(
                identity: BusyMirrorIdentity(
                    sourceKey: BusyMirrorSourceKey(provider: .google, calendarID: "source", eventID: "event-1"),
                    targetParticipantID: oldParticipant.id
                ),
                targetParticipant: oldParticipant,
                eventID: "mirror-old",
                startDate: testDate(hour: 15),
                endDate: testDate(hour: 16),
                isAllDay: false
            )
        ]

        model.selectedAppleCalendarID = newCalendar.id
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(appleService.deletedMirrorEventIDs, ["mirror-old"])
        XCTAssertEqual(
            model.appleCalendarMessage,
            "Removed 1 mirrored busy hold(s) from \(oldCalendar.displayName)."
        )
    }

    private func repoRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

#if os(macOS)
private var hostedXCTestRetainedObjects: [AnyObject] = []

@MainActor
private func retainForHostedXCTest(_ object: AnyObject) {
    hostedXCTestRetainedObjects.append(object)
}
#endif

#if os(macOS)
@MainActor
private final class MockLaunchAtLoginService: MacLaunchAtLoginControlling {
    var status: SMAppService.Status

    init(status: SMAppService.Status) {
        self.status = status
    }

    func setEnabled(_ enabled: Bool) throws {
        status = enabled ? .enabled : .notRegistered
    }
}
#endif

@MainActor
private final class MockAppleCalendarService: AppleCalendarProviding {
    var authorizationStateValue: AppleCalendarAuthorizationState
    var calendars: [AppleCalendarSummary]
    var createdEvent: AppleManagedEventRecord?
    var requestAccessError: Error?
    var didRequestAccess = false
    var deletedEventIDs: [String] = []
    var sourceEvents: [BusyMirrorSourceEvent] = []
    var existingMirrors: [ExistingBusyMirrorEvent] = []
    var createdMirrorIdentities: [BusyMirrorIdentity] = []
    var updatedMirrorIdentities: [BusyMirrorIdentity] = []
    var deletedMirrorEventIDs: [String] = []

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

    func listBusySourceEvents(in participant: BusyMirrorParticipant, window: DateInterval) throws -> [BusyMirrorSourceEvent] {
        sourceEvents.filter { $0.participantID == participant.id }
    }

    func listManagedMirrorEvents(in participant: BusyMirrorParticipant, window: DateInterval) throws -> [ExistingBusyMirrorEvent] {
        existingMirrors.filter { $0.targetParticipant.id == participant.id }
    }

    func createManagedMirrorEvent(in calendar: AppleCalendarSummary, desiredMirror: DesiredBusyMirrorEvent) throws {
        createdMirrorIdentities.append(desiredMirror.identity)
    }

    func updateManagedMirrorEvent(_ existingMirror: ExistingBusyMirrorEvent, desiredMirror: DesiredBusyMirrorEvent) throws {
        updatedMirrorIdentities.append(desiredMirror.identity)
    }

    func deleteManagedMirrorEvent(_ existingMirror: ExistingBusyMirrorEvent) throws {
        deletedMirrorEventIDs.append(existingMirror.eventID)
    }
}

private final class MockAppleCalendarSettingsOpener: AppleCalendarSettingsOpening {
    let openResult: Bool
    private(set) var didOpenCalendarAccessSettings = false

    init(openResult: Bool) {
        self.openResult = openResult
    }

    func openCalendarAccessSettings() -> Bool {
        didOpenCalendarAccessSettings = true
        return openResult
    }
}

private final class MockGoogleAccountStore: GoogleAccountStoring {
    private var accounts: [StoredGoogleAccount]

    init(accounts: [StoredGoogleAccount] = []) {
        self.accounts = accounts
    }

    func loadAccounts() throws -> [StoredGoogleAccount] {
        accounts
    }

    func saveAccounts(_ accounts: [StoredGoogleAccount]) throws {
        self.accounts = accounts
    }

    func upsertAccount(_ account: StoredGoogleAccount) throws -> [StoredGoogleAccount] {
        accounts.removeAll(where: { $0.id == account.id })
        accounts.insert(account, at: 0)
        return accounts
    }

    func removeAccount(id: String) throws -> [StoredGoogleAccount] {
        accounts.removeAll(where: { $0.id == id })
        return accounts
    }
}

private func testDate(hour: Int) -> Date {
    Calendar(identifier: .gregorian).date(
        from: DateComponents(
            timeZone: TimeZone(secondsFromGMT: 0),
            year: 2026,
            month: 4,
            day: 19,
            hour: hour
        )
    )!
}

private func testParticipant(
    provider: BusyMirrorProvider,
    accountID: String? = nil,
    calendarID: String,
    displayName: String
) -> BusyMirrorParticipant {
    BusyMirrorParticipant(
        provider: provider,
        accountID: accountID,
        calendarID: calendarID,
        displayName: displayName
    )
}

private extension Array where Element == BusyMirrorOperation {
    var filterCreate: [BusyMirrorOperation] {
        filter {
            if case .create = $0 {
                return true
            }
            return false
        }
    }

    var filterUpdate: [BusyMirrorOperation] {
        filter {
            if case .update = $0 {
                return true
            }
            return false
        }
    }

    var filterDelete: [BusyMirrorOperation] {
        filter {
            if case .delete = $0 {
                return true
            }
            return false
        }
    }
}
