import Foundation

enum GoogleCalendarAccessRole: String, Codable, Equatable {
    case owner
    case writer
    case reader
    case freeBusyReader

    var canWrite: Bool {
        self == .owner || self == .writer
    }
}

struct GoogleCalendarSummary: Codable, Equatable, Identifiable {
    let id: String
    let summary: String
    let accessRole: GoogleCalendarAccessRole
    let primary: Bool?
    let timeZone: String?

    var isPrimary: Bool {
        primary ?? false
    }

    var displayName: String {
        isPrimary ? "\(summary) (Primary)" : summary
    }

    func matches(name: String) -> Bool {
        summary.compare(name.trimmingCharacters(in: .whitespacesAndNewlines), options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
}

struct GoogleManagedEventRecord: Equatable, Identifiable {
    let calendarID: String
    let calendarName: String
    let eventID: String
    let summary: String
    let windowDescription: String

    var id: String {
        "\(calendarID)|\(eventID)"
    }
}

enum GoogleCalendarSelectionResolver {
    static func resolvedCalendarID(
        availableCalendars: [GoogleCalendarSummary],
        persistedCalendarID: String,
        preferredCalendarName: String?
    ) -> String {
        if availableCalendars.contains(where: { $0.id == persistedCalendarID }) {
            return persistedCalendarID
        }

        if
            let preferredCalendarName,
            let match = availableCalendars.first(where: { $0.matches(name: preferredCalendarName) })
        {
            return match.id
        }

        if let primary = availableCalendars.first(where: \.isPrimary) {
            return primary.id
        }

        return availableCalendars.first?.id ?? ""
    }
}
