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
        existingMirrors: [ExistingBusyMirrorEvent]
    ) -> [BusyMirrorOperation] {
        let desiredByIdentity = Dictionary(uniqueKeysWithValues: desiredMirrors.map { ($0.identity, $0) })
        let existingByIdentity = Dictionary(uniqueKeysWithValues: existingMirrors.map { ($0.identity, $0) })

        var operations: [BusyMirrorOperation] = []

        for desiredMirror in desiredMirrors {
            if let existingMirror = existingByIdentity[desiredMirror.identity] {
                if requiresUpdate(existing: existingMirror, desired: desiredMirror) {
                    operations.append(.update(existing: existingMirror, desired: desiredMirror))
                }
            } else {
                operations.append(.create(desiredMirror))
            }
        }

        for existingMirror in existingMirrors where desiredByIdentity[existingMirror.identity] == nil {
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
    }
}
