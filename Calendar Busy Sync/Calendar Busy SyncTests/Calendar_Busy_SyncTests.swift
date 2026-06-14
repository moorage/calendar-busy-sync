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

    @MainActor
    func testAppModelUsesCooperativeSyncSchedulingOnlyOnIOS() {
        let iosSuite = "\(#function).ios"
        let macSuite = "\(#function).mac"
        let iosDefaults = UserDefaults(suiteName: iosSuite)!
        let macDefaults = UserDefaults(suiteName: macSuite)!
        iosDefaults.removePersistentDomain(forName: iosSuite)
        macDefaults.removePersistentDomain(forName: macSuite)
        defer {
            iosDefaults.removePersistentDomain(forName: iosSuite)
            macDefaults.removePersistentDomain(forName: macSuite)
        }

        let iosModel = AppModel(
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
            userDefaults: iosDefaults,
            googleAccountStore: MockGoogleAccountStore()
        )
        let macModel = AppModel(
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
            userDefaults: macDefaults,
            googleAccountStore: MockGoogleAccountStore()
        )

        XCTAssertTrue(iosModel.usesCooperativeIOSSyncScheduling)
        XCTAssertFalse(macModel.usesCooperativeIOSSyncScheduling)
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

    func testAppleCalendarSelectionResolverMatchesPortableReferenceWhenIdentifierDiffers() {
        let workCalendar = AppleCalendarSummary(
            id: "device-local-id",
            title: "Busy Mirror",
            sourceTitle: "iCloud",
            sourceKind: .iCloud
        )
        let otherCalendar = AppleCalendarSummary(
            id: "other-id",
            title: "Personal",
            sourceTitle: "iCloud",
            sourceKind: .iCloud
        )

        let resolvedID = AppleCalendarSelectionResolver.resolvedCalendarID(
            availableCalendars: [otherCalendar, workCalendar],
            persistedCalendarID: "missing-on-this-device",
            sharedReference: SharedAppleCalendarReference(calendar: workCalendar)
        )

        XCTAssertEqual(resolvedID, workCalendar.id)
    }

    func testBusyMirrorSyncAuditFormatterIncludesOperationContextAndError() {
        let participant = testParticipant(provider: .apple, calendarID: "apple-work", displayName: "iCloud • Work")
        let desiredMirror = DesiredBusyMirrorEvent(
            identity: BusyMirrorIdentity(
                sourceKey: BusyMirrorSourceKey(provider: .google, calendarID: "google-work", eventID: "event-1"),
                targetParticipantID: participant.id
            ),
            targetParticipant: participant,
            startDate: testDate(hour: 9),
            endDate: testDate(hour: 10),
            isAllDay: false
        )

        let message = BusyMirrorSyncAuditFormatter.failureMessage(
            for: .create(desiredMirror),
            error: AppleCalendarServiceError.requestFailed("The destination calendar rejected this write.")
        )

        XCTAssertTrue(message.contains("Create in iCloud • Work"))
        XCTAssertTrue(message.contains("The destination calendar rejected this write."))
    }

    @MainActor
    func testAppModelPrefersNewerSharedConfigurationAtLaunch() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defaults.set(2, forKey: "settings.pollIntervalMinutes")
        defaults.set(Date(timeIntervalSince1970: 10), forKey: "settings.lastModifiedAt")

        let sharedStore = MockSharedAppConfigurationStore(
            isAvailable: true,
            initialConfiguration: SharedAppConfiguration(
                updatedAt: Date(timeIntervalSince1970: 20),
                pollIntervalMinutes: 7,
                auditTrailLogLengthRawValue: AuditTrailLogLength.last5000.rawValue,
                isAppleCalendarEnabled: false,
                selectedAppleCalendarReference: nil,
                usesCustomGoogleOAuthApp: true,
                customGoogleOAuthClientID: "shared-client-id",
                customGoogleOAuthServerClientID: "shared-server-id",
                googleSelectedCalendarIDs: ["google-account": "shared-calendar"],
                activeGoogleAccountID: "google-account"
            )
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
            sharedConfigurationStore: sharedStore,
            googleAccountStore: MockGoogleAccountStore()
        )

        XCTAssertEqual(sharedStore.loadCallCount, 0)
        XCTAssertEqual(model.pollIntervalMinutes, 2)

        await model.prepareIfNeeded()

        XCTAssertEqual(model.pollIntervalMinutes, 7)
        XCTAssertEqual(model.auditTrailLogLength, .last5000)
        XCTAssertTrue(model.usesCustomGoogleOAuthApp)
        XCTAssertEqual(model.customGoogleOAuthClientID, "shared-client-id")
        XCTAssertEqual(model.selectedGoogleCalendarID(for: "google-account"), "shared-calendar")
    }

    @MainActor
    func testAppModelAppliesObservedSharedConfigurationChanges() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let sharedStore = MockSharedAppConfigurationStore(isAvailable: true)
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
            sharedConfigurationStore: sharedStore,
            googleAccountStore: MockGoogleAccountStore()
        )

        await model.prepareIfNeeded()

        await sharedStore.emit(
            SharedAppConfiguration(
                updatedAt: Date(timeIntervalSince1970: 40),
                pollIntervalMinutes: 11,
                auditTrailLogLengthRawValue: AuditTrailLogLength.last10000.rawValue,
                isAppleCalendarEnabled: false,
                selectedAppleCalendarReference: nil,
                usesCustomGoogleOAuthApp: true,
                customGoogleOAuthClientID: "remote-client-id",
                customGoogleOAuthServerClientID: "remote-server-id",
                googleSelectedCalendarIDs: ["shared-account": "shared-calendar-id"],
                activeGoogleAccountID: "shared-account"
            )
        )

        XCTAssertEqual(model.pollIntervalMinutes, 11)
        XCTAssertEqual(model.auditTrailLogLength, .last10000)
        XCTAssertEqual(model.customGoogleOAuthServerClientID, "remote-server-id")
        XCTAssertEqual(model.selectedGoogleCalendarID(for: "shared-account"), "shared-calendar-id")
    }

    @MainActor
    func testAppModelPublishesBookingSetupInSharedConfiguration() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let sharedStore = MockSharedAppConfigurationStore(isAvailable: true)
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
            sharedConfigurationStore: sharedStore,
            googleAccountStore: MockGoogleAccountStore()
        )

        model.bookingPageURLString = "https://example.com/book/"
        model.bookingInboxURLString = "https://inbox.example.com"
        model.bookingGitHubRepositoryString = "owner/booking"
        model.bookingPublicNameString = "Shared Booker"
        model.isAutomaticBookingApprovalEnabled = true

        var appointmentType = model.bookingAppointmentTypes[0]
        appointmentType.name = "Shared consultation"
        appointmentType.durationMinutes = 45
        model.updateBookingAppointmentType(appointmentType)

        let sharedBooking = sharedStore.loadConfiguration()?.bookingConfiguration
        XCTAssertEqual(sharedBooking?.pageURLString, "https://example.com/book/")
        XCTAssertEqual(sharedBooking?.inboxURLString, "https://inbox.example.com")
        XCTAssertEqual(sharedBooking?.gitHubRepositoryString, "owner/booking")
        XCTAssertEqual(sharedBooking?.publicNameString, "Shared Booker")
        XCTAssertEqual(sharedBooking?.isAutomaticApprovalEnabled, true)
        XCTAssertEqual(sharedBooking?.appointmentTypes.first?.name, "Shared consultation")
        XCTAssertEqual(sharedBooking?.appointmentTypes.first?.durationMinutes, 45)
    }

    @MainActor
    func testAppModelAppliesSharedBookingSetupAtLaunch() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defaults.set(Date(timeIntervalSince1970: 10), forKey: "settings.lastModifiedAt")

        let appointmentType = BookingAppointmentType(
            id: AppointmentTypeID("icloud-consult"),
            slug: "icloud-consult",
            name: "iCloud consult",
            summary: "Synced appointment setup.",
            durationMinutes: 60,
            minimumNoticeMinutes: 120,
            bufferBeforeMinutes: 10,
            bufferAfterMinutes: 15,
            weeklyHours: BookingWeeklyHours.weekdayDefault,
            location: BookingAppointmentLocation(mode: .phone, details: "Call the visitor."),
            calendarTarget: .apple(calendarID: "apple-target"),
            isAutoConfirmEnabled: true,
            questions: BookingDraftFactory.defaultAppointmentTypes[0].questions
        )
        let sharedStore = MockSharedAppConfigurationStore(
            isAvailable: true,
            initialConfiguration: SharedAppConfiguration(
                updatedAt: Date(timeIntervalSince1970: 20),
                pollIntervalMinutes: 7,
                auditTrailLogLengthRawValue: AuditTrailLogLength.last5000.rawValue,
                isAppleCalendarEnabled: false,
                selectedAppleCalendarReference: nil,
                usesCustomGoogleOAuthApp: false,
                customGoogleOAuthClientID: "",
                customGoogleOAuthServerClientID: "",
                googleSelectedCalendarIDs: [:],
                activeGoogleAccountID: nil,
                bookingConfiguration: SharedBookingConfiguration(
                    pageURLString: "https://example.com/book/",
                    inboxURLString: "https://inbox.example.com",
                    gitHubRepositoryString: "owner/booking",
                    gitHubBranchString: "main",
                    vercelScopeString: "team-slug",
                    vercelProjectNameString: "booking-relay",
                    publicNameString: "Shared Booker",
                    pageTitleString: "Book shared time",
                    pageSubtitleString: "Choose a time that works.",
                    timeZoneIdentifierString: "America/New_York",
                    themeAccentColorString: "#123456",
                    themeBackgroundColorString: "#F8F8F8",
                    themeTextColorString: "#111111",
                    selectedAppointmentTypeIDString: appointmentType.id.rawValue,
                    isAutomaticApprovalEnabled: true,
                    appointmentTypes: [appointmentType]
                )
            )
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
            sharedConfigurationStore: sharedStore,
            googleAccountStore: MockGoogleAccountStore()
        )

        await model.prepareIfNeeded()

        XCTAssertEqual(model.bookingPageURLString, "https://example.com/book/")
        XCTAssertEqual(model.bookingInboxURLString, "https://inbox.example.com")
        XCTAssertEqual(model.bookingGitHubRepositoryString, "owner/booking")
        XCTAssertEqual(model.bookingVercelProjectNameString, "booking-relay")
        XCTAssertEqual(model.bookingPublicNameString, "Shared Booker")
        XCTAssertEqual(model.bookingThemeAccentColorString, "#123456")
        XCTAssertEqual(model.selectedBookingAppointmentTypeIDString, "icloud-consult")
        XCTAssertTrue(model.isAutomaticBookingApprovalEnabled)
        XCTAssertEqual(model.bookingAppointmentTypes, [appointmentType])
    }

    @MainActor
    func testAppModelIgnoresObservedSharedConfigurationWhenDisabledLocally() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defaults.set(false, forKey: "settings.sharedConfiguration.enabled")

        let sharedStore = MockSharedAppConfigurationStore(isAvailable: true)
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
            sharedConfigurationStore: sharedStore,
            googleAccountStore: MockGoogleAccountStore()
        )

        await model.prepareIfNeeded()

        await sharedStore.emit(
            SharedAppConfiguration(
                updatedAt: Date(timeIntervalSince1970: 40),
                pollIntervalMinutes: 17,
                auditTrailLogLengthRawValue: AuditTrailLogLength.last10000.rawValue,
                isAppleCalendarEnabled: false,
                selectedAppleCalendarReference: nil,
                usesCustomGoogleOAuthApp: true,
                customGoogleOAuthClientID: "remote-client-id",
                customGoogleOAuthServerClientID: "remote-server-id",
                googleSelectedCalendarIDs: ["shared-account": "shared-calendar-id"],
                activeGoogleAccountID: "shared-account"
            )
        )

        XCTAssertFalse(model.isSharedConfigurationEnabled)
        XCTAssertEqual(model.pollIntervalMinutes, AppSettingsDefaults.pollIntervalMinutes)
        XCTAssertFalse(model.usesCustomGoogleOAuthApp)
        XCTAssertEqual(model.selectedGoogleCalendarID(for: "shared-account"), "")
    }

    @MainActor
    func testAppModelDoesNotPublishLocalSettingsWhenSharedConfigurationDisabled() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defaults.set(false, forKey: "settings.sharedConfiguration.enabled")

        let sharedStore = MockSharedAppConfigurationStore(isAvailable: true)
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
            sharedConfigurationStore: sharedStore,
            googleAccountStore: MockGoogleAccountStore()
        )

        model.pollIntervalMinutes = 9

        XCTAssertEqual(sharedStore.saveCallCount, 0)
        XCTAssertNil(sharedStore.loadConfiguration())
    }

    @MainActor
    func testAppModelSchedulesIOSBackgroundRefreshWhenAvailable() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let scheduler = MockIOSBackgroundRefreshScheduler(availability: .available)

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
            iosBackgroundRefreshScheduler: scheduler,
            googleAccountStore: MockGoogleAccountStore()
        )

        await model.prepareIfNeeded()

        XCTAssertEqual(scheduler.submissions.count, 1)
        XCTAssertEqual(scheduler.submissions[0].identifier, IOSBackgroundRefreshConstants.taskIdentifier)
        XCTAssertEqual(model.iosBackgroundRefreshStatusLabel, "On")
        XCTAssertTrue(model.iosBackgroundRefreshDetail?.contains("Best effort.") == true)
    }

    @MainActor
    func testAppModelSurfacesDeniedIOSBackgroundRefreshState() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let scheduler = MockIOSBackgroundRefreshScheduler(availability: .denied)

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
            iosBackgroundRefreshScheduler: scheduler,
            googleAccountStore: MockGoogleAccountStore()
        )

        await model.prepareIfNeeded()

        XCTAssertTrue(scheduler.submissions.isEmpty)
        XCTAssertEqual(model.iosBackgroundRefreshStatusLabel, "Off")
        XCTAssertTrue(model.iosBackgroundRefreshDetail?.contains("turned off") == true)
    }

    @MainActor
    func testAppModelDoesNotScheduleIOSBackgroundRefreshDuringUITestLaunch() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let scheduler = MockIOSBackgroundRefreshScheduler(availability: .available)

        let model = AppModel(
            launchOptions: HarnessLaunchOptions(
                scenarioRoot: nil,
                scenarioName: nil,
                windowSize: nil,
                dumpVisibleStateURL: nil,
                dumpPerfStateURL: nil,
                screenshotPathURL: nil,
                commandDirectoryURL: nil,
                uiTestMode: true,
                platformTarget: .ios,
                deviceClass: .iphone
            ),
            userDefaults: defaults,
            iosBackgroundRefreshScheduler: scheduler,
            googleAccountStore: MockGoogleAccountStore()
        )

        await model.prepareIfNeeded()

        XCTAssertTrue(scheduler.submissions.isEmpty)
        XCTAssertEqual(model.iosBackgroundRefreshStatusLabel, "Unavailable")
        XCTAssertTrue(model.iosBackgroundRefreshDetail?.contains("UI-test") == true)
    }

    @MainActor
    func testAppModelBackgroundRefreshTaskReschedulesNextRequest() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let scheduler = MockIOSBackgroundRefreshScheduler(availability: .available)

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
            iosBackgroundRefreshScheduler: scheduler,
            googleAccountStore: MockGoogleAccountStore()
        )

        await model.prepareIfNeeded()
        await model.handleIOSBackgroundRefreshTask()

        XCTAssertEqual(scheduler.submissions.count, 2)
        XCTAssertEqual(scheduler.cancelledIdentifiers, [
            IOSBackgroundRefreshConstants.taskIdentifier,
            IOSBackgroundRefreshConstants.taskIdentifier,
        ])
    }

    @MainActor
    func testAppModelManualIOSBackgroundRefreshVerificationReusesSchedulerPath() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let scheduler = MockIOSBackgroundRefreshScheduler(availability: .available)

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
            iosBackgroundRefreshScheduler: scheduler,
            googleAccountStore: MockGoogleAccountStore()
        )

        await model.prepareIfNeeded()
        await model.runIOSBackgroundRefreshVerificationNow()

        XCTAssertEqual(scheduler.submissions.count, 2)
        XCTAssertEqual(scheduler.cancelledIdentifiers.count, 2)
    }

    @MainActor
    func testAppModelCanRunIOSBackgroundRefreshVerificationOnlyWhenAvailableAndIdle() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let availableScheduler = MockIOSBackgroundRefreshScheduler(availability: .available)

        let iosModel = AppModel(
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
            iosBackgroundRefreshScheduler: availableScheduler,
            googleAccountStore: MockGoogleAccountStore()
        )

        await iosModel.prepareIfNeeded()

        XCTAssertTrue(iosModel.canRunIOSBackgroundRefreshVerification)

        let macModel = AppModel(
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
            userDefaults: UserDefaults(suiteName: "\(#function).mac")!,
            googleAccountStore: MockGoogleAccountStore()
        )

        await macModel.prepareIfNeeded()

        XCTAssertFalse(macModel.canRunIOSBackgroundRefreshVerification)
    }

    func testIOSBackgroundRefreshDebugConfigurationParsesOneShotLaunchFlag() {
        let configuration = IOSBackgroundRefreshDebugConfiguration.from(
            environment: [
                "CALENDAR_BUSY_SYNC_RUN_IOS_BG_REFRESH_NOW": "1",
            ]
        )

        XCTAssertTrue(configuration.runImmediately)
    }

    @MainActor
    func testSharedAppConfigurationDecodesLegacyPayloadWithoutGoogleAccountDescriptors() throws {
        let payload = """
        {
          "updatedAt": "2026-04-20T12:00:00Z",
          "pollIntervalMinutes": 2,
          "auditTrailLogLengthRawValue": "unlimited",
          "isAppleCalendarEnabled": false,
          "usesCustomGoogleOAuthApp": false,
          "customGoogleOAuthClientID": "",
          "customGoogleOAuthServerClientID": "",
          "googleSelectedCalendarIDs": {
            "google-account": "calendar-id"
          },
          "activeGoogleAccountID": "google-account"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let configuration = try decoder.decode(
            SharedAppConfiguration.self,
            from: Data(payload.utf8)
        )

        XCTAssertEqual(configuration.googleSelectedCalendarIDs["google-account"], "calendar-id")
        XCTAssertTrue(configuration.googleAccountDescriptors.isEmpty)
    }

    @MainActor
    func testGoogleAccountRosterBuilderBuildsSharedPendingAndRemovedRows() {
        let localCard = GoogleAccountCardModel(
            account: GoogleConnectedAccount(
                id: "local-only",
                email: "local@example.com",
                displayName: "Local Only",
                grantedScopes: ["calendar.events"],
                usesCustomOAuthApp: false,
                serverAuthCodeAvailable: false
            ),
            calendars: [],
            selectedCalendarID: "",
            message: nil,
            messageTimestampLabel: nil,
            lastManagedEvent: nil,
            isOperationInFlight: false
        )
        let sharedDescriptor = SharedGoogleAccountDescriptor(
            id: "shared-1",
            email: "shared@example.com",
            displayName: "Shared Account",
            usesCustomOAuthApp: false,
            selectedCalendarID: "shared-calendar",
            selectedCalendarDisplayName: "Shared Calendar"
        )

        let rows = GoogleAccountRosterBuilder.build(
            localCards: [localCard],
            sharedDescriptors: [sharedDescriptor],
            isSharedConfigurationEnabled: true
        )

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].kind, .needsLocalConnection)
        XCTAssertEqual(rows[0].displayName, "Shared Account")
        XCTAssertEqual(rows[0].selectedCalendarDisplayName, "Shared Calendar")
        XCTAssertEqual(rows[1].kind, .removedFromShared)
        XCTAssertEqual(rows[1].displayName, "Local Only")
    }

    @MainActor
    func testGoogleAccountRosterBuilderMatchesSharedDescriptorByEmail() {
        let calendar = GoogleCalendarSummary(
            id: "calendar-id",
            summary: "Work",
            accessRole: .owner,
            primary: false,
            timeZone: nil
        )
        let localCard = GoogleAccountCardModel(
            account: GoogleConnectedAccount(
                id: "local-id",
                email: "shared@example.com",
                displayName: "Shared Local",
                grantedScopes: ["calendar.events"],
                usesCustomOAuthApp: false,
                serverAuthCodeAvailable: false
            ),
            calendars: [calendar],
            selectedCalendarID: "calendar-id",
            message: nil,
            messageTimestampLabel: nil,
            lastManagedEvent: nil,
            isOperationInFlight: false
        )
        let sharedDescriptor = SharedGoogleAccountDescriptor(
            id: "shared-id",
            email: "shared@example.com",
            displayName: "Shared Remote",
            usesCustomOAuthApp: false,
            selectedCalendarID: "calendar-id",
            selectedCalendarDisplayName: "Work"
        )

        let rows = GoogleAccountRosterBuilder.build(
            localCards: [localCard],
            sharedDescriptors: [sharedDescriptor],
            isSharedConfigurationEnabled: true
        )

        XCTAssertEqual(rows.count, 1)
        switch rows[0].kind {
        case .connected:
            break
        default:
            XCTFail("Expected the shared/local email match to produce a connected row.")
        }
        XCTAssertEqual(rows[0].stableAccountID, "local-id")
        XCTAssertEqual(rows[0].selectedCalendarDisplayName, "Work")
        XCTAssertTrue(rows[0].isConnectedLocally)
    }

    @MainActor
    func testGoogleSharedAccountHandoffMatchesDescriptorByEmailAndMigratesCalendarSelection() {
        let connectedAccount = StoredGoogleAccount(
            id: "new-account-id",
            email: "shared@example.com",
            displayName: "Shared Account",
            grantedScopes: ["calendar.events"],
            usesCustomOAuthApp: false,
            archivedUserData: Data("shared".utf8)
        )
        let descriptor = SharedGoogleAccountDescriptor(
            id: "old-account-id",
            email: "shared@example.com",
            displayName: "Shared Account",
            usesCustomOAuthApp: false,
            selectedCalendarID: "shared-calendar",
            selectedCalendarDisplayName: "Shared Calendar"
        )

        let migrated = GoogleSharedAccountHandoff.migratedSelectedCalendarIDs(
            currentSelectedCalendarIDs: ["old-account-id": "shared-calendar"],
            connectedAccount: connectedAccount,
            sharedDescriptors: [descriptor]
        )

        XCTAssertNil(migrated["old-account-id"])
        XCTAssertEqual(migrated["new-account-id"], "shared-calendar")
    }

    @MainActor
    func testGoogleSharedAccountHandoffReconcilesDescriptorsUsingLocalSelectionsAndCalendarNames() {
        let localAccount = StoredGoogleAccount(
            id: "local-id",
            email: "shared@example.com",
            displayName: "Shared Local",
            grantedScopes: ["calendar.events"],
            usesCustomOAuthApp: true,
            archivedUserData: Data("shared".utf8)
        )
        let existingDescriptor = SharedGoogleAccountDescriptor(
            id: "remote-id",
            email: "shared@example.com",
            displayName: "Shared Remote",
            usesCustomOAuthApp: false,
            selectedCalendarID: "old-calendar",
            selectedCalendarDisplayName: "Old Calendar"
        )
        let localCalendar = GoogleCalendarSummary(
            id: "new-calendar",
            summary: "Production",
            accessRole: .owner,
            primary: false,
            timeZone: nil
        )

        let reconciled = GoogleSharedAccountHandoff.reconciledDescriptors(
            currentDescriptors: [existingDescriptor],
            localAccounts: [localAccount],
            googleSelectedCalendarIDs: ["local-id": "new-calendar"],
            googleCalendarsByAccountID: ["local-id": [localCalendar]]
        )

        XCTAssertEqual(reconciled.count, 1)
        XCTAssertEqual(reconciled[0].id, "local-id")
        XCTAssertEqual(reconciled[0].email, "shared@example.com")
        XCTAssertEqual(reconciled[0].displayName, "Shared Local")
        XCTAssertTrue(reconciled[0].usesCustomOAuthApp)
        XCTAssertEqual(reconciled[0].selectedCalendarID, "new-calendar")
        XCTAssertEqual(reconciled[0].selectedCalendarDisplayName, "Production")
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
            "--booking-dry-run-on-launch",
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
        XCTAssertTrue(options.bookingDryRunOnLaunch)
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

    @MainActor
    func testAppModelManualSharedConfigurationSyncReportsMatchingSharedConfiguration() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let sharedStore = MockSharedAppConfigurationStore(isAvailable: true)

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
            sharedConfigurationStore: sharedStore,
            googleAccountStore: MockGoogleAccountStore()
        )

        await model.prepareIfNeeded()
        await model.syncSharedConfigurationNow()

        XCTAssertEqual(sharedStore.requestSyncCallCount, 1)
        XCTAssertEqual(model.sharedConfigurationStatusLabel, "Updated")
        XCTAssertTrue(model.sharedConfigurationStatusMessage.contains("already matches"))
        XCTAssertTrue(model.auditTrailEntries.contains(where: {
            $0.title == "iCloud settings sync" && $0.detail.contains("already matches")
        }))
    }

    @MainActor
    func testAppModelManualSharedConfigurationSyncAppliesNewerRemoteConfiguration() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defaults.set(Date(timeIntervalSince1970: 10), forKey: "settings.lastModifiedAt")
        let sharedStore = MockSharedAppConfigurationStore(isAvailable: true)

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
            sharedConfigurationStore: sharedStore,
            googleAccountStore: MockGoogleAccountStore()
        )

        sharedStore.setConfiguration(
            SharedAppConfiguration(
                updatedAt: Date(timeIntervalSince1970: 40),
                pollIntervalMinutes: 13,
                auditTrailLogLengthRawValue: AuditTrailLogLength.last5000.rawValue,
                isAppleCalendarEnabled: false,
                selectedAppleCalendarReference: nil,
                usesCustomGoogleOAuthApp: false,
                customGoogleOAuthClientID: "",
                customGoogleOAuthServerClientID: "",
                googleSelectedCalendarIDs: [:],
                activeGoogleAccountID: nil
            )
        )

        await model.syncSharedConfigurationNow()

        XCTAssertEqual(model.pollIntervalMinutes, 13)
        XCTAssertEqual(model.auditTrailLogLength, .last5000)
        XCTAssertTrue(model.sharedConfigurationStatusMessage.contains("Applied updated shared settings from iCloud"))
        XCTAssertTrue(model.auditTrailEntries.contains(where: {
            $0.title == "iCloud settings sync" && $0.detail.contains("Applied updated shared settings from iCloud")
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
    func testMacMenuBarSnapshotFreezesCurrentStatusStrings() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defer {
            defaults.removePersistentDomain(forName: #function)
        }

        let appModel = AppModel(
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
        let shellModel = MacUtilityShellModel(
            launchAtLoginService: MockLaunchAtLoginService(status: .notRegistered)
        )
        retainForHostedXCTest(shellModel)

        let snapshot = MenuPresentationSnapshot(appModel: appModel, shellModel: shellModel)

        XCTAssertEqual(snapshot.currentActivitySummary, appModel.currentActivitySummary)
        XCTAssertEqual(snapshot.currentActivityIconName, appModel.currentActivityIconName)
        XCTAssertEqual(snapshot.pendingActivityLabel, appModel.pendingActivityLabel)
        XCTAssertEqual(snapshot.failureCount, appModel.failureCount)
        XCTAssertEqual(snapshot.settingsMenuTitle, shellModel.settingsMenuTitle)
        XCTAssertEqual(snapshot.logsMenuTitle, shellModel.logsMenuTitle)
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
    func testMacUtilityShellModelShowsDockIconOnlyWhileWindowsRemainOpen() {
        let applicationController = MockMacApplicationController()
        let shellModel = MacUtilityShellModel(
            launchAtLoginService: MockLaunchAtLoginService(status: .notRegistered),
            applicationController: applicationController
        )
        retainForHostedXCTest(shellModel)

        XCTAssertEqual(applicationController.dockVisibilityCalls, [false])

        shellModel.setWindowOpen(true, for: AppSceneIDs.settings)
        XCTAssertEqual(applicationController.dockVisibilityCalls.last, true)

        shellModel.setWindowOpen(true, for: AppSceneIDs.auditTrail)
        XCTAssertEqual(applicationController.dockVisibilityCalls.last, true)

        shellModel.setWindowOpen(false, for: AppSceneIDs.settings)
        XCTAssertEqual(applicationController.dockVisibilityCalls.last, true)

        shellModel.setWindowOpen(false, for: AppSceneIDs.auditTrail)
        XCTAssertEqual(applicationController.dockVisibilityCalls.last, false)
    }

    @MainActor
    func testMacUtilityShellModelPresentSceneRaisesTargetWindowAndMakesDockVisible() async {
        let applicationController = MockMacApplicationController()
        let shellModel = MacUtilityShellModel(
            launchAtLoginService: MockLaunchAtLoginService(status: .notRegistered),
            applicationController: applicationController
        )
        retainForHostedXCTest(shellModel)

        var openedSceneID: String?
        shellModel.presentScene(AppSceneIDs.settings) { sceneID in
            openedSceneID = sceneID
            XCTAssertEqual(applicationController.dockVisibilityCalls.last, true)
        }

        XCTAssertEqual(openedSceneID, AppSceneIDs.settings)

        let expectation = expectation(description: "presentScene raises the requested window")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if applicationController.activationCalls >= 1,
               applicationController.broughtForwardSceneIDs.contains(AppSceneIDs.settings) {
                expectation.fulfill()
            }
        }

        await fulfillment(of: [expectation], timeout: 1.0)
    }

    @MainActor
    func testMacUtilityShellModelCanDisableDockVisibilityManagementForHostedTests() async {
        let applicationController = MockMacApplicationController()
        let shellModel = MacUtilityShellModel(
            launchAtLoginService: MockLaunchAtLoginService(status: .notRegistered),
            applicationController: applicationController,
            managesDockVisibility: false
        )
        retainForHostedXCTest(shellModel)

        XCTAssertTrue(applicationController.dockVisibilityCalls.isEmpty)

        shellModel.setWindowOpen(true, for: AppSceneIDs.settings)
        shellModel.presentScene(AppSceneIDs.settings) { _ in }

        let expectation = expectation(description: "hosted shell still raises the target scene")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if applicationController.activationCalls >= 1,
               applicationController.broughtForwardSceneIDs.contains(AppSceneIDs.settings) {
                expectation.fulfill()
            }
        }

        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertTrue(applicationController.dockVisibilityCalls.isEmpty)
    }

    @MainActor
    func testMacWindowVisibilityObserverDefersVisibilityCallbackOffViewUpdateTurn() async {
        var receivedVisibilityChanges: [Bool] = []
        let coordinator = MacWindowVisibilityObserver.Coordinator { isVisible in
            receivedVisibilityChanges.append(isVisible)
        }
        let window = NSWindow()

        coordinator.attach(to: window)

        XCTAssertTrue(receivedVisibilityChanges.isEmpty)

        let expectation = expectation(description: "visibility callback arrives asynchronously")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if receivedVisibilityChanges == [window.isVisible] {
                expectation.fulfill()
            }
        }

        await fulfillment(of: [expectation], timeout: 1.0)
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
            googleSignInEnvironment: GoogleSignInEnvironment(blockingReason: nil),
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

    @MainActor
    func testBookingImportApprovalWritesAppleCalendarEventAndDeletesRelayRecord() async throws {
        let suiteName = "CalendarBusySyncTests.\(#function)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let secrets = BookingLocalSecrets.generate()
        let secretStore = MockBookingSecretStore(
            secrets: secrets,
            adminToken: "admin-token"
        )
        let appleCalendar = AppleCalendarSummary(
            id: "apple-calendar",
            title: "Consulting",
            sourceTitle: "iCloud",
            sourceKind: .iCloud
        )
        let appleService = MockAppleCalendarService(
            authorizationState: .granted,
            calendars: [appleCalendar],
            createdEvent: nil
        )
        let inviteFileWriter = MockBookingInviteFileWriter(
            inviteFileURL: URL(fileURLWithPath: "/tmp/booking-request-approval-1.ics")
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
            sharedConfigurationStore: MockSharedAppConfigurationStore(isAvailable: true),
            appleCalendarService: appleService,
            bookingSecretStore: secretStore,
            bookingInviteFileWriter: inviteFileWriter,
            googleAccountStore: MockGoogleAccountStore()
        )
        model.bookingInboxURLString = "https://relay.example.com"
        await model.connectAppleCalendar()

        let now = Date()
        let slotStart = now.addingTimeInterval(60 * 60)
        let claim = BookingSlotClaim(
            appointmentTypeID: AppointmentTypeID("intro-call"),
            slotID: BookingSlotID("intro-call-\(Int(slotStart.timeIntervalSince1970))"),
            startsAt: slotStart,
            endsAt: slotStart.addingTimeInterval(30 * 60),
            generatedAt: now,
            expiresAt: slotStart,
            nonce: "nonce",
            signingKeyVersion: "v1"
        )
        let token = try secrets.slotSigner.sign(claim)
        let envelope = try BookingTestRequestSender.encrypt(
            plaintext: BookingTestRequestPlaintext(
                requestID: BookingRequestID("request-approval-1"),
                appointmentTypeID: claim.appointmentTypeID,
                slotID: claim.slotID,
                slotToken: token,
                visitor: BookingTestVisitor(
                    name: "Matt Moore",
                    email: "matt@alumni.ucsd.edu",
                    topic: "A 30 minute meeting",
                    guestEmails: ["guest@example.com"]
                ),
                browserTimeZone: "America/Los_Angeles",
                createdAt: now
            ),
            slot: BookingPublishedSlot(
                id: claim.slotID,
                appointmentTypeID: claim.appointmentTypeID,
                startsAt: claim.startsAt,
                endsAt: claim.endsAt,
                expiresAt: claim.expiresAt,
                token: token
            ),
            config: BookingPublishedSiteConfig(
                share: BookingPublishedShare(id: BookingShareID("intro-call")),
                inbox: BookingPublishedInbox(
                    id: secrets.inboxID,
                    url: try XCTUnwrap(URL(string: "https://relay.example.com"))
                ),
                encryption: BookingPublishedEncryption(
                    keyID: secrets.keyID,
                    publicKeyJWK: BookingKeyMaterial.publicKey(
                        from: try secrets.privateKey,
                        keyID: secrets.keyID
                    ).jwk
                )
            ),
            createdAt: now
        )

        let responseEncoder = JSONEncoder()
        responseEncoder.dateEncodingStrategy = .iso8601
        let listPayload = try responseEncoder.encode(BookingRelayRequestPage(
            requests: [envelope],
            cursor: nil
        ))
        RelayURLProtocol.responders = [
            "GET /v1/inboxes/\(secrets.inboxID.rawValue)/requests": { request in
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer admin-token")
                return (200, listPayload)
            },
            "DELETE /v1/inboxes/\(secrets.inboxID.rawValue)/requests/request-approval-1": { request in
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer admin-token")
                return (204, Data())
            },
        ]
        URLProtocol.registerClass(RelayURLProtocol.self)
        defer {
            URLProtocol.unregisterClass(RelayURLProtocol.self)
            RelayURLProtocol.responders = [:]
            RelayURLProtocol.seenRequests = []
        }

        await model.importBookingRequests()
        let imported = try XCTUnwrap(model.importedBookingRequests.first)
        XCTAssertEqual(imported.status, .pendingReview)

        await model.approveBookingRequest(imported.id)

        XCTAssertEqual(appleService.createdBookingRequests.map(\.id), [imported.id])
        XCTAssertEqual(inviteFileWriter.writtenRequests.map(\.id), [imported.id])
        XCTAssertEqual(inviteFileWriter.writtenRequests.first?.inviteeEmails, ["matt@alumni.ucsd.edu", "guest@example.com"])
        XCTAssertEqual(model.importedBookingRequests.first?.status, .approved)
        XCTAssertEqual(model.importedBookingRequests.first?.calendarEventID, "booking-request-approval-1")
        XCTAssertTrue(model.importedBookingRequests.first?.message.contains("booking-request-approval-1.ics") ?? false)
        XCTAssertTrue(model.activeBookingRequests.isEmpty)
        XCTAssertEqual(model.bookingRequestHistory.map(\.id), [imported.id])
        XCTAssertTrue(RelayURLProtocol.seenRequests.contains("DELETE /v1/inboxes/\(secrets.inboxID.rawValue)/requests/request-approval-1"))
    }

    @MainActor
    func testBookingInboxActionsDoNotRequirePublishedPageStatus() throws {
        let suiteName = "CalendarBusySyncTests.\(#function)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let snapshot = BookingSetupSnapshot(
            pageStatus: .generatedLocally,
            inboxStatus: .connected,
            pendingRequestCount: 3,
            lastMessage: nil
        )
        defaults.set(
            try JSONEncoder().encode(snapshot),
            forKey: "settings.booking.setupSnapshot"
        )
        defaults.set("https://moorage.github.io/booking-test/", forKey: "settings.booking.pageURL")
        defaults.set("https://live-booking-relay-vercel.vercel.app", forKey: "settings.booking.inboxURL")

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
            sharedConfigurationStore: MockSharedAppConfigurationStore(isAvailable: true),
            bookingSecretStore: MockBookingSecretStore(secrets: BookingLocalSecrets.generate(), adminToken: "admin-token"),
            googleAccountStore: MockGoogleAccountStore()
        )

        XCTAssertFalse(model.bookingSetupSnapshot.isReady)
        XCTAssertTrue(model.canImportBookingRequests)
        XCTAssertTrue(model.canSendBookingTestRequest)
    }

    @MainActor
    func testBookingInboxReadySnapshotDowngradesWhenAdminTokenIsMissing() throws {
        let suiteName = "CalendarBusySyncTests.\(#function)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let snapshot = BookingSetupSnapshot(
            pageStatus: .published,
            inboxStatus: .connected,
            pendingRequestCount: 3,
            lastMessage: nil
        )
        defaults.set(
            try JSONEncoder().encode(snapshot),
            forKey: "settings.booking.setupSnapshot"
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
            sharedConfigurationStore: MockSharedAppConfigurationStore(isAvailable: true),
            bookingSecretStore: MockBookingSecretStore(secrets: BookingLocalSecrets.generate(), adminToken: nil),
            googleAccountStore: MockGoogleAccountStore()
        )

        XCTAssertEqual(model.bookingSetupSnapshot.inboxStatus, .reachable)
        XCTAssertFalse(model.canImportBookingRequests)
    }

    @MainActor
    func testBookingDismissalConfirmsDeployOnlyForPublishablePendingChanges() throws {
        let suiteName = "CalendarBusySyncTests.\(#function)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let snapshot = BookingSetupSnapshot(
            pageStatus: .needsPublish,
            inboxStatus: .connected,
            pendingRequestCount: 0,
            lastMessage: nil
        )
        defaults.set(try JSONEncoder().encode(snapshot), forKey: "settings.booking.setupSnapshot")
        defaults.set("moorage/booking-test", forKey: "settings.booking.github.repository")
        defaults.set("ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKey", forKey: "settings.booking.github.deployKey.publicKey")
        defaults.set("moorage/booking-test", forKey: "settings.booking.github.deployKey.repository")

        let publishableModel = AppModel(
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
            sharedConfigurationStore: MockSharedAppConfigurationStore(isAvailable: true),
            bookingSecretStore: MockBookingSecretStore(secrets: BookingLocalSecrets.generate(), adminToken: nil),
            googleAccountStore: MockGoogleAccountStore()
        )

        XCTAssertTrue(publishableModel.shouldConfirmBookingPublishOnDismiss)

        defaults.removeObject(forKey: "settings.booking.github.deployKey.publicKey")
        let unpublishableModel = AppModel(
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
            sharedConfigurationStore: MockSharedAppConfigurationStore(isAvailable: true),
            bookingSecretStore: MockBookingSecretStore(secrets: BookingLocalSecrets.generate(), adminToken: nil),
            googleAccountStore: MockGoogleAccountStore()
        )

        XCTAssertFalse(unpublishableModel.shouldConfirmBookingPublishOnDismiss)
    }

    @MainActor
    func testUITestModeUsesEnvironmentBookingInboxAdminToken() throws {
        let suiteName = "CalendarBusySyncTests.\(#function)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        setenv("CALENDAR_BUSY_SYNC_UI_TEST_BOOKING_INBOX_ADMIN_TOKEN", " ui-test-admin-token ", 1)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            unsetenv("CALENDAR_BUSY_SYNC_UI_TEST_BOOKING_INBOX_ADMIN_TOKEN")
        }

        let snapshot = BookingSetupSnapshot(
            pageStatus: .generatedLocally,
            inboxStatus: .connected,
            pendingRequestCount: 3,
            lastMessage: nil
        )
        defaults.set(
            try JSONEncoder().encode(snapshot),
            forKey: "settings.booking.setupSnapshot"
        )

        let secretStore = MockBookingSecretStore(secrets: BookingLocalSecrets.generate(), adminToken: nil)
        let model = AppModel(
            launchOptions: HarnessLaunchOptions(
                scenarioRoot: nil,
                scenarioName: nil,
                windowSize: nil,
                dumpVisibleStateURL: nil,
                dumpPerfStateURL: nil,
                screenshotPathURL: nil,
                commandDirectoryURL: nil,
                uiTestMode: true,
                platformTarget: .macos,
                deviceClass: .mac
            ),
            userDefaults: defaults,
            sharedConfigurationStore: MockSharedAppConfigurationStore(isAvailable: true),
            bookingSecretStore: secretStore,
            googleAccountStore: MockGoogleAccountStore()
        )

        XCTAssertEqual(model.bookingInboxAdminTokenString, "ui-test-admin-token")
        XCTAssertEqual(secretStore.adminToken, nil)
        XCTAssertEqual(model.bookingSetupSnapshot.inboxStatus, .connected)
        XCTAssertTrue(model.canImportBookingRequests)
    }

    @MainActor
    func testUITestModeConsumesBookingInboxAdminTokenFile() throws {
        let suiteName = "CalendarBusySyncTests.\(#function)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let tokenFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("calendar-busy-sync-ui-test-token-\(UUID().uuidString)")
        try " file-admin-token ".write(to: tokenFileURL, atomically: true, encoding: .utf8)
        setenv("CALENDAR_BUSY_SYNC_UI_TEST_BOOKING_INBOX_ADMIN_TOKEN_FILE", tokenFileURL.path, 1)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            unsetenv("CALENDAR_BUSY_SYNC_UI_TEST_BOOKING_INBOX_ADMIN_TOKEN_FILE")
            try? FileManager.default.removeItem(at: tokenFileURL)
        }

        let snapshot = BookingSetupSnapshot(
            pageStatus: .generatedLocally,
            inboxStatus: .connected,
            pendingRequestCount: 3,
            lastMessage: nil
        )
        defaults.set(
            try JSONEncoder().encode(snapshot),
            forKey: "settings.booking.setupSnapshot"
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
                uiTestMode: true,
                platformTarget: .macos,
                deviceClass: .mac
            ),
            userDefaults: defaults,
            sharedConfigurationStore: MockSharedAppConfigurationStore(isAvailable: true),
            bookingSecretStore: MockBookingSecretStore(secrets: BookingLocalSecrets.generate(), adminToken: nil),
            googleAccountStore: MockGoogleAccountStore()
        )

        XCTAssertEqual(model.bookingInboxAdminTokenString, "file-admin-token")
        XCTAssertFalse(FileManager.default.fileExists(atPath: tokenFileURL.path))
        XCTAssertEqual(model.bookingSetupSnapshot.inboxStatus, .connected)
        XCTAssertTrue(model.canImportBookingRequests)
    }

    @MainActor
    func testBookingImportSkipsIncompatibleRelayRequests() async throws {
        let suiteName = "CalendarBusySyncTests.\(#function)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let secrets = BookingLocalSecrets.generate()
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
            sharedConfigurationStore: MockSharedAppConfigurationStore(isAvailable: true),
            bookingSecretStore: MockBookingSecretStore(secrets: secrets, adminToken: "admin-token"),
            googleAccountStore: MockGoogleAccountStore()
        )
        model.bookingInboxURLString = "https://relay.example.com"

        let invalidEnvelope = EncryptedBookingRequestEnvelope(
            schemaVersion: 1,
            requestID: BookingRequestID("request-stale-1"),
            inboxID: secrets.inboxID,
            shareID: BookingShareID("intro-call"),
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(60 * 60),
            keyID: "old-key",
            algorithm: "P256.ECDH-ES+A256GCM",
            ephemeralPublicKeyJWK: nil,
            nonce: "not-base64",
            ciphertext: "not-base64"
        )
        let responseEncoder = JSONEncoder()
        responseEncoder.dateEncodingStrategy = .iso8601
        let listPayload = try responseEncoder.encode(BookingRelayRequestPage(
            requests: [invalidEnvelope],
            cursor: nil
        ))
        RelayURLProtocol.responders = [
            "GET /v1/inboxes/\(secrets.inboxID.rawValue)/requests": { request in
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer admin-token")
                return (200, listPayload)
            },
        ]
        URLProtocol.registerClass(RelayURLProtocol.self)
        defer {
            URLProtocol.unregisterClass(RelayURLProtocol.self)
            RelayURLProtocol.responders = [:]
            RelayURLProtocol.seenRequests = []
        }

        await model.importBookingRequests()

        XCTAssertTrue(model.importedBookingRequests.isEmpty)
        XCTAssertEqual(model.bookingSetupSnapshot.inboxStatus, .connected)
        XCTAssertEqual(model.bookingSetupSnapshot.pendingRequestCount, 0)
        XCTAssertEqual(
            model.bookingSetupSnapshot.lastMessage,
            "Skipped 1 booking request(s) that no longer match this device."
        )
    }

    @MainActor
    func testBookingPageURLUsesSelectedAppointmentTypeDeepLink() throws {
        let suiteName = "CalendarBusySyncTests.\(#function)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let model = AppModel(
            launchOptions: HarnessLaunchOptions(
                platformTarget: .macos,
                deviceClass: .mac
            ),
            userDefaults: defaults,
            sharedConfigurationStore: MockSharedAppConfigurationStore(isAvailable: true),
            bookingSecretStore: MockBookingSecretStore(secrets: nil, adminToken: nil),
            googleAccountStore: MockGoogleAccountStore(),
            googleSignInEnvironment: GoogleSignInEnvironment(blockingReason: "test")
        )

        model.bookingPageURLString = "https://moorage.github.io/booking-test/?ref=settings"
        model.selectedBookingAppointmentTypeIDString = "intro-call"

        XCTAssertEqual(
            model.selectedBookingAppointmentTypeURLString,
            "https://moorage.github.io/booking-test/?ref=settings&appointment=intro-call"
        )
    }

    @MainActor
    func testBookingApprovalCalendarTargetNamesSelectedAppleCalendar() async throws {
        let suiteName = "CalendarBusySyncTests.\(#function)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let iCloud = AppleCalendarSummary(
            id: "icloud",
            title: "Matt - iCloud",
            sourceTitle: "iCloud",
            sourceKind: .iCloud
        )
        let model = AppModel(
            launchOptions: HarnessLaunchOptions(
                platformTarget: .macos,
                deviceClass: .mac
            ),
            userDefaults: defaults,
            sharedConfigurationStore: MockSharedAppConfigurationStore(isAvailable: true),
            appleCalendarService: MockAppleCalendarService(
                authorizationState: .granted,
                calendars: [iCloud],
                createdEvent: nil
            ),
            bookingSecretStore: MockBookingSecretStore(secrets: nil, adminToken: nil),
            googleAccountStore: MockGoogleAccountStore()
        )

        XCTAssertEqual(model.bookingApprovalCalendarTargetSummary, "No target calendar selected")

        await model.connectAppleCalendar()

        XCTAssertEqual(model.bookingApprovalCalendarTargetSummary, "Apple / iCloud: Matt - iCloud • iCloud")
        XCTAssertTrue(model.bookingApprovalCalendarDetail.contains("Accepted bookings are added to Matt - iCloud • iCloud"))
    }

    @MainActor
    func testBookingCalendarTargetWarningExplainsSharedGoogleAccountNeedsLocalSignIn() async throws {
        let suiteName = "CalendarBusySyncTests.\(#function)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let sharedStore = MockSharedAppConfigurationStore(
            isAvailable: true,
            initialConfiguration: SharedAppConfiguration(
                updatedAt: Date(timeIntervalSince1970: 20),
                pollIntervalMinutes: 2,
                auditTrailLogLengthRawValue: AuditTrailLogLength.unlimited.rawValue,
                isAppleCalendarEnabled: false,
                selectedAppleCalendarReference: nil,
                usesCustomGoogleOAuthApp: false,
                customGoogleOAuthClientID: "",
                customGoogleOAuthServerClientID: "",
                googleSelectedCalendarIDs: ["shared-google": "primary"],
                activeGoogleAccountID: "shared-google",
                googleAccountDescriptors: [
                    SharedGoogleAccountDescriptor(
                        id: "shared-google",
                        email: "shared@example.com",
                        displayName: "Shared Google",
                        usesCustomOAuthApp: false,
                        selectedCalendarID: "primary",
                        selectedCalendarDisplayName: "Primary"
                    )
                ]
            )
        )
        let model = AppModel(
            launchOptions: HarnessLaunchOptions(
                platformTarget: .macos,
                deviceClass: .mac
            ),
            userDefaults: defaults,
            sharedConfigurationStore: sharedStore,
            appleCalendarService: MockAppleCalendarService(
                authorizationState: .granted,
                calendars: [],
                createdEvent: nil
            ),
            bookingSecretStore: MockBookingSecretStore(secrets: nil, adminToken: nil),
            googleAccountStore: MockGoogleAccountStore(),
            googleSignInEnvironment: GoogleSignInEnvironment(
                blockingReason: "Google Sign-In on macOS requires a signed app build."
            )
        )

        await model.prepareIfNeeded()

        let warning = try XCTUnwrap(model.bookingCalendarTargetWarning)
        XCTAssertTrue(warning.contains("A shared Google calendar is configured"))
        XCTAssertTrue(warning.contains("this Mac still needs local Google sign-in"))
        XCTAssertTrue(warning.contains("Google Sign-In on macOS requires a signed app build."))
    }

    @MainActor
    func testBookingImportAutomaticallyApprovesWhenAppointmentTypeEnabled() async throws {
        let suiteName = "CalendarBusySyncTests.\(#function)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let secrets = BookingLocalSecrets.generate()
        let secretStore = MockBookingSecretStore(
            secrets: secrets,
            adminToken: "admin-token"
        )
        let appleCalendar = AppleCalendarSummary(
            id: "apple-calendar",
            title: "Consulting",
            sourceTitle: "iCloud",
            sourceKind: .iCloud
        )
        let appleService = MockAppleCalendarService(
            authorizationState: .granted,
            calendars: [appleCalendar],
            createdEvent: nil
        )
        let inviteFileWriter = MockBookingInviteFileWriter(
            inviteFileURL: URL(fileURLWithPath: "/tmp/booking-request-auto-1.ics")
        )
        let model = AppModel(
            launchOptions: HarnessLaunchOptions(
                platformTarget: .macos,
                deviceClass: .mac
            ),
            userDefaults: defaults,
            sharedConfigurationStore: MockSharedAppConfigurationStore(isAvailable: true),
            appleCalendarService: appleService,
            bookingSecretStore: secretStore,
            bookingInviteFileWriter: inviteFileWriter,
            googleAccountStore: MockGoogleAccountStore()
        )
        model.bookingInboxURLString = "https://relay.example.com"
        var appointmentType = try XCTUnwrap(model.bookingAppointmentTypes.first)
        appointmentType.isAutoConfirmEnabled = true
        model.updateBookingAppointmentType(appointmentType)
        await model.connectAppleCalendar()

        let now = Date()
        let slotStart = now.addingTimeInterval(60 * 60)
        let claim = BookingSlotClaim(
            appointmentTypeID: AppointmentTypeID("intro-call"),
            slotID: BookingSlotID("intro-call-\(Int(slotStart.timeIntervalSince1970))"),
            startsAt: slotStart,
            endsAt: slotStart.addingTimeInterval(30 * 60),
            generatedAt: now,
            expiresAt: slotStart,
            nonce: "nonce",
            signingKeyVersion: "v1"
        )
        let token = try secrets.slotSigner.sign(claim)
        let envelope = try BookingTestRequestSender.encrypt(
            plaintext: BookingTestRequestPlaintext(
                requestID: BookingRequestID("request-auto-1"),
                appointmentTypeID: claim.appointmentTypeID,
                slotID: claim.slotID,
                slotToken: token,
                visitor: BookingTestVisitor(
                    name: "Matt Moore",
                    email: "matt@alumni.ucsd.edu",
                    topic: "A 30 minute meeting",
                    guestEmails: []
                ),
                browserTimeZone: "America/Los_Angeles",
                createdAt: now
            ),
            slot: BookingPublishedSlot(
                id: claim.slotID,
                appointmentTypeID: claim.appointmentTypeID,
                startsAt: claim.startsAt,
                endsAt: claim.endsAt,
                expiresAt: claim.expiresAt,
                token: token
            ),
            config: BookingPublishedSiteConfig(
                share: BookingPublishedShare(id: BookingShareID("intro-call")),
                inbox: BookingPublishedInbox(
                    id: secrets.inboxID,
                    url: try XCTUnwrap(URL(string: "https://relay.example.com"))
                ),
                encryption: BookingPublishedEncryption(
                    keyID: secrets.keyID,
                    publicKeyJWK: BookingKeyMaterial.publicKey(
                        from: try secrets.privateKey,
                        keyID: secrets.keyID
                    ).jwk
                )
            ),
            createdAt: now
        )

        let responseEncoder = JSONEncoder()
        responseEncoder.dateEncodingStrategy = .iso8601
        let listPayload = try responseEncoder.encode(BookingRelayRequestPage(
            requests: [envelope],
            cursor: nil
        ))
        RelayURLProtocol.responders = [
            "GET /v1/inboxes/\(secrets.inboxID.rawValue)/requests": { request in
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer admin-token")
                return (200, listPayload)
            },
            "DELETE /v1/inboxes/\(secrets.inboxID.rawValue)/requests/request-auto-1": { request in
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer admin-token")
                return (204, Data())
            },
        ]
        URLProtocol.registerClass(RelayURLProtocol.self)
        defer {
            URLProtocol.unregisterClass(RelayURLProtocol.self)
            RelayURLProtocol.responders = [:]
            RelayURLProtocol.seenRequests = []
        }

        await model.importBookingRequests()

        let imported = try XCTUnwrap(model.importedBookingRequests.first)
        XCTAssertEqual(imported.status, .approved)
        XCTAssertEqual(appleService.createdBookingRequests.map(\.id), [imported.id])
        XCTAssertEqual(inviteFileWriter.writtenRequests.map(\.id), [imported.id])
        XCTAssertTrue(model.activeBookingRequests.isEmpty)
        XCTAssertTrue(model.bookingSetupSnapshot.lastMessage?.contains("automatically accepted 1") ?? false)
        XCTAssertTrue(RelayURLProtocol.seenRequests.contains("DELETE /v1/inboxes/\(secrets.inboxID.rawValue)/requests/request-auto-1"))
    }

    @MainActor
    func testBookingDeclineWritesAppleDeclineICSAndDeletesRelayRecord() async throws {
        let suiteName = "CalendarBusySyncTests.\(#function)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let secrets = BookingLocalSecrets.generate()
        let secretStore = MockBookingSecretStore(
            secrets: secrets,
            adminToken: "admin-token"
        )
        let appleCalendar = AppleCalendarSummary(
            id: "apple-calendar",
            title: "Consulting",
            sourceTitle: "iCloud",
            sourceKind: .iCloud
        )
        let appleService = MockAppleCalendarService(
            authorizationState: .granted,
            calendars: [appleCalendar],
            createdEvent: nil
        )
        let inviteFileWriter = MockBookingInviteFileWriter(
            inviteFileURL: URL(fileURLWithPath: "/tmp/booking-request-decline-1.ics")
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
            sharedConfigurationStore: MockSharedAppConfigurationStore(isAvailable: true),
            appleCalendarService: appleService,
            bookingSecretStore: secretStore,
            bookingInviteFileWriter: inviteFileWriter,
            googleAccountStore: MockGoogleAccountStore()
        )
        model.bookingInboxURLString = "https://relay.example.com"
        await model.connectAppleCalendar()

        let now = Date()
        let slotStart = now.addingTimeInterval(60 * 60)
        let claim = BookingSlotClaim(
            appointmentTypeID: AppointmentTypeID("intro-call"),
            slotID: BookingSlotID("intro-call-\(Int(slotStart.timeIntervalSince1970))"),
            startsAt: slotStart,
            endsAt: slotStart.addingTimeInterval(30 * 60),
            generatedAt: now,
            expiresAt: slotStart,
            nonce: "nonce",
            signingKeyVersion: "v1"
        )
        let token = try secrets.slotSigner.sign(claim)
        let envelope = try BookingTestRequestSender.encrypt(
            plaintext: BookingTestRequestPlaintext(
                requestID: BookingRequestID("request-decline-1"),
                appointmentTypeID: claim.appointmentTypeID,
                slotID: claim.slotID,
                slotToken: token,
                visitor: BookingTestVisitor(
                    name: "Matt Moore",
                    email: "matt@alumni.ucsd.edu",
                    topic: "A 30 minute meeting",
                    guestEmails: ["guest@example.com"]
                ),
                browserTimeZone: "America/Los_Angeles",
                createdAt: now
            ),
            slot: BookingPublishedSlot(
                id: claim.slotID,
                appointmentTypeID: claim.appointmentTypeID,
                startsAt: claim.startsAt,
                endsAt: claim.endsAt,
                expiresAt: claim.expiresAt,
                token: token
            ),
            config: BookingPublishedSiteConfig(
                share: BookingPublishedShare(id: BookingShareID("intro-call")),
                inbox: BookingPublishedInbox(
                    id: secrets.inboxID,
                    url: try XCTUnwrap(URL(string: "https://relay.example.com"))
                ),
                encryption: BookingPublishedEncryption(
                    keyID: secrets.keyID,
                    publicKeyJWK: BookingKeyMaterial.publicKey(
                        from: try secrets.privateKey,
                        keyID: secrets.keyID
                    ).jwk
                )
            ),
            createdAt: now
        )

        let responseEncoder = JSONEncoder()
        responseEncoder.dateEncodingStrategy = .iso8601
        let listPayload = try responseEncoder.encode(BookingRelayRequestPage(
            requests: [envelope],
            cursor: nil
        ))
        RelayURLProtocol.responders = [
            "GET /v1/inboxes/\(secrets.inboxID.rawValue)/requests": { request in
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer admin-token")
                return (200, listPayload)
            },
            "DELETE /v1/inboxes/\(secrets.inboxID.rawValue)/requests/request-decline-1": { request in
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer admin-token")
                return (204, Data())
            },
        ]
        URLProtocol.registerClass(RelayURLProtocol.self)
        defer {
            URLProtocol.unregisterClass(RelayURLProtocol.self)
            RelayURLProtocol.responders = [:]
            RelayURLProtocol.seenRequests = []
        }

        await model.importBookingRequests()
        let imported = try XCTUnwrap(model.importedBookingRequests.first)

        await model.declineBookingRequest(imported.id)

        XCTAssertTrue(appleService.createdBookingRequests.isEmpty)
        XCTAssertTrue(inviteFileWriter.writtenRequests.isEmpty)
        XCTAssertEqual(inviteFileWriter.writtenDeclines.map(\.id), [imported.id])
        XCTAssertEqual(inviteFileWriter.writtenDeclines.first?.inviteeEmails, ["matt@alumni.ucsd.edu", "guest@example.com"])
        XCTAssertEqual(model.importedBookingRequests.first?.status, .declined)
        XCTAssertTrue(model.importedBookingRequests.first?.message.contains("booking-request-decline-1.ics") ?? false)
        XCTAssertTrue(model.activeBookingRequests.isEmpty)
        XCTAssertEqual(model.bookingRequestHistory.map(\.id), [imported.id])
        XCTAssertTrue(RelayURLProtocol.seenRequests.contains("DELETE /v1/inboxes/\(secrets.inboxID.rawValue)/requests/request-decline-1"))
    }

    func testGoogleBookingEventWritesAttendeeInvites() async throws {
        let request = makeCalendarTestImportedBookingRequest(
            guestEmails: [
                "guest@example.com",
                "matt@alumni.ucsd.edu",
            ]
        )
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [GoogleCalendarURLProtocol.self]
        let session = URLSession(configuration: config)
        GoogleCalendarURLProtocol.seenRequests = []
        GoogleCalendarURLProtocol.responder = { urlRequest in
            XCTAssertEqual(urlRequest.httpMethod, "POST")
            XCTAssertEqual(urlRequest.url?.path, "/calendar/v3/calendars/primary/events")
            XCTAssertEqual(urlRequest.url?.query, "sendUpdates=all&conferenceDataVersion=1")
            XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
            let body = try XCTUnwrap(urlRequest.httpBody)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let description = try XCTUnwrap(json["description"] as? String)
            XCTAssertTrue(description.contains("Notes: A 30 minute meeting"))
            let attendees = try XCTUnwrap(json["attendees"] as? [[String: Any]])
            XCTAssertEqual(attendees.compactMap { $0["email"] as? String }, ["matt@alumni.ucsd.edu", "guest@example.com"])
            let conferenceData = try XCTUnwrap(json["conferenceData"] as? [String: Any])
            let createRequest = try XCTUnwrap(conferenceData["createRequest"] as? [String: Any])
            let solutionKey = try XCTUnwrap(createRequest["conferenceSolutionKey"] as? [String: Any])
            XCTAssertEqual(solutionKey["type"] as? String, "hangoutsMeet")
            return (200, Data(#"{"id":"google-booking-1","summary":"Meeting with Matt Moore"}"#.utf8))
        }
        defer {
            GoogleCalendarURLProtocol.responder = nil
            GoogleCalendarURLProtocol.seenRequests = []
        }

        let service = GoogleCalendarService(session: session)
        let event = try await service.createBookingEvent(
            in: GoogleCalendarSummary(
                id: "primary",
                summary: "Matt Google",
                accessRole: .owner,
                primary: true,
                timeZone: "America/Los_Angeles"
            ),
            accessToken: "access-token",
            request: request,
            createsGoogleMeet: true
        )

        XCTAssertEqual(event.eventID, "google-booking-1")
        XCTAssertEqual(GoogleCalendarURLProtocol.seenRequests, ["POST /calendar/v3/calendars/primary/events"])
    }

    func testGoogleDeclinedBookingEventMarksOwnerDeclinedAndNotifiesInvitees() async throws {
        let request = makeCalendarTestImportedBookingRequest(
            guestEmails: ["guest@example.com", "owner@example.com"]
        )
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [GoogleCalendarURLProtocol.self]
        let session = URLSession(configuration: config)
        GoogleCalendarURLProtocol.seenRequests = []
        GoogleCalendarURLProtocol.responder = { urlRequest in
            XCTAssertEqual(urlRequest.httpMethod, "POST")
            XCTAssertEqual(urlRequest.url?.path, "/calendar/v3/calendars/primary/events")
            XCTAssertEqual(urlRequest.url?.query, "sendUpdates=all")
            let body = try XCTUnwrap(urlRequest.httpBody)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["transparency"] as? String, "transparent")
            XCTAssertEqual(json["summary"] as? String, "Declined: Meeting with Matt Moore")
            let attendees = try XCTUnwrap(json["attendees"] as? [[String: Any]])
            XCTAssertEqual(attendees.compactMap { $0["email"] as? String }, [
                "owner@example.com",
                "matt@alumni.ucsd.edu",
                "guest@example.com",
            ])
            XCTAssertEqual(attendees.first?["responseStatus"] as? String, "declined")
            return (200, Data(#"{"id":"google-decline-1","summary":"Declined: Meeting with Matt Moore"}"#.utf8))
        }
        defer {
            GoogleCalendarURLProtocol.responder = nil
            GoogleCalendarURLProtocol.seenRequests = []
        }

        let service = GoogleCalendarService(session: session)
        let event = try await service.createDeclinedBookingEvent(
            in: GoogleCalendarSummary(
                id: "primary",
                summary: "Matt Google",
                accessRole: .owner,
                primary: true,
                timeZone: "America/Los_Angeles"
            ),
            accessToken: "access-token",
            request: request,
            ownerEmail: "owner@example.com"
        )

        XCTAssertEqual(event.eventID, "google-decline-1")
        XCTAssertEqual(GoogleCalendarURLProtocol.seenRequests, ["POST /calendar/v3/calendars/primary/events"])
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
            existingMirrors: existingMirrors,
            existingBusyBlocks: []
        )

        XCTAssertEqual(operations.count, 3)
        XCTAssertEqual(operations.filterCreate.count, 1)
        XCTAssertEqual(operations.filterUpdate.count, 1)
        XCTAssertEqual(operations.filterDelete.count, 1)
    }

    func testBusyMirrorSyncPlannerCollapsesSameSlotDesiredMirrorsIntoSingleOperation() {
        let alpha = testParticipant(provider: .apple, calendarID: "alpha", displayName: "Alpha")
        let beta = testParticipant(provider: .google, accountID: "acct-beta", calendarID: "beta", displayName: "Beta")
        let start = testDate(hour: 9)
        let end = testDate(hour: 10)

        let duplicateSlotMirrors = [
            DesiredBusyMirrorEvent(
                identity: BusyMirrorIdentity(
                    sourceKey: BusyMirrorSourceKey(provider: .apple, calendarID: "alpha", eventID: "alpha-source"),
                    targetParticipantID: beta.id
                ),
                targetParticipant: beta,
                startDate: start,
                endDate: end,
                isAllDay: false
            ),
            DesiredBusyMirrorEvent(
                identity: BusyMirrorIdentity(
                    sourceKey: BusyMirrorSourceKey(provider: .google, calendarID: "gamma", eventID: "gamma-source"),
                    targetParticipantID: beta.id
                ),
                targetParticipant: beta,
                startDate: start,
                endDate: end,
                isAllDay: false
            ),
        ]

        let operations = BusyMirrorSyncPlanner.operations(
            desiredMirrors: duplicateSlotMirrors,
            existingMirrors: [],
            existingBusyBlocks: []
        )

        XCTAssertEqual(operations.count, 1)
        XCTAssertEqual(operations.filterCreate.count, 1)

        guard case let .create(desiredMirror) = operations[0] else {
            return XCTFail("Expected one create operation for the canonical mirror.")
        }

        XCTAssertEqual(desiredMirror.targetParticipant.id, beta.id)
        XCTAssertEqual(desiredMirror.startDate, start)
        XCTAssertEqual(desiredMirror.endDate, end)
    }

    func testBusyMirrorSyncPlannerSuppressesCreateWhenExactBusySlotAlreadyExists() {
        let beta = testParticipant(provider: .google, accountID: "acct-beta", calendarID: "beta", displayName: "Beta")
        let start = testDate(hour: 9)
        let end = testDate(hour: 10)
        let desiredMirror = DesiredBusyMirrorEvent(
            identity: BusyMirrorIdentity(
                sourceKey: BusyMirrorSourceKey(provider: .apple, calendarID: "alpha", eventID: "alpha-source"),
                targetParticipantID: beta.id
            ),
            targetParticipant: beta,
            startDate: start,
            endDate: end,
            isAllDay: false
        )

        let operations = BusyMirrorSyncPlanner.operations(
            desiredMirrors: [desiredMirror],
            existingMirrors: [],
            existingBusyBlocks: [
                BusyMirrorTargetBusyBlock(
                    targetParticipant: beta,
                    eventID: "manual-busy",
                    startDate: start,
                    endDate: end,
                    isAllDay: false,
                    managedMirrorIdentity: nil
                )
            ]
        )

        XCTAssertTrue(operations.isEmpty)
    }

    func testBusyMirrorSyncPlannerDeletesRedundantManagedMirrorWhenExactBusySlotAlreadyExists() {
        let beta = testParticipant(provider: .google, accountID: "acct-beta", calendarID: "beta", displayName: "Beta")
        let start = testDate(hour: 9)
        let end = testDate(hour: 10)
        let existingMirror = ExistingBusyMirrorEvent(
            identity: BusyMirrorIdentity(
                sourceKey: BusyMirrorSourceKey(provider: .apple, calendarID: "alpha", eventID: "alpha-source"),
                targetParticipantID: beta.id
            ),
            targetParticipant: beta,
            eventID: "managed-mirror",
            startDate: start,
            endDate: end,
            isAllDay: false
        )

        let operations = BusyMirrorSyncPlanner.operations(
            desiredMirrors: [
                DesiredBusyMirrorEvent(
                    identity: existingMirror.identity,
                    targetParticipant: beta,
                    startDate: start,
                    endDate: end,
                    isAllDay: false
                )
            ],
            existingMirrors: [existingMirror],
            existingBusyBlocks: [
                BusyMirrorTargetBusyBlock(
                    targetParticipant: beta,
                    eventID: existingMirror.eventID,
                    startDate: start,
                    endDate: end,
                    isAllDay: false,
                    managedMirrorIdentity: existingMirror.identity
                ),
                BusyMirrorTargetBusyBlock(
                    targetParticipant: beta,
                    eventID: "manual-busy",
                    startDate: start,
                    endDate: end,
                    isAllDay: false,
                    managedMirrorIdentity: nil
                )
            ]
        )

        XCTAssertEqual(operations.count, 1)
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

@MainActor
private final class MockMacApplicationController: MacApplicationControlling {
    private(set) var activationCalls = 0
    private(set) var dockVisibilityCalls: [Bool] = []
    private(set) var broughtForwardSceneIDs: [String] = []

    func activate(ignoringOtherApps: Bool) {
        activationCalls += 1
    }

    func setDockVisible(_ isVisible: Bool) {
        dockVisibilityCalls.append(isVisible)
    }

    func bringWindowToFront(sceneID: String) {
        broughtForwardSceneIDs.append(sceneID)
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
    var busyTargetBlocks: [BusyMirrorTargetBusyBlock] = []
    var createdBookingRequests: [BookingImportedRequest] = []
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

    func listBusyTargetBlocks(in participant: BusyMirrorParticipant, window: DateInterval) throws -> [BusyMirrorTargetBusyBlock] {
        busyTargetBlocks.filter { $0.targetParticipant.id == participant.id }
    }

    func createBookingEvent(in calendar: AppleCalendarSummary, request: BookingImportedRequest) throws -> AppleManagedEventRecord {
        createdBookingRequests.append(request)
        return AppleManagedEventRecord(
            calendarID: calendar.id,
            calendarName: calendar.displayName,
            eventID: "booking-\(request.id.rawValue)",
            summary: "Meeting with \(request.visitorDisplayName)",
            windowDescription: "Booking window"
        )
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

private final class MockBookingSecretStore: BookingSecretStoring {
    var secrets: BookingLocalSecrets?
    var adminToken: String?
    var githubDeployKeyPrivateKey: String?
    var didDeleteLegacyGitHubToken = false

    init(secrets: BookingLocalSecrets?, adminToken: String?) {
        self.secrets = secrets
        self.adminToken = adminToken
    }

    func loadSecrets() throws -> BookingLocalSecrets? {
        secrets
    }

    func saveSecrets(_ secrets: BookingLocalSecrets) throws {
        self.secrets = secrets
    }

    func loadAdminToken() throws -> String? {
        adminToken
    }

    func saveAdminToken(_ token: String) throws {
        adminToken = token
    }

    func loadGitHubDeployKeyPrivateKey() throws -> String? {
        githubDeployKeyPrivateKey
    }

    func saveGitHubDeployKeyPrivateKey(_ privateKey: String) throws {
        githubDeployKeyPrivateKey = privateKey
    }

    func deleteLegacyGitHubToken() throws {
        didDeleteLegacyGitHubToken = true
    }
}

private final class MockBookingInviteFileWriter: BookingInviteFileWriting {
    let inviteFileURL: URL
    var writtenRequests: [BookingImportedRequest] = []
    var writtenDeclines: [BookingImportedRequest] = []

    init(inviteFileURL: URL) {
        self.inviteFileURL = inviteFileURL
    }

    func writeInviteFile(for request: BookingImportedRequest, calendarName: String) throws -> URL {
        writtenRequests.append(request)
        return inviteFileURL
    }

    func writeDeclineFile(for request: BookingImportedRequest, calendarName: String) throws -> URL {
        writtenDeclines.append(request)
        return inviteFileURL
    }
}

private func makeCalendarTestImportedBookingRequest(guestEmails: [String] = []) -> BookingImportedRequest {
    let now = Date(timeIntervalSince1970: 1_767_225_600)
    let slotStart = Date(timeIntervalSince1970: 1_767_258_000)
    let requestID = BookingRequestID("request-google-1")
    let claim = BookingSlotClaim(
        appointmentTypeID: AppointmentTypeID("intro-call"),
        slotID: BookingSlotID("intro-call-1767258000"),
        startsAt: slotStart,
        endsAt: slotStart.addingTimeInterval(30 * 60),
        generatedAt: now,
        expiresAt: slotStart,
        nonce: "nonce",
        signingKeyVersion: "v1"
    )
    return BookingImportedRequest(
        id: requestID,
        envelope: EncryptedBookingRequestEnvelope(
            schemaVersion: 1,
            requestID: requestID,
            inboxID: BookingInboxID("inbox-123"),
            shareID: BookingShareID("intro-call"),
            createdAt: now,
            expiresAt: slotStart,
            keyID: "key-v1",
            algorithm: "P256.ECDH-ES+A256GCM",
            ephemeralPublicKeyJWK: nil,
            nonce: "nonce",
            ciphertext: "ciphertext"
        ),
        plaintext: BookingRequestPlaintext(
            requestID: requestID,
            appointmentTypeID: claim.appointmentTypeID,
            slotID: claim.slotID,
            slotToken: SignedBookingSlotToken("slot-token"),
            visitor: BookingRequestVisitor(
                name: "Matt Moore",
                email: "matt@alumni.ucsd.edu",
                topic: "A 30 minute meeting",
                guestEmails: guestEmails
            ),
            browserTimeZone: "America/Los_Angeles",
            createdAt: now
        ),
        slotClaim: claim,
        importedAt: now,
        status: .pendingReview,
        message: BookingCopy.Validation.slotStillOpen,
        calendarEventID: nil
    )
}

private final class RelayURLProtocol: URLProtocol {
    typealias Responder = (URLRequest) throws -> (statusCode: Int, data: Data)

    static var responders: [String: Responder] = [:]
    static var seenRequests: [String] = []

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "relay.example.com"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let key = "\(request.httpMethod ?? "GET") \(request.url?.path ?? "")"
        Self.seenRequests.append(key)

        guard let responder = Self.responders[key], let url = request.url else {
            client?.urlProtocol(
                self,
                didFailWithError: URLError(.unsupportedURL)
            )
            return
        }

        do {
            var responderRequest = request
            if responderRequest.httpBody == nil, let stream = request.httpBodyStream {
                responderRequest.httpBody = Data(inputStream: stream)
            }
            let responsePayload = try responder(responderRequest)
            let response = HTTPURLResponse(
                url: url,
                statusCode: responsePayload.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: responsePayload.data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class GoogleCalendarURLProtocol: URLProtocol {
    typealias Responder = (URLRequest) throws -> (statusCode: Int, data: Data)

    static var responder: Responder?
    static var seenRequests: [String] = []

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "www.googleapis.com"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let key = "\(request.httpMethod ?? "GET") \(request.url?.path ?? "")"
        Self.seenRequests.append(key)

        guard let responder = Self.responder, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }

        do {
            var responderRequest = request
            if responderRequest.httpBody == nil, let stream = request.httpBodyStream {
                responderRequest.httpBody = Data(inputStream: stream)
            }
            let responsePayload = try responder(responderRequest)
            let response = HTTPURLResponse(
                url: url,
                statusCode: responsePayload.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: responsePayload.data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private extension Data {
    init(inputStream: InputStream) {
        self.init()
        inputStream.open()
        defer { inputStream.close() }

        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while inputStream.hasBytesAvailable {
            let count = inputStream.read(buffer, maxLength: bufferSize)
            guard count > 0 else {
                break
            }
            append(buffer, count: count)
        }
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

private final class MockSharedAppConfigurationStore: SharedAppConfigurationStoring {
    let isAvailable: Bool
    private var configuration: SharedAppConfiguration?
    private var onChange: (@MainActor (SharedAppConfiguration) -> Void)?
    private(set) var loadCallCount = 0
    private(set) var saveCallCount = 0
    private(set) var requestSyncCallCount = 0
    var requestSyncResult = true

    init(
        isAvailable: Bool,
        initialConfiguration: SharedAppConfiguration? = nil
    ) {
        self.isAvailable = isAvailable
        self.configuration = initialConfiguration
    }

    func loadConfiguration() -> SharedAppConfiguration? {
        loadCallCount += 1
        return configuration
    }

    func saveConfiguration(_ configuration: SharedAppConfiguration) {
        saveCallCount += 1
        self.configuration = configuration
    }

    func setConfiguration(_ configuration: SharedAppConfiguration?) {
        self.configuration = configuration
    }

    func startObserving(_ onChange: @escaping @MainActor (SharedAppConfiguration) -> Void) {
        self.onChange = onChange
    }

    @discardableResult
    func requestSync() -> Bool {
        requestSyncCallCount += 1
        return requestSyncResult
    }

    @MainActor
    func emit(_ configuration: SharedAppConfiguration) {
        self.configuration = configuration
        onChange?(configuration)
    }
}

private final class MockIOSBackgroundRefreshScheduler: IOSBackgroundRefreshScheduling {
    let availability: IOSBackgroundRefreshAvailability
    private(set) var submissions: [(identifier: String, earliestBeginDate: Date)] = []
    private(set) var cancelledIdentifiers: [String] = []

    init(availability: IOSBackgroundRefreshAvailability) {
        self.availability = availability
    }

    func submitAppRefresh(identifier: String, earliestBeginDate: Date) throws {
        submissions.append((identifier: identifier, earliestBeginDate: earliestBeginDate))
    }

    func cancelAppRefresh(identifier: String) {
        cancelledIdentifiers.append(identifier)
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
