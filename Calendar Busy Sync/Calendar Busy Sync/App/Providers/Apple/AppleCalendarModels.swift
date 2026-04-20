import Foundation

enum AppleCalendarAuthorizationState: String, Equatable {
    case notDetermined
    case granted
    case denied
    case restricted
}

enum AppleCalendarSourceKind: String, Codable, Equatable {
    case iCloud
    case calDAV
    case exchange
    case local
    case subscribed
    case birthdays
    case other

    var displayLabel: String {
        switch self {
        case .iCloud:
            return "iCloud"
        case .calDAV:
            return "CalDAV"
        case .exchange:
            return "Exchange"
        case .local:
            return "On My Device"
        case .subscribed:
            return "Subscribed"
        case .birthdays:
            return "Birthdays"
        case .other:
            return "Apple Calendar"
        }
    }
}

struct AppleCalendarSummary: Equatable, Identifiable {
    let id: String
    let title: String
    let sourceTitle: String
    let sourceKind: AppleCalendarSourceKind

    var isLikelyICloud: Bool {
        sourceKind == .iCloud || sourceTitle.localizedCaseInsensitiveContains("icloud")
    }

    var sourceDisplayName: String {
        let trimmedSourceTitle = sourceTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSourceTitle.isEmpty {
            return trimmedSourceTitle
        }

        return sourceKind.displayLabel
    }

    var displayName: String {
        let source = sourceDisplayName
        if source.compare(title, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
            return title
        }

        return "\(title) • \(source)"
    }

    func matches(name: String) -> Bool {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            return false
        }

        if title.compare(normalizedName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
            return true
        }

        return displayName.compare(normalizedName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    func matches(reference: SharedAppleCalendarReference) -> Bool {
        guard sourceKind == reference.sourceKind else {
            return false
        }

        return title.compare(reference.title, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            && sourceTitle.compare(reference.sourceTitle, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
}

struct AppleManagedEventRecord: Equatable, Identifiable {
    let calendarID: String
    let calendarName: String
    let eventID: String
    let summary: String
    let windowDescription: String

    var id: String {
        "\(calendarID)|\(eventID)"
    }
}

enum AppleCalendarSelectionResolver {
    static func resolvedCalendarID(
        availableCalendars: [AppleCalendarSummary],
        persistedCalendarID: String,
        sharedReference: SharedAppleCalendarReference? = nil
    ) -> String {
        if availableCalendars.contains(where: { $0.id == persistedCalendarID }) {
            return persistedCalendarID
        }

        if
            let sharedReference,
            let matchedCalendar = availableCalendars.first(where: { $0.matches(reference: sharedReference) })
        {
            return matchedCalendar.id
        }

        if let iCloudCalendar = availableCalendars.first(where: \.isLikelyICloud) {
            return iCloudCalendar.id
        }

        return availableCalendars.first?.id ?? ""
    }
}
