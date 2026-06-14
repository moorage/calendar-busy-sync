import Foundation

enum BookingCalendarEventContent {
    static func summary(for request: BookingImportedRequest) -> String {
        "Meeting with \(request.visitorDisplayName)"
    }

    static func description(for request: BookingImportedRequest) -> String {
        let visitor = request.plaintext.visitor
        let trimmedName = visitor.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = visitor.email.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = visitor.topic.trimmingCharacters(in: .whitespacesAndNewlines)
        let notesLine = notes.isEmpty ? "No notes provided." : notes
        let guestLine = request.inviteeEmails
            .filter { $0.compare(trimmedEmail, options: .caseInsensitive) != .orderedSame }
            .joined(separator: ", ")

        var lines = [
            "Requested through Calendar Busy Sync Booking.",
            "Booker: \(trimmedName.isEmpty ? trimmedEmail : trimmedName)",
            "Email: \(trimmedEmail)",
        ]
        if !guestLine.isEmpty {
            lines.append("Guests: \(guestLine)")
        }
        lines.append("Notes: \(notesLine)")
        lines.append("Request ID: \(request.id.rawValue)")
        return lines.joined(separator: "\n")
    }

    static func windowDescription(
        start: Date,
        end: Date,
        timeZone: TimeZone
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "MMM d, HH:mm z"
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }
}
