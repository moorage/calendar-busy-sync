import Foundation

enum BusyMirrorProvider: String, Codable, Hashable {
    case google
    case apple
}

struct BusyMirrorParticipant: Identifiable, Equatable, Hashable {
    let provider: BusyMirrorProvider
    let accountID: String?
    let calendarID: String
    let displayName: String

    var id: String {
        switch provider {
        case .google:
            return "google|\(accountID ?? "unknown")|\(calendarID)"
        case .apple:
            return "apple|\(calendarID)"
        }
    }
}

struct BusyMirrorSourceKey: Codable, Equatable, Hashable {
    let provider: BusyMirrorProvider
    let calendarID: String
    let eventID: String
}

struct BusyMirrorSourceEvent: Equatable, Hashable, Identifiable {
    let key: BusyMirrorSourceKey
    let participantID: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool

    var id: String {
        "\(key.provider.rawValue)|\(key.calendarID)|\(key.eventID)"
    }
}

struct BusyMirrorIdentity: Codable, Equatable, Hashable, Identifiable {
    let sourceKey: BusyMirrorSourceKey
    let targetParticipantID: String

    var id: String {
        "\(sourceKey.provider.rawValue)|\(sourceKey.calendarID)|\(sourceKey.eventID)|\(targetParticipantID)"
    }
}

struct BusyMirrorOccupancyKey: Equatable, Hashable, Identifiable {
    let targetParticipantID: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool

    var id: String {
        "\(targetParticipantID)|\(startDate.timeIntervalSinceReferenceDate)|\(endDate.timeIntervalSinceReferenceDate)|\(isAllDay)"
    }
}

struct DesiredBusyMirrorEvent: Equatable, Hashable, Identifiable {
    let identity: BusyMirrorIdentity
    let targetParticipant: BusyMirrorParticipant
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool

    var id: String { identity.id }

    var occupancyKey: BusyMirrorOccupancyKey {
        BusyMirrorOccupancyKey(
            targetParticipantID: targetParticipant.id,
            startDate: startDate,
            endDate: endDate,
            isAllDay: isAllDay
        )
    }
}

struct ExistingBusyMirrorEvent: Equatable, Hashable, Identifiable {
    let identity: BusyMirrorIdentity
    let targetParticipant: BusyMirrorParticipant
    let eventID: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool

    var id: String {
        "\(identity.id)|\(eventID)"
    }

    var occupancyKey: BusyMirrorOccupancyKey {
        BusyMirrorOccupancyKey(
            targetParticipantID: targetParticipant.id,
            startDate: startDate,
            endDate: endDate,
            isAllDay: isAllDay
        )
    }
}

struct BusyMirrorTargetBusyBlock: Equatable, Hashable, Identifiable {
    let targetParticipant: BusyMirrorParticipant
    let eventID: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let managedMirrorIdentity: BusyMirrorIdentity?

    var id: String {
        "\(targetParticipant.id)|\(eventID)"
    }

    var occupancyKey: BusyMirrorOccupancyKey {
        BusyMirrorOccupancyKey(
            targetParticipantID: targetParticipant.id,
            startDate: startDate,
            endDate: endDate,
            isAllDay: isAllDay
        )
    }

    var isManagedMirror: Bool {
        managedMirrorIdentity != nil
    }
}

enum BusyMirrorOperation: Equatable {
    case create(DesiredBusyMirrorEvent)
    case update(existing: ExistingBusyMirrorEvent, desired: DesiredBusyMirrorEvent)
    case delete(ExistingBusyMirrorEvent)
}

struct BusyMirrorSyncSummary: Equatable {
    let participantCount: Int
    let sourceEventCount: Int
    let createdCount: Int
    let updatedCount: Int
    let deletedCount: Int
    let failedCount: Int
    let completedAt: Date
    let failureMessages: [String]

    var status: String {
        failedCount == 0 ? "ready" : "degraded"
    }
}

enum BusyMirrorSyncWindow {
    static func defaultWindow(now: Date = Date()) -> DateInterval {
        DateInterval(
            start: now.addingTimeInterval(-24 * 60 * 60),
            end: now.addingTimeInterval(60 * 24 * 60 * 60)
        )
    }
}
