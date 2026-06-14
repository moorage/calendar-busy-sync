import XCTest
import CryptoKit
@testable import Calendar_Busy_Sync

final class BookingTests: XCTestCase {
    func testAppointmentMarkdownParsesPublicConfig() throws {
        let appointmentType = try BookingAppointmentMarkdownParser.parse(
            """
            ---
            slug: intro-call
            name: Intro call
            duration_minutes: 30
            availability_horizon_days: 30
            minimum_notice_minutes: 1440
            buffer_before_minutes: 10
            buffer_after_minutes: 10
            weekly_hours: mon=09:00-16:30;tue=09:00-16:30|18:00-19:00;fri=closed
            location: google_meet
            questions: name=text,email=email,topic=long_text
            ---
            A short first conversation.
            """
        )

        XCTAssertEqual(appointmentType.id, AppointmentTypeID("intro-call"))
        XCTAssertEqual(appointmentType.slug, "intro-call")
        XCTAssertEqual(appointmentType.durationMinutes, 30)
        XCTAssertEqual(appointmentType.availabilityHorizonDays, 30)
        XCTAssertEqual(appointmentType.bufferBeforeMinutes, 10)
        XCTAssertEqual(appointmentType.location.mode, .googleMeet)
        XCTAssertEqual(appointmentType.summary, "A short first conversation.")
        XCTAssertEqual(
            appointmentType.weeklyHours,
            [
                BookingWeeklyHours(
                    weekday: 2,
                    windows: [BookingWorkingHours(startMinuteOfDay: 9 * 60, endMinuteOfDay: 16 * 60 + 30)]
                ),
                BookingWeeklyHours(
                    weekday: 3,
                    windows: [
                        BookingWorkingHours(startMinuteOfDay: 9 * 60, endMinuteOfDay: 16 * 60 + 30),
                        BookingWorkingHours(startMinuteOfDay: 18 * 60, endMinuteOfDay: 19 * 60),
                    ]
                ),
                BookingWeeklyHours(weekday: 6, windows: []),
            ]
        )
        XCTAssertEqual(appointmentType.questions.map(\.type), [.text, .email, .longText])
    }

    func testWeeklyHoursCodecRoundTripsEditorFormat() throws {
        let weeklyHours = try BookingWeeklyHoursCodec.parse("mon=09:00-16:30;tue=09:00-12:00|13:00-16:30;fri=closed")

        XCTAssertEqual(
            BookingWeeklyHoursCodec.serialize(weeklyHours),
            "mon=09:00-16:30;tue=09:00-12:00|13:00-16:30;fri=closed"
        )
    }

    func testAppointmentMarkdownRejectsSecretLookingFrontMatter() {
        XCTAssertThrowsError(
            try BookingAppointmentMarkdownParser.parse(
                """
                ---
                slug: intro-call
                name: Intro call
                duration_minutes: 30
                refresh_token: secret-value
                ---
                Do not publish this.
                """
            )
        ) { error in
            XCTAssertEqual(
                (error as? BookingConfigurationError)?.localizedDescription,
                "This field looks like a secret. Remove it before publishing."
            )
        }
    }

    func testAppointmentValidationRejectsDuplicateSlugs() throws {
        let first = try BookingAppointmentMarkdownParser.parse(
            """
            ---
            slug: intro-call
            name: Intro call
            duration_minutes: 30
            ---
            First.
            """
        )
        let second = BookingAppointmentType(
            id: AppointmentTypeID("another"),
            slug: first.slug,
            name: "Another",
            summary: "Another call.",
            durationMinutes: 45,
            minimumNoticeMinutes: 60,
            bufferBeforeMinutes: 0,
            bufferAfterMinutes: 0,
            weeklyHours: BookingWeeklyHours.weekdayDefault,
            isAutoConfirmEnabled: false,
            questions: []
        )

        XCTAssertThrowsError(try BookingConfigurationValidator.validateAppointmentTypes([first, second])) { error in
            XCTAssertEqual((error as? BookingConfigurationError)?.localizedDescription, "Another appointment type already uses intro-call.")
        }
    }

    func testAppointmentValidationRejectsAvailabilityHorizonOverThreeMonths() throws {
        var appointmentType = BookingDraftFactory.defaultAppointmentTypes[0]
        appointmentType.availabilityHorizonDays = BookingAppointmentType.maximumAvailabilityHorizonDays + 1

        XCTAssertThrowsError(try BookingConfigurationValidator.validateAppointmentTypes([appointmentType])) { error in
            XCTAssertEqual(
                (error as? BookingConfigurationError)?.localizedDescription,
                "Availability can be shown for at most 3 months."
            )
        }
    }

    func testAppointmentSlugValidationReportsTooShortLinkName() {
        XCTAssertThrowsError(try BookingIdentifierValidator.validateSlug("ab", fieldName: BookingCopy.Field.linkName)) { error in
            XCTAssertEqual(
                (error as? BookingConfigurationError)?.localizedDescription,
                "Link name must be at least 3 characters."
            )
        }
    }

    func testSlotSignerRoundTripsAndRejectsTampering() throws {
        let signer = try BookingSlotSigner(secret: Data(repeating: 7, count: 32))
        let claim = BookingSlotClaim(
            appointmentTypeID: AppointmentTypeID("intro-call"),
            slotID: BookingSlotID("intro-call-1767229200"),
            startsAt: Date(timeIntervalSince1970: 1_767_229_200),
            endsAt: Date(timeIntervalSince1970: 1_767_231_000),
            generatedAt: Date(timeIntervalSince1970: 1_767_142_800),
            expiresAt: Date(timeIntervalSince1970: 1_767_229_200),
            nonce: "nonce",
            signingKeyVersion: "v1"
        )

        let token = try signer.sign(claim)

        XCTAssertEqual(try signer.verifiedClaim(from: token), claim)
        XCTAssertThrowsError(
            try signer.verifiedClaim(from: SignedBookingSlotToken(token.rawValue + "a"))
        )
    }

    func testAvailabilityCompilerSuppressesBusyIntervals() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let appointmentType = BookingAppointmentType(
            id: AppointmentTypeID("intro-call"),
            slug: "intro-call",
            name: "Intro call",
            summary: "A short first conversation.",
            durationMinutes: 30,
            minimumNoticeMinutes: 0,
            bufferBeforeMinutes: 0,
            bufferAfterMinutes: 0,
            weeklyHours: BookingWeeklyHours.weekdayDefault,
            isAutoConfirmEnabled: false,
            questions: []
        )
        let busyStart = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 9, minute: 30))!
        let busyEnd = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 10))!

        let slots = try BookingAvailabilityCompiler.openSlots(
            on: day,
            appointmentType: appointmentType,
            workingHours: BookingWorkingHours(startMinuteOfDay: 9 * 60, endMinuteOfDay: 10 * 60),
            busyIntervals: [BookingBusyInterval(interval: DateInterval(start: busyStart, end: busyEnd))],
            calendar: calendar,
            generatedAt: day
        ) { claim in
            SignedBookingSlotToken(claim.slotID.rawValue)
        }

        XCTAssertEqual(slots.map(\.id.rawValue), ["intro-call-1767258000"])
    }

    func testAvailabilityCompilerRoundsMinimumNoticeToStandardSlotStep() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let generatedAt = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 8, minute: 7, second: 12))!
        let appointmentType = BookingAppointmentType(
            id: AppointmentTypeID("intro-call"),
            slug: "intro-call",
            name: "Intro call",
            summary: "A short first conversation.",
            durationMinutes: 30,
            minimumNoticeMinutes: 60,
            bufferBeforeMinutes: 0,
            bufferAfterMinutes: 0,
            weeklyHours: BookingWeeklyHours.weekdayDefault,
            isAutoConfirmEnabled: false,
            questions: []
        )

        let slots = try BookingAvailabilityCompiler.openSlots(
            on: day,
            appointmentType: appointmentType,
            workingHours: BookingWorkingHours(startMinuteOfDay: 9 * 60, endMinuteOfDay: 10 * 60),
            busyIntervals: [],
            calendar: calendar,
            generatedAt: generatedAt
        ) { claim in
            SignedBookingSlotToken(claim.slotID.rawValue)
        }

        XCTAssertEqual(calendar.component(.minute, from: try XCTUnwrap(slots.first?.interval.start)), 15)
        XCTAssertEqual(slots.map { calendar.component(.minute, from: $0.interval.start) }, [15, 30])
    }

    func testAvailabilityCompilerAppliesAppointmentBuffersToBusyIntervals() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let appointmentType = BookingAppointmentType(
            id: AppointmentTypeID("intro-call"),
            slug: "intro-call",
            name: "Intro call",
            summary: "A short first conversation.",
            durationMinutes: 30,
            minimumNoticeMinutes: 0,
            bufferBeforeMinutes: 15,
            bufferAfterMinutes: 0,
            weeklyHours: BookingWeeklyHours.weekdayDefault,
            isAutoConfirmEnabled: false,
            questions: []
        )
        let busyStart = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 9, minute: 30))!
        let busyEnd = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 10))!

        let slots = try BookingAvailabilityCompiler.openSlots(
            on: day,
            appointmentType: appointmentType,
            workingHours: BookingWorkingHours(startMinuteOfDay: 9 * 60, endMinuteOfDay: 10 * 60),
            busyIntervals: [BookingBusyInterval(interval: DateInterval(start: busyStart, end: busyEnd))],
            calendar: calendar,
            generatedAt: day
        ) { claim in
            SignedBookingSlotToken(claim.slotID.rawValue)
        }

        XCTAssertTrue(slots.isEmpty)
    }

    func testDraftFactoryUsesRealBusyIntervalsAcrossPublishedWeekdays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12))!
        let busyStart = calendar.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 9))!
        let busyEnd = calendar.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 17))!

        let draft = try BookingDraftFactory.makeDraft(
            now: now,
            inboxURL: URL(string: "https://inbox.example.com"),
            busyIntervals: [BookingBusyInterval(interval: DateInterval(start: busyStart, end: busyEnd))],
            calendar: calendar
        )

        XCTAssertFalse(draft.slots.isEmpty)
        XCTAssertFalse(draft.slots.contains { calendar.component(.day, from: $0.interval.start) == 2 })
        XCTAssertTrue(draft.slots.contains { calendar.component(.day, from: $0.interval.start) == 5 })
    }

    func testDraftFactoryPublishesSlotsForMultipleActiveAppointmentTypes() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12))!
        let intro = BookingAppointmentType(
            id: AppointmentTypeID("intro-call"),
            slug: "intro-call",
            name: "Intro call",
            summary: "A short conversation.",
            durationMinutes: 45,
            minimumNoticeMinutes: 60,
            bufferBeforeMinutes: 0,
            bufferAfterMinutes: 0,
            weeklyHours: BookingWeeklyHours.weekdayDefault,
            isAutoConfirmEnabled: false,
            questions: []
        )
        let followUp = BookingAppointmentType(
            id: AppointmentTypeID("follow-up"),
            slug: "follow-up",
            name: "Follow-up",
            summary: "A focused follow-up.",
            durationMinutes: 30,
            minimumNoticeMinutes: 60,
            bufferBeforeMinutes: 0,
            bufferAfterMinutes: 0,
            weeklyHours: BookingWeeklyHours.weekdayDefault,
            isAutoConfirmEnabled: false,
            questions: []
        )

        let draft = try BookingDraftFactory.makeDraft(
            now: now,
            inboxURL: URL(string: "https://inbox.example.com"),
            appointmentTypes: [intro, followUp],
            calendar: calendar
        )
        let publishedAppointmentTypeIDs = Set(draft.slots.map(\.appointmentTypeID))

        XCTAssertGreaterThan(draft.slots.count, 40)
        XCTAssertTrue(publishedAppointmentTypeIDs.contains(intro.id))
        XCTAssertTrue(publishedAppointmentTypeIDs.contains(followUp.id))
    }

    func testDraftFactoryUsesPerAppointmentTypeAvailabilityHorizons() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12))!
        var short = BookingDraftFactory.defaultAppointmentTypes[0]
        short.availabilityHorizonDays = 1
        var long = BookingDraftFactory.defaultAppointmentTypes[0]
        long.id = AppointmentTypeID("long-call")
        long.slug = "long-call"
        long.name = "Long call"
        long.availabilityHorizonDays = 30

        let draft = try BookingDraftFactory.makeDraft(
            now: now,
            inboxURL: URL(string: "https://inbox.example.com"),
            appointmentTypes: [short, long],
            calendar: calendar
        )
        let today = calendar.startOfDay(for: now)
        let shortMaxDay = draft.slots
            .filter { $0.appointmentTypeID == short.id }
            .map { calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: $0.interval.start)).day ?? 0 }
            .max()
        let longMaxDay = draft.slots
            .filter { $0.appointmentTypeID == long.id }
            .map { calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: $0.interval.start)).day ?? 0 }
            .max()

        XCTAssertEqual(shortMaxDay, 1)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(longMaxDay), 29)
    }

    func testDraftFactoryBusyLookupWindowUsesLargestActiveAvailabilityHorizon() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12))!
        var short = BookingDraftFactory.defaultAppointmentTypes[0]
        short.availabilityHorizonDays = 7
        var long = BookingDraftFactory.defaultAppointmentTypes[0]
        long.id = AppointmentTypeID("long-call")
        long.slug = "long-call"
        long.availabilityHorizonDays = 90

        let window = BookingDraftFactory.busyLookupWindow(
            startingAt: now,
            appointmentTypes: [short, long],
            calendar: calendar
        )

        XCTAssertEqual(calendar.dateComponents([.day], from: window.start, to: window.end).day, 91)
    }

    func testPublicArtifactAuditorFindsForbiddenValues() {
        let findings = BookingPublicArtifactAuditor.findings(
            in: #"{"token":"ya29.private","calendar":"work-calendar-id"}"#,
            forbiddenValues: ["work-calendar-id"]
        )

        XCTAssertEqual(findings.count, 2)
    }

    func testBookingIdentifiersEncodeAsWireStrings() throws {
        let envelope = EncryptedBookingRequestEnvelope(
            schemaVersion: 1,
            requestID: BookingRequestID("request-1234"),
            inboxID: BookingInboxID("inbox-123"),
            shareID: BookingShareID("intro-call"),
            createdAt: Date(timeIntervalSince1970: 10),
            expiresAt: Date(timeIntervalSince1970: 20),
            keyID: "key-v1",
            algorithm: "ECDH-P256-AES-GCM",
            ephemeralPublicKeyJWK: ["x": "x-coordinate", "y": "y-coordinate"],
            nonce: "nonce-value",
            ciphertext: "ciphertext-value"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(envelope)
        let text = String(decoding: data, as: UTF8.self)
        let decoded = try JSONDecoder.bookingTestDecoder.decode(
            EncryptedBookingRequestEnvelope.self,
            from: data
        )

        XCTAssertTrue(text.contains(#""requestID":"request-1234""#))
        XCTAssertFalse(text.contains(#""rawValue""#))
        XCTAssertEqual(decoded.requestID, envelope.requestID)
        XCTAssertEqual(decoded.inboxID, envelope.inboxID)
        XCTAssertEqual(decoded.shareID, envelope.shareID)
    }

    func testStaticSiteGeneratorEmitsPublicArtifactsWithoutForbiddenValues() throws {
        let appointmentType = BookingAppointmentType(
            id: AppointmentTypeID("intro-call"),
            slug: "intro-call",
            name: "Intro call",
            summary: "A focused first conversation.",
            durationMinutes: 30,
            minimumNoticeMinutes: 60,
            bufferBeforeMinutes: 0,
            bufferAfterMinutes: 0,
            weeklyHours: BookingWeeklyHours.weekdayDefault,
            isAutoConfirmEnabled: false,
            questions: []
        )
        let configuration = BookingSiteConfiguration(
            profile: .example,
            appointmentTypes: [appointmentType],
            theme: .defaultValue,
            inboxID: BookingInboxID("inbox-123"),
            shareID: BookingShareID("intro-call"),
            inboxURL: URL(string: "https://example.workers.dev"),
            publicKey: BookingPublicKey(
                keyID: "public-key-v1",
                jwk: [
                    "kty": "EC",
                    "crv": "P-256",
                    "x": "x-coordinate",
                    "y": "y-coordinate",
                ]
            )
        )
        let slot = BookingOpenSlot(
            id: BookingSlotID("intro-call-1767258000"),
            appointmentTypeID: appointmentType.id,
            interval: DateInterval(
                start: Date(timeIntervalSince1970: 1_767_258_000),
                duration: 30 * 60
            ),
            token: SignedBookingSlotToken("signed-slot")
        )

        let artifacts = try BookingStaticSiteGenerator.artifacts(
            configuration: configuration,
            slots: [slot],
            generatedAt: Date(timeIntervalSince1970: 1_767_225_600),
            expiresAt: Date(timeIntervalSince1970: 1_767_312_000)
        )
        let combinedText = artifacts.map { $0.text }.joined(separator: "\n")

        XCTAssertEqual(artifacts.map(\.relativePath), ["public/site-config.json", "public/availability/slots.json"])
        XCTAssertTrue(combinedText.contains("Intro call"))
        XCTAssertTrue(combinedText.contains(#""weeklyHours""#))
        XCTAssertTrue(combinedText.contains(#""location""#))
        XCTAssertTrue(combinedText.contains(#""version""#))
        XCTAssertTrue(combinedText.contains(#""fingerprint""#))
        XCTAssertFalse(combinedText.contains("work-calendar-id"))
        XCTAssertFalse(combinedText.contains("refresh_token"))
    }

    func testDraftFactoryUsesCustomizedProfileThemeAndShareID() throws {
        let profile = BookingProfile(
            id: BookingProfileID("default"),
            publicName: "Avery Stone",
            pageTitle: "Book Avery",
            pageSubtitle: "Pick a focused slot.",
            timeZoneIdentifier: "America/New_York"
        )
        let theme = BookingTheme(
            accentColor: "#14532D",
            backgroundColor: "#F8FAFC",
            textColor: "#111827"
        )

        let draft = try BookingDraftFactory.makeDraft(
            now: Date(timeIntervalSince1970: 1_767_225_600),
            inboxURL: URL(string: "https://inbox.example.com"),
            profile: profile,
            theme: theme,
            shareID: BookingShareID("avery-intro")
        )
        let artifacts = try BookingStaticSiteGenerator.artifacts(
            configuration: draft.configuration,
            slots: draft.slots,
            generatedAt: draft.generatedAt,
            expiresAt: draft.expiresAt
        )
        let siteConfig = try XCTUnwrap(artifacts.first { $0.relativePath == "public/site-config.json" }?.text)

        XCTAssertTrue(siteConfig.contains("Avery Stone"))
        XCTAssertTrue(siteConfig.contains("Book Avery"))
        XCTAssertTrue(siteConfig.contains("Pick a focused slot."))
        XCTAssertTrue(siteConfig.contains("America/New_York"))
        XCTAssertTrue(siteConfig.contains("#14532D"))
        XCTAssertTrue(siteConfig.contains("#F8FAFC"))
        XCTAssertTrue(siteConfig.contains("#111827"))
        XCTAssertTrue(siteConfig.contains("avery-intro"))
        XCTAssertTrue(siteConfig.contains(#""availabilityHorizonDays""#))
        XCTAssertTrue(siteConfig.contains("14"))
    }

    func testPausedAppointmentTypesStayOutOfPublicSiteConfigAndSlots() throws {
        let paused = BookingAppointmentType(
            id: AppointmentTypeID("paused-call"),
            slug: "paused-call",
            name: "Paused call",
            summary: "Hidden while paused.",
            durationMinutes: 30,
            minimumNoticeMinutes: 60,
            bufferBeforeMinutes: 0,
            bufferAfterMinutes: 0,
            weeklyHours: BookingWeeklyHours.weekdayDefault,
            isAutoConfirmEnabled: false,
            isPaused: true,
            questions: []
        )
        let draft = try BookingDraftFactory.makeDraft(
            now: Date(timeIntervalSince1970: 1_767_225_600),
            inboxURL: URL(string: "https://inbox.example.com"),
            appointmentTypes: [paused]
        )
        let artifacts = try BookingStaticSiteGenerator.artifacts(
            configuration: draft.configuration,
            slots: draft.slots,
            generatedAt: draft.generatedAt,
            expiresAt: draft.expiresAt
        )
        let combinedText = artifacts.map { $0.text }.joined(separator: "\n")

        XCTAssertTrue(draft.slots.isEmpty)
        XCTAssertFalse(combinedText.contains("Paused call"))
        XCTAssertFalse(combinedText.contains("paused-call"))
    }

    func testAppointmentTypeDecodingDefaultsPausedToFalse() throws {
        let json = """
        {
          "id": "intro-call",
          "slug": "intro-call",
          "name": "Intro call",
          "summary": "A focused first conversation.",
          "durationMinutes": 30,
          "minimumNoticeMinutes": 60,
          "bufferBeforeMinutes": 0,
          "bufferAfterMinutes": 0,
          "weeklyHours": [],
          "location": { "mode": "none", "details": "" },
          "isAutoConfirmEnabled": false,
          "questions": []
        }
        """.data(using: .utf8)!

        let appointmentType = try JSONDecoder().decode(BookingAppointmentType.self, from: json)

        XCTAssertFalse(appointmentType.isPaused)
        XCTAssertEqual(appointmentType.availabilityHorizonDays, BookingAppointmentType.defaultAvailabilityHorizonDays)
    }

    func testAppointmentTypeDecodingDefaultsCalendarTargetToNil() throws {
        let json = """
        {
          "id": "intro-call",
          "slug": "intro-call",
          "name": "Intro call",
          "summary": "A focused first conversation.",
          "durationMinutes": 30,
          "minimumNoticeMinutes": 60,
          "bufferBeforeMinutes": 0,
          "bufferAfterMinutes": 0,
          "weeklyHours": [],
          "location": { "mode": "none", "details": "" },
          "isAutoConfirmEnabled": false,
          "questions": []
        }
        """.data(using: .utf8)!

        let appointmentType = try JSONDecoder().decode(BookingAppointmentType.self, from: json)

        XCTAssertNil(appointmentType.calendarTarget)
    }

    func testAppointmentCalendarTargetsStayOutOfPublicArtifactsAndFingerprint() throws {
        let baseAppointment = BookingAppointmentType(
            id: AppointmentTypeID("intro-call"),
            slug: "intro-call",
            name: "Intro call",
            summary: "A focused first conversation.",
            durationMinutes: 30,
            minimumNoticeMinutes: 60,
            bufferBeforeMinutes: 0,
            bufferAfterMinutes: 0,
            weeklyHours: BookingWeeklyHours.weekdayDefault,
            calendarTarget: .apple(calendarID: "private-apple-calendar-id"),
            isAutoConfirmEnabled: false,
            questions: []
        )
        var retargetedAppointment = baseAppointment
        retargetedAppointment.calendarTarget = .google(
            accountID: "private-google-account-id",
            calendarID: "private-google-calendar-id"
        )
        let firstDraft = try BookingDraftFactory.makeDraft(
            now: Date(timeIntervalSince1970: 1_767_225_600),
            inboxURL: URL(string: "https://inbox.example.com"),
            appointmentTypes: [baseAppointment]
        )
        var retargetedConfiguration = firstDraft.configuration
        retargetedConfiguration.appointmentTypes = [retargetedAppointment]
        let artifacts = try BookingStaticSiteGenerator.artifacts(
            configuration: firstDraft.configuration,
            slots: firstDraft.slots,
            generatedAt: firstDraft.generatedAt,
            expiresAt: firstDraft.expiresAt
        )
        let combinedText = artifacts.map { $0.text }.joined(separator: "\n")

        XCTAssertEqual(
            try BookingPublicationFingerprint.publicSiteFingerprint(configuration: firstDraft.configuration),
            try BookingPublicationFingerprint.publicSiteFingerprint(configuration: retargetedConfiguration)
        )
        XCTAssertFalse(combinedText.contains("private-apple-calendar-id"))
        XCTAssertFalse(combinedText.contains("private-google-account-id"))
        XCTAssertFalse(combinedText.contains("private-google-calendar-id"))
    }

    func testRelayHealthResponseDecodesAllowedOriginEvidence() throws {
        let data = Data(
            """
            {
              "ok": true,
              "allowedOrigin": "https://owner.github.io",
              "storage": "vercel-blob"
            }
            """.utf8
        )

        let health = try JSONDecoder().decode(BookingRelayHealthResponse.self, from: data)

        XCTAssertTrue(health.ok)
        XCTAssertEqual(health.allowedOrigin, "https://owner.github.io")
        XCTAssertEqual(health.storage, "vercel-blob")
    }

    func testStaticSiteWriterCreatesNestedPublicFiles() throws {
        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: outputDirectory)
        }

        let summary = try BookingStaticSiteWriter.write(
            artifacts: [
                BookingStaticSiteArtifact(
                    relativePath: "public/site-config.json",
                    data: Data(#"{"ok":true}"#.utf8)
                ),
            ],
            to: outputDirectory
        )

        XCTAssertEqual(summary.writtenRelativePaths, ["public/site-config.json"])
        XCTAssertEqual(
            try String(contentsOf: outputDirectory.appendingPathComponent("public/site-config.json")),
            #"{"ok":true}"#
        )
        if FileManager.default.fileExists(atPath: "templates/booking-site/index.html") {
            XCTAssertTrue(FileManager.default.fileExists(atPath: outputDirectory.appendingPathComponent("index.html").path))
        }
    }

    func testStaticSiteWriterUsesEditableTemplateDirectory() throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let templateDirectory = rootDirectory.appendingPathComponent("template", isDirectory: true)
        let outputDirectory = rootDirectory.appendingPathComponent("output", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        try FileManager.default.createDirectory(
            at: templateDirectory,
            withIntermediateDirectories: true
        )
        try "custom shell".write(
            to: templateDirectory.appendingPathComponent("index.html"),
            atomically: true,
            encoding: .utf8
        )

        let summary = try BookingStaticSiteWriter.write(
            artifacts: [
                BookingStaticSiteArtifact(
                    relativePath: "public/site-config.json",
                    data: Data(#"{"ok":true}"#.utf8)
                ),
            ],
            to: outputDirectory,
            templateDirectory: templateDirectory
        )

        XCTAssertEqual(summary.writtenRelativePaths, ["public/site-config.json"])
        XCTAssertEqual(
            try String(contentsOf: outputDirectory.appendingPathComponent("index.html")),
            "custom shell"
        )
        XCTAssertEqual(
            try String(contentsOf: outputDirectory.appendingPathComponent("public/site-config.json")),
            #"{"ok":true}"#
        )
    }

    func testGitHubRepositoryParsesOwnerRepoAndURL() throws {
        let repository = try BookingGitHubRepository(rawValue: "https://github.com/moorage/booking-test")

        XCTAssertEqual(repository.owner, "moorage")
        XCTAssertEqual(repository.name, "booking-test")
        XCTAssertEqual(repository.slug, "moorage/booking-test")
        XCTAssertEqual(repository.pagesURL.absoluteString, "https://moorage.github.io/booking-test/")
    }

    func testGitHubRepositoryParsesSSHCloneURLs() throws {
        let scpRepository = try BookingGitHubRepository(rawValue: "git@github.com:moorage/booking-test.git")
        let sshRepository = try BookingGitHubRepository(rawValue: "ssh://git@github.com/moorage/booking-test.git")

        XCTAssertEqual(scpRepository.slug, "moorage/booking-test")
        XCTAssertEqual(sshRepository.slug, "moorage/booking-test")
        XCTAssertEqual(scpRepository.sshRemoteURLString, "git@github.com:moorage/booking-test.git")
    }

    func testGitHubRepositoryParsesGitHubCLICloneCommand() throws {
        let repository = try BookingGitHubRepository(rawValue: "gh repo clone moorage/booking-test")

        XCTAssertEqual(repository.slug, "moorage/booking-test")
    }

    func testGitHubRepositoryRejectsNonRepositoryPaths() {
        XCTAssertThrowsError(try BookingGitHubRepository(rawValue: "https://github.com/moorage/booking-test/tree/main")) { error in
            XCTAssertEqual(
                error as? BookingConfigurationError,
                .invalidField("Use a GitHub repository like owner/repo, a GitHub clone URL, or gh repo clone owner/repo.")
            )
        }
    }

    func testGitHubRepositoryParsesUserPagesRepository() throws {
        let repository = try BookingGitHubRepository(rawValue: "moorage/moorage.github.io")

        XCTAssertEqual(repository.pagesURL.absoluteString, "https://moorage.github.io/")
    }

    func testRelayRequestBuilderKeepsAdminTokenOutOfURL() throws {
        let relayURL = try BookingRelayURL(URL(string: "https://example.workers.dev")!)
        let token = BookingRelayAdminToken(rawValue: "admin-secret")

        let listRequest = BookingRelayRequestBuilder.listRequestsRequest(
            relayURL: relayURL,
            inboxID: BookingInboxID("inbox-123"),
            cursor: "cursor 1",
            adminToken: token
        )
        let deleteRequest = BookingRelayRequestBuilder.deleteRequest(
            relayURL: relayURL,
            inboxID: BookingInboxID("inbox-123"),
            requestID: BookingRequestID("request-1234"),
            adminToken: token
        )

        XCTAssertEqual(listRequest.httpMethod, "GET")
        XCTAssertEqual(listRequest.value(forHTTPHeaderField: "Authorization"), "Bearer admin-secret")
        XCTAssertEqual(deleteRequest.httpMethod, "DELETE")
        XCTAssertEqual(deleteRequest.value(forHTTPHeaderField: "Authorization"), "Bearer admin-secret")
        XCTAssertFalse(listRequest.url!.absoluteString.contains("admin-secret"))
        XCTAssertFalse(deleteRequest.url!.absoluteString.contains("admin-secret"))
        XCTAssertTrue(listRequest.url!.absoluteString.contains("cursor=cursor%201"))
    }

    func testRelayRequestPageDecodesBrowserEnvelope() throws {
        let json = Data(
            """
            {
              "requests": [
                {
                  "schemaVersion": 1,
                  "requestID": "request-1234",
                  "inboxID": "inbox-123",
                  "shareID": "intro-call",
                  "createdAt": "2026-01-01T00:00:00Z",
                  "expiresAt": "2026-01-01T01:00:00Z",
                  "keyID": "key-v1",
                  "algorithm": "ECDH-P256-AES-GCM",
                  "ephemeralPublicKeyJwk": {
                    "key_ops": [],
                    "ext": true,
                    "kty": "EC",
                    "crv": "P-256",
                    "x": "x-coordinate",
                    "y": "y-coordinate"
                  },
                  "nonce": "nonce-value",
                  "ciphertext": "ciphertext-value"
                }
              ],
              "cursor": "next-cursor"
            }
            """.utf8
        )

        let page = try JSONDecoder.bookingTestDecoder.decode(
            BookingRelayRequestPage.self,
            from: json
        )

        XCTAssertEqual(page.cursor, "next-cursor")
        XCTAssertEqual(page.requests.first?.requestID, BookingRequestID("request-1234"))
        XCTAssertEqual(page.requests.first?.ephemeralPublicKeyJWK?["crv"], "P-256")
        XCTAssertNil(page.requests.first?.ephemeralPublicKeyJWK?["ext"])
    }

    func testBookingKeyMaterialExportsPublicJWKOnly() {
        let privateKey = P256.KeyAgreement.PrivateKey()

        let publicKey = BookingKeyMaterial.publicKey(
            from: privateKey,
            keyID: "booking-key-v1"
        )

        XCTAssertEqual(publicKey.keyID, "booking-key-v1")
        XCTAssertEqual(publicKey.jwk["kty"], "EC")
        XCTAssertEqual(publicKey.jwk["crv"], "P-256")
        XCTAssertNotNil(publicKey.jwk["x"])
        XCTAssertNotNil(publicKey.jwk["y"])
        XCTAssertNil(publicKey.jwk["d"])
    }

    func testDraftFactoryCreatesPublishableArtifactsWithConfiguredInboxURL() throws {
        let secrets = BookingLocalSecrets.generate()
        let draft = try BookingDraftFactory.makeDraft(
            now: Date(timeIntervalSince1970: 1_767_225_600),
            inboxURL: URL(string: "https://inbox.example.com"),
            secrets: secrets
        )
        let artifacts = try BookingStaticSiteGenerator.artifacts(
            configuration: draft.configuration,
            slots: draft.slots,
            generatedAt: draft.generatedAt,
            expiresAt: draft.expiresAt
        )
        let siteConfig = artifacts.first { $0.relativePath == "public/site-config.json" }?.text ?? ""

        XCTAssertFalse(draft.slots.isEmpty)
        XCTAssertTrue(siteConfig.contains("https://inbox.example.com"))
        XCTAssertTrue(siteConfig.contains(secrets.inboxID.rawValue))
        XCTAssertTrue(siteConfig.contains(#""publicKeyJwk""#))
        XCTAssertFalse(siteConfig.contains(#""d""#))
    }

    func testGitHubPublisherPlansSkipForUnchangedRemoteFiles() {
        let localData = Data(#"{"version":{"fingerprint":"same"}}"#.utf8)

        let plan = BookingGitHubPublisher.filePublishPlan(
            relativePath: "public/site-config.json",
            localData: localData,
            remoteData: localData
        )

        XCTAssertFalse(plan.shouldUpload)
        XCTAssertFalse(plan.isOverwrite)
        XCTAssertNil(plan.remoteChangedPath)
    }

    func testGitHubPublisherPlansOverwriteWarningForRemoteDrift() {
        let localData = Data(#"{"slots":["local"]}"#.utf8)
        let remoteData = Data(#"{"slots":["remote"]}"#.utf8)

        let plan = BookingGitHubPublisher.filePublishPlan(
            relativePath: "public/availability/slots.json",
            localData: localData,
            remoteData: remoteData
        )

        XCTAssertTrue(plan.shouldUpload)
        XCTAssertTrue(plan.isOverwrite)
        XCTAssertEqual(plan.remoteChangedPath, "public/availability/slots.json")
    }

    func testGitHubPublisherAllowsOnlyGeneratedFilesAtRepositoryRoot() {
        let unexpectedPaths = BookingGitHubPublisher.unexpectedRootContentPaths(
            localPaths: [
                "index.html",
                "assets/app.js",
                "public/site-config.json",
            ],
            remotePaths: [
                "README.md",
                "assets/app.js",
                "public/site-config.json",
            ]
        )

        XCTAssertEqual(unexpectedPaths, ["README.md"])
    }

    func testGitHubPublisherAllowsRepeatPublishOfGeneratedRootFiles() {
        let unexpectedPaths = BookingGitHubPublisher.unexpectedRootContentPaths(
            localPaths: [
                "index.html",
                "assets/app.js",
                "public/site-config.json",
            ],
            remotePaths: [
                "index.html",
                "assets/app.js",
            ]
        )

        XCTAssertTrue(unexpectedPaths.isEmpty)
    }

    func testGitHubPublisherPushesGeneratedRootFilesWithDeployKey() async throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory
            .appendingPathComponent("booking-publisher-test-\(UUID().uuidString)", isDirectory: true)
        let localRoot = tempRoot.appendingPathComponent("local", isDirectory: true)
        let workRoot = tempRoot.appendingPathComponent("work", isDirectory: true)
        defer {
            try? fileManager.removeItem(at: tempRoot)
        }

        try fileManager.createDirectory(at: localRoot.appendingPathComponent("public"), withIntermediateDirectories: true)
        try Data("<html>Booking</html>".utf8).write(to: localRoot.appendingPathComponent("index.html"))
        try Data(#"{"version":{"fingerprint":"abc"}}"#.utf8)
            .write(to: localRoot.appendingPathComponent("public/site-config.json"))

        let runner = RecordingBookingGitCommandRunner()
        let summary = try await BookingGitHubPublisher.publishDirectory(
            at: localRoot,
            repository: try BookingGitHubRepository(rawValue: "moorage/booking-test"),
            branch: "main",
            privateKeyPEM: """
            -----BEGIN OPENSSH PRIVATE KEY-----
            test
            -----END OPENSSH PRIVATE KEY-----
            """,
            fileManager: fileManager,
            commandRunner: runner,
            workingDirectoryRoot: workRoot
        )

        XCTAssertEqual(summary.uploadedCount, 2)
        XCTAssertEqual(summary.skippedCount, 0)
        XCTAssertEqual(summary.overwrittenCount, 0)
        XCTAssertEqual(summary.remoteChangedPaths, [])
        XCTAssertTrue(runner.commands.contains { $0.arguments == ["push", "origin", "HEAD:main"] })
        XCTAssertTrue(runner.commands.contains { command in
            command.environment["GIT_SSH_COMMAND"]?.contains("-i") == true
        })
    }

    func testGitHubPublisherRejectsNonEmptyRepositoryRoot() async throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory
            .appendingPathComponent("booking-publisher-test-\(UUID().uuidString)", isDirectory: true)
        let localRoot = tempRoot.appendingPathComponent("local", isDirectory: true)
        let workRoot = tempRoot.appendingPathComponent("work", isDirectory: true)
        defer {
            try? fileManager.removeItem(at: tempRoot)
        }

        try fileManager.createDirectory(at: localRoot, withIntermediateDirectories: true)
        try Data("<html>Booking</html>".utf8).write(to: localRoot.appendingPathComponent("index.html"))

        let runner = RecordingBookingGitCommandRunner(remoteFiles: ["README.md": "Existing repository content"])

        do {
            _ = try await BookingGitHubPublisher.publishDirectory(
                at: localRoot,
                repository: try BookingGitHubRepository(rawValue: "moorage/booking-test"),
                branch: "main",
                privateKeyPEM: """
                -----BEGIN OPENSSH PRIVATE KEY-----
                test
                -----END OPENSSH PRIVATE KEY-----
                """,
                fileManager: fileManager,
                commandRunner: runner,
                workingDirectoryRoot: workRoot
            )
            XCTFail("Expected non-empty repository roots to be rejected.")
        } catch {
            XCTAssertEqual(
                error as? BookingConfigurationError,
                .invalidField("Use an empty GitHub Pages repository. Remove README.md before publishing.")
            )
        }

        XCTAssertFalse(runner.commands.contains { $0.arguments.first == "push" })
    }

    func testDraftFactoryReusesStoredSecretsForDecryptAndSlotVerification() throws {
        let secrets = BookingLocalSecrets.generate()
        let draft = try BookingDraftFactory.makeDraft(
            now: Date(timeIntervalSince1970: 1_767_225_600),
            inboxURL: URL(string: "https://inbox.example.com"),
            secrets: secrets
        )
        let slot = try XCTUnwrap(draft.slots.first)
        let claim = try secrets.slotSigner.verifiedClaim(from: slot.token)

        XCTAssertEqual(draft.configuration.inboxID, secrets.inboxID)
        XCTAssertEqual(draft.configuration.publicKey.keyID, secrets.keyID)
        XCTAssertEqual(claim.slotID, slot.id)
    }

    func testRequestDecryptorOpensECDHEnvelope() throws {
        let recipientPrivateKey = P256.KeyAgreement.PrivateKey()
        let ephemeralPrivateKey = P256.KeyAgreement.PrivateKey()
        let sharedSecret = try ephemeralPrivateKey.sharedSecretFromKeyAgreement(
            with: recipientPrivateKey.publicKey
        )
        let symmetricKey = sharedSecret.withUnsafeBytes { bytes in
            SymmetricKey(data: Data(bytes))
        }
        let nonce = try AES.GCM.Nonce(data: Data(repeating: 1, count: 12))
        let plaintext = Data(#"{"name":"Test Booker"}"#.utf8)
        let sealedBox = try AES.GCM.seal(plaintext, using: symmetricKey, nonce: nonce)
        let publicKeyData = ephemeralPrivateKey.publicKey.x963Representation
        let envelope = EncryptedBookingRequestEnvelope(
            schemaVersion: 1,
            requestID: BookingRequestID("request-1234"),
            inboxID: BookingInboxID("inbox-123"),
            shareID: BookingShareID("intro-call"),
            createdAt: Date(timeIntervalSince1970: 10),
            expiresAt: Date(timeIntervalSince1970: 20),
            keyID: "key-v1",
            algorithm: "ECDH-P256-AES-GCM",
            ephemeralPublicKeyJWK: [
                "kty": "EC",
                "crv": "P-256",
                "x": Data(publicKeyData[1..<33]).base64URLEncodedStringForTest(),
                "y": Data(publicKeyData[33..<65]).base64URLEncodedStringForTest(),
            ],
            nonce: Data(repeating: 1, count: 12).base64URLEncodedStringForTest(),
            ciphertext: (sealedBox.ciphertext + sealedBox.tag).base64URLEncodedStringForTest()
        )

        XCTAssertEqual(
            try BookingRequestDecryptor.decrypt(envelope, using: recipientPrivateKey),
            plaintext
        )
    }

    func testTestRequestSenderCreatesDecryptableBrowserStyleEnvelope() throws {
        let recipientPrivateKey = P256.KeyAgreement.PrivateKey()
        let config = BookingPublishedSiteConfig(
            share: BookingPublishedShare(id: BookingShareID("intro-call")),
            inbox: BookingPublishedInbox(
                id: BookingInboxID("demo-inbox"),
                url: try XCTUnwrap(URL(string: "https://relay.example.com"))
            ),
            encryption: BookingPublishedEncryption(
                keyID: "test-key-v1",
                publicKeyJWK: BookingKeyMaterial.publicKey(
                    from: recipientPrivateKey,
                    keyID: "test-key-v1"
                ).jwk
            )
        )
        let slot = BookingPublishedSlot(
            id: BookingSlotID("intro-call-1"),
            appointmentTypeID: AppointmentTypeID("intro-call"),
            startsAt: Date(timeIntervalSince1970: 100),
            endsAt: Date(timeIntervalSince1970: 130),
            expiresAt: Date(timeIntervalSince1970: 100),
            token: SignedBookingSlotToken("signed-slot-token")
        )
        let plaintext = BookingTestRequestPlaintext(
            requestID: BookingRequestID("test-request-1"),
            appointmentTypeID: AppointmentTypeID("intro-call"),
            slotID: BookingSlotID("intro-call-1"),
            slotToken: SignedBookingSlotToken("signed-slot-token"),
            visitor: BookingTestVisitor(
                name: "Calendar Busy Sync Test",
                email: "test@example.com",
                topic: "Setup test request"
            ),
            browserTimeZone: "America/Los_Angeles",
            createdAt: Date(timeIntervalSince1970: 50)
        )

        let envelope = try BookingTestRequestSender.encrypt(
            plaintext: plaintext,
            slot: slot,
            config: config,
            createdAt: Date(timeIntervalSince1970: 50)
        )
        let decryptedData = try BookingRequestDecryptor.decrypt(envelope, using: recipientPrivateKey)
        let decryptedPlaintext = try JSONDecoder.bookingTestDecoder.decode(
            DecodedBookingTestRequestPlaintext.self,
            from: decryptedData
        )

        XCTAssertEqual(envelope.algorithm, "ECDH-P256-AES-GCM")
        XCTAssertEqual(envelope.inboxID, BookingInboxID("demo-inbox"))
        XCTAssertEqual(decryptedPlaintext.requestID, BookingRequestID("test-request-1"))
        XCTAssertEqual(decryptedPlaintext.visitor.email, "test@example.com")
    }

    func testPublishedSiteConfigDecodesBrowserStandardJWKValues() throws {
        let json = Data(
            #"""
            {
              "share": {"id": "intro-call"},
              "inbox": {"id": "demo-inbox", "url": "https://relay.example.com"},
              "encryption": {
                "keyID": "key-v1",
                "publicKeyJwk": {
                  "kty": "EC",
                  "crv": "P-256",
                  "x": "abc",
                  "y": "def",
                  "ext": true
                }
              }
            }
            """#.utf8
        )

        let config = try JSONDecoder.bookingTestDecoder.decode(BookingPublishedSiteConfig.self, from: json)

        XCTAssertEqual(config.encryption.publicKeyJWK["ext"], "true")
        XCTAssertEqual(config.inbox.id, BookingInboxID("demo-inbox"))
    }

    func testRequestImporterDecryptsVerifiesAndMarksPendingReview() throws {
        let secrets = BookingLocalSecrets.generate()
        let now = Date(timeIntervalSince1970: 1_767_225_600)
        let slotStart = Date(timeIntervalSince1970: 1_767_258_000)
        let slotEnd = slotStart.addingTimeInterval(30 * 60)
        let claim = BookingSlotClaim(
            appointmentTypeID: AppointmentTypeID("intro-call"),
            slotID: BookingSlotID("intro-call-1767258000"),
            startsAt: slotStart,
            endsAt: slotEnd,
            generatedAt: now,
            expiresAt: slotStart,
            nonce: "nonce",
            signingKeyVersion: "v1"
        )
        let token = try secrets.slotSigner.sign(claim)
        let config = BookingPublishedSiteConfig(
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
        )
        let slot = BookingPublishedSlot(
            id: claim.slotID,
            appointmentTypeID: claim.appointmentTypeID,
            startsAt: claim.startsAt,
            endsAt: claim.endsAt,
            expiresAt: claim.expiresAt,
            token: token
        )
        let plaintext = BookingTestRequestPlaintext(
            requestID: BookingRequestID("request-1"),
            appointmentTypeID: claim.appointmentTypeID,
            slotID: claim.slotID,
            slotToken: token,
            visitor: BookingTestVisitor(
                name: "Matt Moore",
                email: "matt@alumni.ucsd.edu",
                topic: "End-to-end browser test",
                guestEmails: ["guest@example.com"]
            ),
            browserTimeZone: "America/Los_Angeles",
            createdAt: now
        )
        let envelope = try BookingTestRequestSender.encrypt(
            plaintext: plaintext,
            slot: slot,
            config: config,
            createdAt: now
        )

        let imported = try BookingRequestImporter.importEnvelope(
            envelope,
            secrets: secrets,
            now: now,
            isSlotStillOpen: { _ in true }
        )

        XCTAssertEqual(imported.status, .pendingReview)
        XCTAssertEqual(imported.plaintext.visitor.email, "matt@alumni.ucsd.edu")
        XCTAssertEqual(imported.inviteeEmails, ["matt@alumni.ucsd.edu", "guest@example.com"])
        XCTAssertEqual(imported.slotClaim, claim)
    }

    func testRequestVisitorDecodesOlderPayloadsWithoutGuestEmails() throws {
        let data = Data(
            """
            {"name":"Matt Moore","email":"matt@alumni.ucsd.edu","topic":"Intro"}
            """.utf8
        )

        let visitor = try JSONDecoder().decode(BookingRequestVisitor.self, from: data)

        XCTAssertEqual(visitor.guestEmails, [])
    }

    func testInviteICSIncludesBookerAndGuestAttendees() throws {
        let request = makeImportedBookingRequest(
            guestEmails: [
                "guest@example.com",
                "matt@alumni.ucsd.edu",
                "second@example.com",
            ]
        )

        let data = BookingInviteICSGenerator.makeICS(
            for: request,
            calendarName: "Matt - iCloud",
            now: Date(timeIntervalSince1970: 1_767_225_600)
        )
        let ics = try XCTUnwrap(String(data: data, encoding: .utf8))
        let unfoldedICS = ics.replacingOccurrences(of: "\r\n ", with: "")

        XCTAssertTrue(unfoldedICS.contains("METHOD:REQUEST"))
        XCTAssertTrue(unfoldedICS.contains("SUMMARY:Meeting with Matt Moore"))
        XCTAssertTrue(unfoldedICS.contains("Notes: A 30 minute meeting"))
        XCTAssertTrue(unfoldedICS.contains("ATTENDEE;CN=\"Matt Moore\";ROLE=REQ-PARTICIPANT;PARTSTAT=NEEDS-ACTION;RSVP=TRUE:mailto:matt@alumni.ucsd.edu"))
        XCTAssertTrue(unfoldedICS.contains("ATTENDEE;CN=\"guest@example.com\";ROLE=REQ-PARTICIPANT;PARTSTAT=NEEDS-ACTION;RSVP=TRUE:mailto:guest@example.com"))
        XCTAssertTrue(unfoldedICS.contains("ATTENDEE;CN=\"second@example.com\";ROLE=REQ-PARTICIPANT;PARTSTAT=NEEDS-ACTION;RSVP=TRUE:mailto:second@example.com"))
    }

    func testDeclineICSMarksOwnerDeclinedAndIncludesInvitees() throws {
        let request = makeImportedBookingRequest(guestEmails: ["guest@example.com"])

        let data = BookingInviteICSGenerator.makeICS(
            for: request,
            calendarName: "Matt - iCloud",
            now: Date(timeIntervalSince1970: 1_767_225_600),
            disposition: .decline
        )
        let ics = try XCTUnwrap(String(data: data, encoding: .utf8))
        let unfoldedICS = ics.replacingOccurrences(of: "\r\n ", with: "")

        XCTAssertTrue(unfoldedICS.contains("METHOD:REPLY"))
        XCTAssertTrue(unfoldedICS.contains("SUMMARY:Declined: Meeting with Matt Moore"))
        XCTAssertTrue(unfoldedICS.contains("STATUS:CANCELLED"))
        XCTAssertTrue(unfoldedICS.contains("ORGANIZER;CN=\"Matt - iCloud\":mailto:matt@alumni.ucsd.edu"))
        XCTAssertTrue(unfoldedICS.contains("ATTENDEE;CN=\"Matt - iCloud\";ROLE=REQ-PARTICIPANT;PARTSTAT=DECLINED;RSVP=FALSE:mailto:calendar-busy-sync@example.invalid"))
        XCTAssertTrue(unfoldedICS.contains("ATTENDEE;CN=\"Matt Moore\";ROLE=REQ-PARTICIPANT;PARTSTAT=NEEDS-ACTION;RSVP=TRUE:mailto:matt@alumni.ucsd.edu"))
        XCTAssertTrue(unfoldedICS.contains("ATTENDEE;CN=\"guest@example.com\";ROLE=REQ-PARTICIPANT;PARTSTAT=NEEDS-ACTION;RSVP=TRUE:mailto:guest@example.com"))
    }

    func testRequestImporterMarksUnavailableWhenLiveCalendarBlocksSlot() throws {
        let secrets = BookingLocalSecrets.generate()
        let now = Date(timeIntervalSince1970: 1_767_225_600)
        let slotStart = Date(timeIntervalSince1970: 1_767_258_000)
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
        let token = try secrets.slotSigner.sign(claim)
        let config = BookingPublishedSiteConfig(
            share: BookingPublishedShare(id: BookingShareID("intro-call")),
            inbox: BookingPublishedInbox(id: secrets.inboxID, url: URL(string: "https://relay.example.com")!),
            encryption: BookingPublishedEncryption(
                keyID: secrets.keyID,
                publicKeyJWK: BookingKeyMaterial.publicKey(from: try secrets.privateKey, keyID: secrets.keyID).jwk
            )
        )
        let envelope = try BookingTestRequestSender.encrypt(
            plaintext: BookingTestRequestPlaintext(
                requestID: BookingRequestID("request-2"),
                appointmentTypeID: claim.appointmentTypeID,
                slotID: claim.slotID,
                slotToken: token,
                visitor: BookingTestVisitor(name: "Matt Moore", email: "matt@alumni.ucsd.edu", topic: ""),
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
            config: config,
            createdAt: now
        )

        let imported = try BookingRequestImporter.importEnvelope(
            envelope,
            secrets: secrets,
            now: now,
            isSlotStillOpen: { _ in false }
        )

        XCTAssertEqual(imported.status, .unavailable)
        XCTAssertEqual(imported.message, BookingCopy.Validation.slotNoLongerOpen)
    }

    func testRequestLedgerDedupesAndMarksExpired() {
        let envelope = EncryptedBookingRequestEnvelope(
            schemaVersion: 1,
            requestID: BookingRequestID("request-1234"),
            inboxID: BookingInboxID("inbox-123"),
            shareID: BookingShareID("intro-call"),
            createdAt: Date(timeIntervalSince1970: 10),
            expiresAt: Date(timeIntervalSince1970: 20),
            keyID: "key-v1",
            algorithm: "ECDH-P256-AES-GCM",
            ephemeralPublicKeyJWK: nil,
            nonce: "nonce",
            ciphertext: "ciphertext"
        )
        var ledger = BookingRequestLedger()

        let firstImport = ledger.importEnvelope(
            envelope,
            digest: "digest",
            now: Date(timeIntervalSince1970: 30)
        )
        let duplicateImport = ledger.importEnvelope(
            envelope,
            digest: "digest",
            now: Date(timeIntervalSince1970: 30)
        )

        XCTAssertEqual(firstImport?.status, .expired)
        XCTAssertNil(duplicateImport)
    }

    func testCopyRegistryUsesRequestInboxLanguage() {
        XCTAssertEqual(BookingCopy.StatusCard.inboxTitle, "Request inbox")
        XCTAssertFalse(BookingCopy.StatusCard.inboxTitle.localizedCaseInsensitiveContains("relay"))
        XCTAssertEqual(BookingCopy.Action.generatePageFiles, "Generate page files")
        XCTAssertEqual(BookingCopy.Action.runDryRun, "Refresh page files")
        XCTAssertEqual(BookingCopy.Action.automaticBookingApproval, "Automatically accept requests")
        XCTAssertEqual(BookingCopy.Validation.dryRunReady, "Page files ready. Review them before publishing.")
        XCTAssertEqual(BookingCopy.Field.appointmentType, "Appointment type")
        XCTAssertEqual(BookingIconography.inbox.primarySystemName, "tray")
    }

    func testDefaultAppointmentTypesAreExposedForNativeSelection() {
        XCTAssertEqual(BookingDraftFactory.defaultAppointmentTypes.map(\.id), [AppointmentTypeID("intro-call")])
        XCTAssertEqual(BookingDraftFactory.defaultAppointmentTypes.map(\.slug), ["intro-call"])
    }

    func testSetupSnapshotChoosesNextActionableStep() {
        XCTAssertEqual(BookingSetupSnapshot.notStarted.nextSetupStep, .page)
        XCTAssertEqual(
            BookingSetupSnapshot(
                pageStatus: .generatedLocally,
                inboxStatus: .notConnected,
                pendingRequestCount: 0,
                lastMessage: nil
            ).nextSetupStep,
            .publish
        )
        XCTAssertEqual(
            BookingSetupSnapshot(
                pageStatus: .published,
                inboxStatus: .needsCheck,
                pendingRequestCount: 0,
                lastMessage: nil
            ).nextSetupStep,
            .inbox
        )
        XCTAssertEqual(
            BookingSetupSnapshot(
                pageStatus: .published,
                inboxStatus: .connected,
                pendingRequestCount: 0,
                lastMessage: nil
            ).nextSetupStep,
            .test
        )
    }

    func testSetupSnapshotEmphasizesCurrentPageAction() {
        XCTAssertTrue(
            BookingSetupSnapshot(
                pageStatus: .notPublished,
                inboxStatus: .notConnected,
                pendingRequestCount: 0,
                lastMessage: nil
            ).shouldEmphasizePageGeneration
        )
        XCTAssertTrue(
            BookingSetupSnapshot(
                pageStatus: .generatedLocally,
                inboxStatus: .notConnected,
                pendingRequestCount: 0,
                lastMessage: nil
            ).shouldEmphasizePublish
        )
        XCTAssertTrue(
            BookingSetupSnapshot(
                pageStatus: .uploaded,
                inboxStatus: .notConnected,
                pendingRequestCount: 0,
                lastMessage: nil
            ).shouldEmphasizeVerification
        )
        XCTAssertFalse(
            BookingSetupSnapshot(
                pageStatus: .published,
                inboxStatus: .connected,
                pendingRequestCount: 0,
                lastMessage: nil
            ).shouldEmphasizePageGeneration
        )
    }
}

private func makeImportedBookingRequest(guestEmails: [String] = []) -> BookingImportedRequest {
    let now = Date(timeIntervalSince1970: 1_767_225_600)
    let slotStart = Date(timeIntervalSince1970: 1_767_258_000)
    let requestID = BookingRequestID("request-ics-1")
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

private struct DecodedBookingTestRequestPlaintext: Decodable, Equatable {
    var requestID: BookingRequestID
    var visitor: DecodedBookingTestVisitor
}

private struct DecodedBookingTestVisitor: Decodable, Equatable {
    var email: String
}

private final class RecordingBookingGitCommandRunner: BookingGitCommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private let remoteFiles: [String: String]
    private var recordedCommands: [BookingGitCommand] = []
    private var recordedLastWorktreeURL: URL?

    var commands: [BookingGitCommand] {
        lock.lock()
        defer { lock.unlock() }
        return recordedCommands
    }

    var lastWorktreeURL: URL? {
        lock.lock()
        defer { lock.unlock() }
        return recordedLastWorktreeURL
    }

    init(remoteFiles: [String: String] = [:]) {
        self.remoteFiles = remoteFiles
    }

    func run(_ command: BookingGitCommand) async throws -> BookingGitCommandResult {
        lock.lock()
        recordedCommands.append(command)
        lock.unlock()

        guard command.executableURL.lastPathComponent == "git" else {
            return BookingGitCommandResult(standardOutput: "", standardError: "")
        }

        switch command.arguments.first {
        case "clone":
            let worktreePath = try XCTUnwrap(command.arguments.last)
            let worktreeURL = URL(fileURLWithPath: worktreePath, isDirectory: true)
            try FileManager.default.createDirectory(
                at: worktreeURL.appendingPathComponent(".git", isDirectory: true),
                withIntermediateDirectories: true
            )
            for (relativePath, content) in remoteFiles {
                let fileURL = worktreeURL.appendingPathComponent(relativePath)
                try FileManager.default.createDirectory(
                    at: fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try Data(content.utf8).write(to: fileURL)
            }
            lock.lock()
            recordedLastWorktreeURL = worktreeURL
            lock.unlock()
            return BookingGitCommandResult(standardOutput: "", standardError: "")
        case "rev-parse":
            throw BookingGitCommandError.failed(
                executable: command.executableURL.path,
                arguments: command.arguments,
                status: 128,
                standardOutput: "",
                standardError: "fatal: Needed a single revision"
            )
        case "status":
            return BookingGitCommandResult(standardOutput: "A  index.html\n", standardError: "")
        default:
            return BookingGitCommandResult(standardOutput: "", standardError: "")
        }
    }
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

    func base64URLEncodedStringForTest() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension JSONDecoder {
    static var bookingTestDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
