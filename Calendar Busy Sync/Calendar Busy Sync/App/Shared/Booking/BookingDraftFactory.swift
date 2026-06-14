import CryptoKit
import Foundation

struct BookingDraft: Equatable, Sendable {
    var configuration: BookingSiteConfiguration
    var slots: [BookingOpenSlot]
    var generatedAt: Date
    var expiresAt: Date
}

enum BookingDraftFactory {
    static let defaultAppointmentTypes = [
        BookingAppointmentType(
            id: AppointmentTypeID("intro-call"),
            slug: "intro-call",
            name: "Intro call",
            summary: "A focused first conversation.",
            durationMinutes: 30,
            minimumNoticeMinutes: 60,
            bufferBeforeMinutes: 10,
            bufferAfterMinutes: 10,
            weeklyHours: BookingWeeklyHours.weekdayDefault,
            isAutoConfirmEnabled: false,
            questions: [
                BookingQuestion(id: "name", label: BookingCopy.PublicSite.visitorName, type: .text, isRequired: true),
                BookingQuestion(id: "email", label: BookingCopy.PublicSite.visitorEmail, type: .email, isRequired: true),
                BookingQuestion(id: "topic", label: BookingCopy.PublicSite.topicQuestion, type: .longText, isRequired: false),
            ]
        ),
    ]

    static func makeDraft(
        now: Date,
        inboxURL: URL?,
        busyIntervals: [BookingBusyInterval] = [],
        secrets: BookingLocalSecrets = .generate(),
        appointmentTypes: [BookingAppointmentType] = Self.defaultAppointmentTypes,
        profile: BookingProfile = .example,
        theme: BookingTheme = .defaultValue,
        shareID: BookingShareID = BookingShareID("intro-call"),
        calendar: Calendar = .current
    ) throws -> BookingDraft {
        try BookingConfigurationValidator.validateAppointmentTypes(appointmentTypes)
        let privateKey = try secrets.privateKey
        let signer = try secrets.slotSigner
        let generationCalendar = calendar
        var slotsByAppointmentType: [[BookingOpenSlot]] = []

        for appointmentType in appointmentTypes where !appointmentType.isPaused {
            var appointmentSlots: [BookingOpenSlot] = []
            for dayOffset in 1...appointmentType.availabilityHorizonDays {
                guard let day = generationCalendar.date(byAdding: .day, value: dayOffset, to: now) else {
                    continue
                }

                let weekday = generationCalendar.component(.weekday, from: day)
                for workingHours in appointmentType.workingHours(forWeekday: weekday) {
                    appointmentSlots.append(
                        contentsOf: try BookingAvailabilityCompiler.openSlots(
                            on: generationCalendar.startOfDay(for: day),
                            appointmentType: appointmentType,
                            workingHours: workingHours,
                            busyIntervals: busyIntervals,
                            calendar: generationCalendar,
                            generatedAt: now
                        ) { claim in
                            try signer.sign(claim)
                        }
                    )
                }
            }

            if !appointmentSlots.isEmpty {
                slotsByAppointmentType.append(appointmentSlots)
            }
        }

        let slots = slotsByAppointmentType.flatMap { $0 }.sorted { $0.interval.start < $1.interval.start }
        let expiresAt = slots.map(\.interval.start).max() ?? now

        return BookingDraft(
            configuration: BookingSiteConfiguration(
                profile: profile,
                appointmentTypes: appointmentTypes,
                theme: theme,
                inboxID: secrets.inboxID,
                shareID: shareID,
                inboxURL: inboxURL ?? URL(string: "https://example.workers.dev"),
                publicKey: BookingKeyMaterial.publicKey(
                    from: privateKey,
                    keyID: secrets.keyID
                )
            ),
            slots: slots,
            generatedAt: now,
            expiresAt: expiresAt
        )
    }

    static func busyLookupWindow(
        startingAt now: Date,
        appointmentTypes: [BookingAppointmentType] = Self.defaultAppointmentTypes,
        calendar: Calendar = .current
    ) -> DateInterval {
        let start = calendar.startOfDay(for: now)
        let activeHorizonDays = appointmentTypes
            .filter { !$0.isPaused }
            .map(\.availabilityHorizonDays)
            .max() ?? BookingAppointmentType.defaultAvailabilityHorizonDays
        let clampedHorizonDays = max(
            1,
            min(BookingAppointmentType.maximumAvailabilityHorizonDays, activeHorizonDays)
        )
        let end = calendar.date(byAdding: .day, value: clampedHorizonDays + 1, to: start)
            ?? start.addingTimeInterval(TimeInterval((clampedHorizonDays + 1) * 24 * 60 * 60))
        return DateInterval(start: start, end: end)
    }
}
