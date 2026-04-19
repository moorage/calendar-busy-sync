import Foundation

enum CalendarSelectionRole: String, Codable {
    case source = "source"
    case destination = "destination"
    case sourceAndDestination = "source-and-destination"

    var canSource: Bool {
        self == .source || self == .sourceAndDestination
    }

    var canDestination: Bool {
        self == .destination || self == .sourceAndDestination
    }

    var badgeLabel: String {
        switch self {
        case .source:
            return "Source"
        case .destination:
            return "Destination"
        case .sourceAndDestination:
            return "Source + Destination"
        }
    }
}

struct SelectedCalendar: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let role: CalendarSelectionRole
}

struct ConnectedAccountScenario: Codable, Identifiable, Equatable {
    let id: String
    let provider: String
    let displayName: String
    let selectedCalendars: [SelectedCalendar]
}

struct SourceEventScenario: Codable, Identifiable, Equatable {
    let calendarId: String
    let eventId: String
    let title: String
    let availability: String
    let start: String
    let end: String

    var id: String { eventId }

    var blocksTime: Bool {
        let normalized = availability.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized != "free" && normalized != "available"
    }
}

struct MirrorPreviewEntry: Codable, Equatable, Identifiable {
    let sourceCalendar: String
    let targetCalendar: String
    let availability: String

    var id: String {
        "\(sourceCalendar)->\(targetCalendar)->\(availability)"
    }
}

struct BusySyncScenario: Codable, Equatable {
    let scenarioName: String
    let accounts: [ConnectedAccountScenario]
    let sourceEvents: [SourceEventScenario]
    let expectedMirrorPreview: [MirrorPreviewEntry]

    static let emptyLiveShell = BusySyncScenario(
        scenarioName: "live-google-shell",
        accounts: [],
        sourceEvents: [],
        expectedMirrorPreview: []
    )
}

struct ScenarioState: Equatable {
    let scenario: BusySyncScenario
    let mirrorPreview: [MirrorPreviewEntry]

    var connectedAccountCount: Int {
        scenario.accounts.count
    }

    var selectedCalendarCount: Int {
        scenario.accounts.reduce(into: 0) { partialResult, account in
            partialResult += account.selectedCalendars.count
        }
    }

    var mirrorRuleCount: Int {
        selectedDestinationCalendars.count
    }

    var pendingWriteCount: Int {
        mirrorPreview.count
    }

    var failedWriteCount: Int {
        0
    }

    var lastSyncStatus: String {
        "ready"
    }

    private var calendarsByID: [String: SelectedCalendar] {
        scenario.accounts
            .flatMap(\.selectedCalendars)
            .reduce(into: [String: SelectedCalendar]()) { partialResult, calendar in
                partialResult[calendar.id] = calendar
            }
    }

    private var selectedDestinationCalendars: [SelectedCalendar] {
        scenario.accounts
            .flatMap(\.selectedCalendars)
            .filter(\.role.canDestination)
    }

    func selectedCalendarName(for id: String) -> String? {
        scenario.accounts
            .flatMap(\.selectedCalendars)
            .first(where: { $0.id == id })?
            .name
    }

    func auditTimestampLabel(forPreviewAt index: Int) -> String {
        guard mirrorPreview.indices.contains(index) else {
            return "Queued"
        }

        let preview = mirrorPreview[index]
        guard let sourceCalendar = scenario.accounts
            .flatMap(\.selectedCalendars)
            .first(where: { $0.name == preview.sourceCalendar }),
            let event = scenario.sourceEvents.first(where: { $0.calendarId == sourceCalendar.id && $0.blocksTime })
        else {
            return "Queued"
        }

        return event.shortStartLabel
    }

    static func build(from scenario: BusySyncScenario) -> ScenarioState {
        let calendarsByID = scenario.accounts
            .flatMap(\.selectedCalendars)
            .reduce(into: [String: SelectedCalendar]()) { partialResult, calendar in
                partialResult[calendar.id] = calendar
            }

        let destinationCalendars = scenario.accounts
            .flatMap(\.selectedCalendars)
            .filter(\.role.canDestination)

        let preview = scenario.sourceEvents.flatMap { event -> [MirrorPreviewEntry] in
            guard event.blocksTime, let sourceCalendar = calendarsByID[event.calendarId], sourceCalendar.role.canSource else {
                return []
            }

            return destinationCalendars
                .filter { $0.id != sourceCalendar.id }
                .map {
                    MirrorPreviewEntry(
                        sourceCalendar: sourceCalendar.name,
                        targetCalendar: $0.name,
                        availability: "busy"
                    )
                }
        }

        return ScenarioState(scenario: scenario, mirrorPreview: preview)
    }

    static let emptyLiveShell = ScenarioState.build(from: .emptyLiveShell)
}

extension SourceEventScenario {
    var shortStartLabel: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackFormatter = ISO8601DateFormatter()

        let parsedDate = formatter.date(from: start) ?? fallbackFormatter.date(from: start)
        guard let parsedDate else {
            return start
        }

        let display = DateFormatter()
        display.locale = Locale(identifier: "en_US_POSIX")
        display.dateFormat = "MMM d, HH:mm"
        return display.string(from: parsedDate)
    }
}
