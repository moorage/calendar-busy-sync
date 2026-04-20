import Foundation

enum BusyMirrorSyncPlanner {
    static func desiredMirrors(
        participants: [BusyMirrorParticipant],
        sourceEvents: [BusyMirrorSourceEvent],
        now: Date = Date()
    ) -> [DesiredBusyMirrorEvent] {
        let participantsByID = Dictionary(uniqueKeysWithValues: participants.map { ($0.id, $0) })
        var desiredMirrors: [DesiredBusyMirrorEvent] = []

        for sourceEvent in sourceEvents {
            guard sourceEvent.endDate > now else {
                continue
            }

            let effectiveStartDate = max(sourceEvent.startDate, now)

            let sourceEventMirrors: [DesiredBusyMirrorEvent] = participants.compactMap { targetParticipant -> DesiredBusyMirrorEvent? in
                guard targetParticipant.id != sourceEvent.participantID else {
                    return nil
                }
                guard let sourceParticipant = participantsByID[sourceEvent.participantID] else {
                    return nil
                }
                guard sourceParticipant.calendarID != targetParticipant.calendarID || sourceParticipant.provider != targetParticipant.provider else {
                    return nil
                }

                return DesiredBusyMirrorEvent(
                    identity: BusyMirrorIdentity(
                        sourceKey: sourceEvent.key,
                        targetParticipantID: targetParticipant.id
                    ),
                    targetParticipant: targetParticipant,
                    startDate: effectiveStartDate,
                    endDate: sourceEvent.endDate,
                    isAllDay: sourceEvent.isAllDay
                )
            }

            desiredMirrors.append(contentsOf: sourceEventMirrors)
        }

        return desiredMirrors.sorted { lhs, rhs in
            if lhs.targetParticipant.displayName != rhs.targetParticipant.displayName {
                return lhs.targetParticipant.displayName.localizedCaseInsensitiveCompare(rhs.targetParticipant.displayName) == .orderedAscending
            }
            return lhs.identity.id < rhs.identity.id
        }
    }

    static func operations(
        desiredMirrors: [DesiredBusyMirrorEvent],
        existingMirrors: [ExistingBusyMirrorEvent],
        existingBusyBlocks: [BusyMirrorTargetBusyBlock]
    ) -> [BusyMirrorOperation] {
        var operations: [BusyMirrorOperation] = []
        var handledManagedEventIDs = Set<String>()
        let desiredByOccupancy = Dictionary(grouping: desiredMirrors, by: \.occupancyKey)
        let existingMirrorsByOccupancy = Dictionary(grouping: existingMirrors, by: \.occupancyKey)
        let existingMirrorsByIdentity = Dictionary(grouping: existingMirrors, by: \.identity)
        let busyBlocksByOccupancy = Dictionary(grouping: existingBusyBlocks, by: \.occupancyKey)

        for occupancyKey in desiredByOccupancy.keys.sorted(by: { lhs, rhs in
            if lhs.targetParticipantID != rhs.targetParticipantID {
                return lhs.targetParticipantID < rhs.targetParticipantID
            }
            if lhs.startDate != rhs.startDate {
                return lhs.startDate < rhs.startDate
            }
            if lhs.endDate != rhs.endDate {
                return lhs.endDate < rhs.endDate
            }
            if lhs.isAllDay != rhs.isAllDay {
                return lhs.isAllDay && !rhs.isAllDay
            }
            return lhs.id < rhs.id
        }) {
            guard let occupancyDesiredMirrors = desiredByOccupancy[occupancyKey], !occupancyDesiredMirrors.isEmpty else {
                continue
            }

            let occupancyExistingMirrors = existingMirrorsByOccupancy[occupancyKey] ?? []
            let occupancyBusyBlocks = busyBlocksByOccupancy[occupancyKey] ?? []
            let preferredDesiredIdentities = occupancyDesiredMirrors.compactMap { desiredMirror in
                existingMirrorsByIdentity[desiredMirror.identity] == nil ? nil : desiredMirror.identity
            }

            if occupancyBusyBlocks.contains(where: { !$0.isManagedMirror }) {
                for existingMirror in occupancyExistingMirrors {
                    operations.append(.delete(existingMirror))
                    handledManagedEventIDs.insert(existingMirror.eventID)
                }
                continue
            }

            let canonicalDesiredMirror = canonicalDesiredMirror(
                in: occupancyDesiredMirrors,
                preferredIdentities: preferredDesiredIdentities,
                preferredSourceKeys: occupancyExistingMirrors.map(\.identity.sourceKey)
            )

            if let retainedExistingMirror = retainedExistingMirror(
                in: occupancyExistingMirrors,
                existingMirrorsByIdentity: existingMirrorsByIdentity,
                preferredIdentity: canonicalDesiredMirror.identity
            ) {
                handledManagedEventIDs.insert(retainedExistingMirror.eventID)

                if requiresUpdate(existing: retainedExistingMirror, desired: canonicalDesiredMirror) {
                    operations.append(.update(existing: retainedExistingMirror, desired: canonicalDesiredMirror))
                }

                for duplicateExistingMirror in occupancyExistingMirrors where duplicateExistingMirror.eventID != retainedExistingMirror.eventID {
                    operations.append(.delete(duplicateExistingMirror))
                    handledManagedEventIDs.insert(duplicateExistingMirror.eventID)
                }
            } else {
                operations.append(.create(canonicalDesiredMirror))
            }
        }

        for existingMirror in existingMirrors where !handledManagedEventIDs.contains(existingMirror.eventID) {
            operations.append(.delete(existingMirror))
        }

        return operations
    }

    private static func requiresUpdate(
        existing: ExistingBusyMirrorEvent,
        desired: DesiredBusyMirrorEvent
    ) -> Bool {
        existing.startDate != desired.startDate
            || existing.endDate != desired.endDate
            || existing.isAllDay != desired.isAllDay
            || existing.identity != desired.identity
    }

    private static func canonicalDesiredMirror(
        in desiredMirrors: [DesiredBusyMirrorEvent],
        preferredIdentities: [BusyMirrorIdentity],
        preferredSourceKeys: [BusyMirrorSourceKey]
    ) -> DesiredBusyMirrorEvent {
        for preferredIdentity in preferredIdentities {
            if let matchingMirror = desiredMirrors.first(where: { $0.identity == preferredIdentity }) {
                return matchingMirror
            }
        }

        for preferredSourceKey in preferredSourceKeys {
            if let matchingMirror = desiredMirrors.first(where: { $0.identity.sourceKey == preferredSourceKey }) {
                return matchingMirror
            }
        }

        return desiredMirorsSorted(desiredMirrors).first!
    }

    private static func retainedExistingMirror(
        in existingMirrors: [ExistingBusyMirrorEvent],
        existingMirrorsByIdentity: [BusyMirrorIdentity: [ExistingBusyMirrorEvent]],
        preferredIdentity: BusyMirrorIdentity
    ) -> ExistingBusyMirrorEvent? {
        if let exactMatch = existingMirrors.first(where: { $0.identity == preferredIdentity }) {
            return exactMatch
        }

        if let relocatedMirrors = existingMirrorsByIdentity[preferredIdentity],
           let relocatedMatch = existingMirrorsSorted(relocatedMirrors).first {
            return relocatedMatch
        }

        return existingMirrorsSorted(existingMirrors).first
    }

    private static func desiredMirorsSorted(_ desiredMirrors: [DesiredBusyMirrorEvent]) -> [DesiredBusyMirrorEvent] {
        desiredMirrors.sorted { lhs, rhs in
            if lhs.identity.sourceKey.provider != rhs.identity.sourceKey.provider {
                return lhs.identity.sourceKey.provider.rawValue < rhs.identity.sourceKey.provider.rawValue
            }
            if lhs.identity.sourceKey.calendarID != rhs.identity.sourceKey.calendarID {
                return lhs.identity.sourceKey.calendarID < rhs.identity.sourceKey.calendarID
            }
            return lhs.identity.sourceKey.eventID < rhs.identity.sourceKey.eventID
        }
    }

    private static func existingMirrorsSorted(_ existingMirrors: [ExistingBusyMirrorEvent]) -> [ExistingBusyMirrorEvent] {
        existingMirrors.sorted { lhs, rhs in
            if lhs.identity.id != rhs.identity.id {
                return lhs.identity.id < rhs.identity.id
            }
            return lhs.eventID < rhs.eventID
        }
    }
}
