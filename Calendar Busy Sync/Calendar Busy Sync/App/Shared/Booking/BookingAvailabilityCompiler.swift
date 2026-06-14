import Foundation

struct BookingBusyInterval: Equatable, Sendable {
    var interval: DateInterval
}

struct BookingWorkingHours: Codable, Equatable, Sendable {
    var startMinuteOfDay: Int
    var endMinuteOfDay: Int

    static let unavailable = BookingWorkingHours(
        startMinuteOfDay: 0,
        endMinuteOfDay: 0
    )

    static let weekdayDefault = BookingWorkingHours(
        startMinuteOfDay: 9 * 60,
        endMinuteOfDay: 17 * 60
    )
}

struct BookingOpenSlot: Equatable, Sendable {
    var id: BookingSlotID
    var appointmentTypeID: AppointmentTypeID
    var interval: DateInterval
    var token: SignedBookingSlotToken
}

enum BookingAvailabilityCompiler {
    static func openSlots(
        on day: Date,
        appointmentType: BookingAppointmentType,
        workingHours: BookingWorkingHours,
        busyIntervals: [BookingBusyInterval],
        calendar: Calendar,
        generatedAt: Date,
        tokenFactory: (BookingSlotClaim) throws -> SignedBookingSlotToken
    ) throws -> [BookingOpenSlot] {
        guard appointmentType.durationMinutes > 0 else {
            throw BookingConfigurationError.invalidField("Add a duration before publishing.")
        }
        guard workingHours.startMinuteOfDay < workingHours.endMinuteOfDay else {
            return []
        }

        let start = try date(on: day, minuteOfDay: workingHours.startMinuteOfDay, calendar: calendar)
        let end = try date(on: day, minuteOfDay: workingHours.endMinuteOfDay, calendar: calendar)
        let duration = TimeInterval(appointmentType.durationMinutes * 60)
        let step = TimeInterval(15 * 60)
        let minimumStart = generatedAt.addingTimeInterval(TimeInterval(appointmentType.minimumNoticeMinutes * 60))
        let bufferedBusyIntervals = busyIntervals.map {
            buffered(
                $0.interval,
                before: appointmentType.bufferBeforeMinutes,
                after: appointmentType.bufferAfterMinutes
            )
        }
        var cursor = roundedUpToSlotStep(max(start, minimumStart), calendar: calendar)
        var slots: [BookingOpenSlot] = []

        while cursor.addingTimeInterval(duration) <= end {
            let interval = DateInterval(start: cursor, duration: duration)
            if !bufferedBusyIntervals.contains(where: { overlaps($0, interval) }) {
                let slotID = BookingSlotID("\(appointmentType.slug)-\(Int(cursor.timeIntervalSince1970))")
                let claim = BookingSlotClaim(
                    appointmentTypeID: appointmentType.id,
                    slotID: slotID,
                    startsAt: interval.start,
                    endsAt: interval.end,
                    generatedAt: generatedAt,
                    expiresAt: interval.start,
                    nonce: UUID().uuidString.lowercased(),
                    signingKeyVersion: "v1"
                )
                slots.append(
                    BookingOpenSlot(
                        id: slotID,
                        appointmentTypeID: appointmentType.id,
                        interval: interval,
                        token: try tokenFactory(claim)
                    )
                )
            }

            cursor = cursor.addingTimeInterval(step)
        }

        return slots
    }

    private static func date(on day: Date, minuteOfDay: Int, calendar: Calendar) throws -> Date {
        guard minuteOfDay >= 0, minuteOfDay <= 24 * 60 else {
            throw BookingConfigurationError.invalidField("Working hours must stay within one day.")
        }

        let hour = minuteOfDay / 60
        let minute = minuteOfDay % 60
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = hour
        components.minute = minute
        components.second = 0

        guard let date = calendar.date(from: components) else {
            throw BookingConfigurationError.invalidField("Working hours could not be converted to dates.")
        }

        return date
    }

    private static func buffered(_ interval: DateInterval, before: Int, after: Int) -> DateInterval {
        let start = interval.start.addingTimeInterval(-TimeInterval(max(0, before) * 60))
        let end = interval.end.addingTimeInterval(TimeInterval(max(0, after) * 60))
        return DateInterval(start: start, end: max(start, end))
    }

    private static func roundedUpToSlotStep(_ date: Date, calendar: Calendar) -> Date {
        let stepMinutes = 15
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard
            let minute = components.minute,
            let floored = calendar.date(from: components)
        else {
            return date
        }

        let remainder = minute % stepMinutes
        if remainder == 0 && date == floored {
            return date
        }

        return floored.addingTimeInterval(TimeInterval((stepMinutes - remainder) * 60))
    }

    private static func overlaps(_ lhs: DateInterval, _ rhs: DateInterval) -> Bool {
        lhs.start < rhs.end && rhs.start < lhs.end
    }
}
