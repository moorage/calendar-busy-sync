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
}
