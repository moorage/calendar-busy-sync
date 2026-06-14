import Foundation

protocol BookingInviteFileWriting {
    func writeInviteFile(for request: BookingImportedRequest, calendarName: String) throws -> URL
    func writeDeclineFile(for request: BookingImportedRequest, calendarName: String) throws -> URL
}

struct BookingInviteFileWriter: BookingInviteFileWriting {
    private let fileManager: FileManager
    private let now: () -> Date

    init(
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init
    ) {
        self.fileManager = fileManager
        self.now = now
    }

    func writeInviteFile(for request: BookingImportedRequest, calendarName: String) throws -> URL {
        let data = BookingInviteICSGenerator.makeICS(
            for: request,
            calendarName: calendarName,
            now: now(),
            disposition: .request
        )
        return try write(data, fileName: "Calendar Busy Sync Booking \(request.id.rawValue).ics")
    }

    func writeDeclineFile(for request: BookingImportedRequest, calendarName: String) throws -> URL {
        let data = BookingInviteICSGenerator.makeICS(
            for: request,
            calendarName: calendarName,
            now: now(),
            disposition: .decline
        )
        return try write(data, fileName: "Calendar Busy Sync Declined Booking \(request.id.rawValue).ics")
    }

    private func write(_ data: Data, fileName: String) throws -> URL {
        var lastError: Error?
        for directory in candidateInviteDirectories() {
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
                let fileURL = directory.appendingPathComponent(fileName)
                try data.write(to: fileURL, options: .atomic)
                return fileURL
            } catch {
                lastError = error
            }
        }

        throw lastError ?? CocoaError(.fileWriteUnknown)
    }

    private func candidateInviteDirectories() -> [URL] {
        var directories: [URL] = []
        directories.append(contentsOf: fileManager.urls(for: .downloadsDirectory, in: .userDomainMask))
        directories.append(contentsOf: fileManager.urls(for: .documentDirectory, in: .userDomainMask))
        directories.append(fileManager.temporaryDirectory)

        var seen: Set<URL> = []
        return directories.filter { seen.insert($0).inserted }
    }
}

enum BookingInviteICSGenerator {
    enum Disposition {
        case request
        case decline
    }

    static func makeICS(
        for request: BookingImportedRequest,
        calendarName: String,
        now: Date,
        disposition: Disposition = .request
    ) -> Data {
        let summary = summary(for: request, disposition: disposition)
        let description = description(for: request, disposition: disposition)
        let visitor = request.plaintext.visitor
        let visitorName = visitor.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let bookerEmail = visitor.email.trimmingCharacters(in: .whitespacesAndNewlines)
        let organizerName = calendarName.trimmingCharacters(in: .whitespacesAndNewlines)
        let organizerDisplayName = organizerName.isEmpty ? "Calendar Busy Sync" : organizerName
        let organizerEmail = organizerEmail(for: request, disposition: disposition)
        let attendees = request.inviteeEmails

        var lines = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//Calendar Busy Sync//Privacy First Booking//EN",
            "CALSCALE:GREGORIAN",
            "METHOD:\(method(for: disposition))",
            "BEGIN:VEVENT",
            "UID:\(escapeText(request.id.rawValue))@calendar-busy-sync.local",
            "DTSTAMP:\(formatDate(now))",
            "DTSTART:\(formatDate(request.slotClaim.startsAt))",
            "DTEND:\(formatDate(request.slotClaim.endsAt))",
            "SUMMARY:\(escapeText(summary))",
            "DESCRIPTION:\(escapeText(description))",
            "ORGANIZER;CN=\(parameterValue(organizerDisplayName)):mailto:\(organizerEmail)",
        ]

        if disposition == .decline {
            lines.append(
                "ATTENDEE;CN=\(parameterValue(organizerDisplayName));ROLE=REQ-PARTICIPANT;PARTSTAT=DECLINED;RSVP=FALSE:mailto:calendar-busy-sync@example.invalid"
            )
        }

        for email in attendees {
            let attendeeName = email.compare(bookerEmail, options: .caseInsensitive) == .orderedSame
                ? (visitorName.isEmpty ? email : visitorName)
                : email
            lines.append(
                "ATTENDEE;CN=\(parameterValue(attendeeName));ROLE=REQ-PARTICIPANT;PARTSTAT=NEEDS-ACTION;RSVP=TRUE:mailto:\(email)"
            )
        }

        lines.append(contentsOf: [
            "TRANSP:OPAQUE",
            "STATUS:\(status(for: disposition))",
            "SEQUENCE:0",
            "END:VEVENT",
            "END:VCALENDAR",
        ])

        return Data((lines.map(foldLine).joined(separator: "\r\n") + "\r\n").utf8)
    }

    private static func summary(for request: BookingImportedRequest, disposition: Disposition) -> String {
        switch disposition {
        case .request:
            return BookingCalendarEventContent.summary(for: request)
        case .decline:
            return "Declined: \(BookingCalendarEventContent.summary(for: request))"
        }
    }

    private static func description(for request: BookingImportedRequest, disposition: Disposition) -> String {
        let base = BookingCalendarEventContent.description(for: request)
        switch disposition {
        case .request:
            return base
        case .decline:
            return "Request declined through Calendar Busy Sync Booking.\n\(base)"
        }
    }

    private static func organizerEmail(for request: BookingImportedRequest, disposition: Disposition) -> String {
        switch disposition {
        case .request:
            return "calendar-busy-sync@example.invalid"
        case .decline:
            return request.plaintext.visitor.email.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func method(for disposition: Disposition) -> String {
        switch disposition {
        case .request:
            return "REQUEST"
        case .decline:
            return "REPLY"
        }
    }

    private static func status(for disposition: Disposition) -> String {
        switch disposition {
        case .request:
            return "CONFIRMED"
        case .decline:
            return "CANCELLED"
        }
    }

    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: date)
    }

    private static func escapeText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\n")
    }

    private static func parameterValue(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static func foldLine(_ line: String) -> String {
        guard line.count > 74 else {
            return line
        }

        var remaining = line
        var parts: [String] = []
        while remaining.count > 74 {
            let index = remaining.index(remaining.startIndex, offsetBy: 74)
            parts.append(String(remaining[..<index]))
            remaining = String(remaining[index...])
        }
        parts.append(remaining)
        return parts.enumerated().map { index, part in
            index == 0 ? part : " \(part)"
        }.joined(separator: "\r\n")
    }
}
