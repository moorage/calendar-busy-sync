import EventKit
import Foundation

protocol AppleCalendarProviding: AnyObject {
    func authorizationState() -> AppleCalendarAuthorizationState
    func requestAccessIfNeeded() async throws -> AppleCalendarAuthorizationState
    func listWritableCalendars() throws -> [AppleCalendarSummary]
    func createManagedBusyEvent(in calendar: AppleCalendarSummary) throws -> AppleManagedEventRecord
    func deleteManagedBusyEvent(_ event: AppleManagedEventRecord) throws
    func listBusySourceEvents(in participant: BusyMirrorParticipant, window: DateInterval) throws -> [BusyMirrorSourceEvent]
    func listManagedMirrorEvents(in participant: BusyMirrorParticipant, window: DateInterval) throws -> [ExistingBusyMirrorEvent]
    func createManagedMirrorEvent(in calendar: AppleCalendarSummary, desiredMirror: DesiredBusyMirrorEvent) throws
    func updateManagedMirrorEvent(_ existingMirror: ExistingBusyMirrorEvent, desiredMirror: DesiredBusyMirrorEvent) throws
    func deleteManagedMirrorEvent(_ existingMirror: ExistingBusyMirrorEvent) throws
}

enum AppleCalendarServiceError: LocalizedError, Equatable {
    case notConnected
    case accessDenied
    case accessRestricted
    case calendarNotFound
    case managedEventMissing
    case requestFailed(String)
    case invalidManagedMetadata

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Connect Apple / iCloud Calendar before loading calendars or writing busy slots."
        case .accessDenied:
            return "Calendar access is denied for this app. Re-enable it in System Settings > Privacy & Security > Calendars."
        case .accessRestricted:
            return "Calendar access is restricted on this device."
        case .calendarNotFound:
            return "The selected Apple calendar is no longer available on this device."
        case .managedEventMissing:
            return "The managed busy slot is no longer present in the selected Apple calendar."
        case let .requestFailed(message):
            return message
        case .invalidManagedMetadata:
            return "Apple Calendar returned a managed mirror event with invalid metadata."
        }
    }
}

@MainActor
final class AppleCalendarService: AppleCalendarProviding {
    private let eventStore: EKEventStore
    private let mirrorIdentityStore: AppleMirrorIdentityStoring
    private let now: () -> Date
    private let timeZone: () -> TimeZone

    init(
        eventStore: EKEventStore = EKEventStore(),
        mirrorIdentityStore: AppleMirrorIdentityStoring = AppleMirrorIdentityStore(),
        now: @escaping () -> Date = Date.init,
        timeZone: @escaping () -> TimeZone = { .current }
    ) {
        self.eventStore = eventStore
        self.mirrorIdentityStore = mirrorIdentityStore
        self.now = now
        self.timeZone = timeZone
    }

    func authorizationState() -> AppleCalendarAuthorizationState {
        Self.authorizationState(from: EKEventStore.authorizationStatus(for: .event))
    }

    func requestAccessIfNeeded() async throws -> AppleCalendarAuthorizationState {
        switch authorizationState() {
        case .granted:
            return .granted
        case .denied:
            throw AppleCalendarServiceError.accessDenied
        case .restricted:
            throw AppleCalendarServiceError.accessRestricted
        case .notDetermined:
            try await requestCalendarAccess()
            switch authorizationState() {
            case .granted:
                return .granted
            case .restricted:
                throw AppleCalendarServiceError.accessRestricted
            case .denied, .notDetermined:
                throw AppleCalendarServiceError.accessDenied
            }
        }
    }

    func listWritableCalendars() throws -> [AppleCalendarSummary] {
        try requireGrantedAuthorization()

        return eventStore.calendars(for: .event)
            .filter(\.allowsContentModifications)
            .map(Self.summary(from:))
            .sorted { lhs, rhs in
                if lhs.isLikelyICloud != rhs.isLikelyICloud {
                    return lhs.isLikelyICloud && !rhs.isLikelyICloud
                }

                let titleComparison = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
                if titleComparison != .orderedSame {
                    return titleComparison == .orderedAscending
                }

                return lhs.sourceDisplayName.localizedCaseInsensitiveCompare(rhs.sourceDisplayName) == .orderedAscending
            }
    }

    func createManagedBusyEvent(in calendar: AppleCalendarSummary) throws -> AppleManagedEventRecord {
        try requireGrantedAuthorization()

        guard let writableCalendar = eventStore.calendar(withIdentifier: calendar.id) else {
            throw AppleCalendarServiceError.calendarNotFound
        }

        let draft = ManagedAppleBusyEventDraft.verification(now: now(), timeZone: timeZone())
        let event = EKEvent(eventStore: eventStore)
        event.calendar = writableCalendar
        event.title = draft.summary
        event.notes = draft.notes
        event.startDate = draft.startDate
        event.endDate = draft.endDate
        event.availability = .busy
        event.isAllDay = false

        do {
            try eventStore.save(event, span: .thisEvent, commit: true)
        } catch {
            throw AppleCalendarServiceError.requestFailed(
                "Apple Calendar could not create the managed busy slot. Try again from the current app window."
            )
        }

        return AppleManagedEventRecord(
            calendarID: calendar.id,
            calendarName: calendar.displayName,
            eventID: event.eventIdentifier,
            summary: draft.summary,
            windowDescription: draft.windowDescription
        )
    }

    func deleteManagedBusyEvent(_ event: AppleManagedEventRecord) throws {
        try requireGrantedAuthorization()

        guard let managedEvent = eventStore.event(withIdentifier: event.eventID) else {
            throw AppleCalendarServiceError.managedEventMissing
        }

        do {
            try eventStore.remove(managedEvent, span: .thisEvent, commit: true)
        } catch {
            throw AppleCalendarServiceError.requestFailed(
                "Apple Calendar could not delete the managed busy slot. Try again from the current app window."
            )
        }
    }

    func listBusySourceEvents(in participant: BusyMirrorParticipant, window: DateInterval) throws -> [BusyMirrorSourceEvent] {
        try requireGrantedAuthorization()

        guard let calendar = eventStore.calendar(withIdentifier: participant.calendarID) else {
            throw AppleCalendarServiceError.calendarNotFound
        }

        return try events(in: calendar, window: window).compactMap { event in
            guard try !isManagedMirrorEvent(event) else {
                return nil
            }
            guard event.isEligibleSourceEvent else {
                return nil
            }

            return BusyMirrorSourceEvent(
                key: BusyMirrorSourceKey(
                    provider: .apple,
                    calendarID: participant.calendarID,
                    eventID: event.eventIdentifier
                ),
                participantID: participant.id,
                startDate: event.startDate,
                endDate: event.endDate,
                isAllDay: event.isAllDay
            )
        }
    }

    func listManagedMirrorEvents(in participant: BusyMirrorParticipant, window: DateInterval) throws -> [ExistingBusyMirrorEvent] {
        try requireGrantedAuthorization()

        guard let calendar = eventStore.calendar(withIdentifier: participant.calendarID) else {
            throw AppleCalendarServiceError.calendarNotFound
        }

        return try events(in: calendar, window: window).compactMap { event in
            let resolution = try resolveManagedMirror(for: event)

            switch resolution {
            case let .resolved(sourceKey, _):
                return ExistingBusyMirrorEvent(
                    identity: BusyMirrorIdentity(
                        sourceKey: sourceKey,
                        targetParticipantID: participant.id
                    ),
                    targetParticipant: participant,
                    eventID: event.eventIdentifier,
                    startDate: event.startDate,
                    endDate: event.endDate,
                    isAllDay: event.isAllDay
                )
            case let .orphaned(token):
                try removeOrphanedManagedMirrorEvent(event, token: token)
                return nil
            case .none:
                return nil
            }
        }
    }

    func createManagedMirrorEvent(in calendar: AppleCalendarSummary, desiredMirror: DesiredBusyMirrorEvent) throws {
        try requireGrantedAuthorization()

        guard let writableCalendar = eventStore.calendar(withIdentifier: calendar.id) else {
            throw AppleCalendarServiceError.calendarNotFound
        }

        let event = EKEvent(eventStore: eventStore)
        event.calendar = writableCalendar
        let token = AppleManagedMirrorMarker.makeToken()
        applyManagedMirror(desiredMirror, to: event, token: token)

        do {
            try eventStore.save(event, span: .thisEvent, commit: true)
            try mirrorIdentityStore.setSourceKey(desiredMirror.identity.sourceKey, for: token)
        } catch {
            throw AppleCalendarServiceError.requestFailed(
                "Apple Calendar could not create a mirrored busy slot during sync."
            )
        }
    }

    func updateManagedMirrorEvent(_ existingMirror: ExistingBusyMirrorEvent, desiredMirror: DesiredBusyMirrorEvent) throws {
        try requireGrantedAuthorization()

        guard let event = eventStore.event(withIdentifier: existingMirror.eventID) else {
            throw AppleCalendarServiceError.managedEventMissing
        }

        let token = AppleManagedMirrorMarker(url: event.url)?.token ?? AppleManagedMirrorMarker.makeToken()
        applyManagedMirror(desiredMirror, to: event, token: token)

        do {
            try eventStore.save(event, span: .thisEvent, commit: true)
            try mirrorIdentityStore.setSourceKey(desiredMirror.identity.sourceKey, for: token)
        } catch {
            throw AppleCalendarServiceError.requestFailed(
                "Apple Calendar could not update a mirrored busy slot during sync."
            )
        }
    }

    func deleteManagedMirrorEvent(_ existingMirror: ExistingBusyMirrorEvent) throws {
        try requireGrantedAuthorization()

        guard let event = eventStore.event(withIdentifier: existingMirror.eventID) else {
            throw AppleCalendarServiceError.managedEventMissing
        }

        do {
            try eventStore.remove(event, span: .thisEvent, commit: true)
            if let token = AppleManagedMirrorMarker(url: event.url)?.token {
                try mirrorIdentityStore.removeSourceKey(for: token)
            }
        } catch {
            throw AppleCalendarServiceError.requestFailed(
                "Apple Calendar could not delete a stale mirrored busy slot during sync."
            )
        }
    }

    private func requestCalendarAccess() async throws {
        do {
            if #available(iOS 17.0, macOS 14.0, *) {
                _ = try await eventStore.requestFullAccessToEvents()
            } else {
                _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
                    eventStore.requestAccess(to: .event) { granted, error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(returning: granted)
                        }
                    }
                }
            }
        } catch {
            throw AppleCalendarServiceError.requestFailed(
                "Apple Calendar permission could not be requested from this app session."
            )
        }
    }

    private func requireGrantedAuthorization() throws {
        switch authorizationState() {
        case .granted:
            return
        case .denied:
            throw AppleCalendarServiceError.accessDenied
        case .restricted:
            throw AppleCalendarServiceError.accessRestricted
        case .notDetermined:
            throw AppleCalendarServiceError.notConnected
        }
    }

    private func events(in calendar: EKCalendar, window: DateInterval) throws -> [EKEvent] {
        let predicate = eventStore.predicateForEvents(
            withStart: window.start,
            end: window.end,
            calendars: [calendar]
        )
        return eventStore.events(matching: predicate)
    }

    private func applyManagedMirror(_ desiredMirror: DesiredBusyMirrorEvent, to event: EKEvent, token: String) {
        event.title = "Busy"
        event.notes = ManagedAppleMirrorNotes.userVisibleNote
        event.url = AppleManagedMirrorMarker(token: token).url
        event.startDate = desiredMirror.startDate
        event.endDate = desiredMirror.endDate
        event.availability = .busy
        event.isAllDay = desiredMirror.isAllDay
    }

    private func isManagedMirrorEvent(_ event: EKEvent) throws -> Bool {
        switch try resolveManagedMirror(for: event) {
        case .none:
            return false
        case .resolved, .orphaned:
            return true
        }
    }

    private func resolveManagedMirror(for event: EKEvent) throws -> AppleManagedMirrorResolution {
        if let marker = AppleManagedMirrorMarker(url: event.url) {
            if let sourceKey = try mirrorIdentityStore.sourceKey(for: marker.token) {
                return .resolved(sourceKey: sourceKey, token: marker.token)
            }

            if let legacySourceKey = ManagedAppleMirrorNotes.legacySourceKey(from: event.notes) {
                try migrateManagedMirror(event, token: marker.token, sourceKey: legacySourceKey)
                return .resolved(sourceKey: legacySourceKey, token: marker.token)
            }

            return .orphaned(token: marker.token)
        }

        guard let legacySourceKey = ManagedAppleMirrorNotes.legacySourceKey(from: event.notes) else {
            return .none
        }

        let token = AppleManagedMirrorMarker.makeToken()
        try migrateManagedMirror(event, token: token, sourceKey: legacySourceKey)
        return .resolved(sourceKey: legacySourceKey, token: token)
    }

    private func migrateManagedMirror(
        _ event: EKEvent,
        token: String,
        sourceKey: BusyMirrorSourceKey
    ) throws {
        event.notes = ManagedAppleMirrorNotes.userVisibleNote
        event.url = AppleManagedMirrorMarker(token: token).url

        do {
            try eventStore.save(event, span: .thisEvent, commit: true)
            try mirrorIdentityStore.setSourceKey(sourceKey, for: token)
        } catch {
            throw AppleCalendarServiceError.requestFailed(
                "Apple Calendar could not migrate an existing mirrored busy slot to the compact metadata format."
            )
        }
    }

    private func removeOrphanedManagedMirrorEvent(_ event: EKEvent, token: String) throws {
        do {
            try eventStore.remove(event, span: .thisEvent, commit: true)
            try mirrorIdentityStore.removeSourceKey(for: token)
        } catch {
            throw AppleCalendarServiceError.requestFailed(
                "Apple Calendar could not remove an orphaned mirrored busy slot after local metadata was lost."
            )
        }
    }

    private static func authorizationState(from status: EKAuthorizationStatus) -> AppleCalendarAuthorizationState {
        if #available(iOS 17.0, macOS 14.0, *) {
            switch status {
            case .authorized, .fullAccess, .writeOnly:
                return .granted
            case .denied:
                return .denied
            case .restricted:
                return .restricted
            case .notDetermined:
                return .notDetermined
            @unknown default:
                return .denied
            }
        }

        switch status {
        case .authorized:
            return .granted
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .denied
        }
    }

    private static func summary(from calendar: EKCalendar) -> AppleCalendarSummary {
        AppleCalendarSummary(
            id: calendar.calendarIdentifier,
            title: calendar.title,
            sourceTitle: calendar.source.title,
            sourceKind: sourceKind(from: calendar.source)
        )
    }

    private static func sourceKind(from source: EKSource) -> AppleCalendarSourceKind {
        if source.title.localizedCaseInsensitiveContains("icloud") {
            return .iCloud
        }

        switch source.sourceType {
        case .mobileMe:
            return .iCloud
        case .calDAV:
            return .calDAV
        case .exchange:
            return .exchange
        case .local:
            return .local
        case .subscribed:
            return .subscribed
        case .birthdays:
            return .birthdays
        default:
            return .other
        }
    }
}

private enum ManagedAppleMirrorNotes {
    static let userVisibleNote = "Managed by Calendar Busy Sync mirror reconciliation."

    private static let managedPrefix = "calendarBusySyncManaged=true"
    private static let kindPrefix = "calendarBusySyncKind=mirror"
    private static let sourceProviderPrefix = "calendarBusySyncSourceProvider="
    private static let sourceCalendarPrefix = "calendarBusySyncSourceCalendarID="
    private static let sourceEventPrefix = "calendarBusySyncSourceEventID="

    static func legacySourceKey(from notes: String?) -> BusyMirrorSourceKey? {
        guard let notes else {
            return nil
        }

        var providerRawValue: String?
        var calendarID: String?
        var eventID: String?
        var isManaged = false
        var isMirror = false

        for line in notes.components(separatedBy: .newlines) {
            if line == managedPrefix {
                isManaged = true
            } else if line == kindPrefix {
                isMirror = true
            } else if line.hasPrefix(sourceProviderPrefix) {
                providerRawValue = String(line.dropFirst(sourceProviderPrefix.count))
            } else if line.hasPrefix(sourceCalendarPrefix) {
                calendarID = String(line.dropFirst(sourceCalendarPrefix.count))
            } else if line.hasPrefix(sourceEventPrefix) {
                eventID = String(line.dropFirst(sourceEventPrefix.count))
            }
        }

        guard
            isManaged,
            isMirror,
            let providerRawValue,
            let provider = BusyMirrorProvider(rawValue: providerRawValue),
            let calendarID,
            let eventID
        else {
            return nil
        }

        return BusyMirrorSourceKey(
            provider: provider,
            calendarID: calendarID,
            eventID: eventID
        )
    }
}

private enum AppleManagedMirrorResolution {
    case none
    case resolved(sourceKey: BusyMirrorSourceKey, token: String)
    case orphaned(token: String)
}

private extension EKEvent {
    var blocksTime: Bool {
        switch availability {
        case .free:
            return false
        default:
            return true
        }
    }

    var isEligibleSourceEvent: Bool {
        AppleMirrorEligibility.shouldMirror(
            blocksTime: blocksTime,
            organizerIsCurrentUser: organizer?.isCurrentUser == true,
            hasAttendees: hasAttendees,
            currentUserParticipantStatus: attendees?.first(where: \.isCurrentUser)?.participantStatus
        )
    }
}

private struct ManagedAppleBusyEventDraft {
    let summary: String
    let notes: String
    let startDate: Date
    let endDate: Date
    let windowDescription: String

    static func verification(now: Date, timeZone: TimeZone) -> ManagedAppleBusyEventDraft {
        let roundedStart = roundedUpToFiveMinutes(now)
        let endDate = roundedStart.addingTimeInterval(30 * 60)
        let displayFormatter = DateFormatter()
        displayFormatter.locale = Locale(identifier: "en_US_POSIX")
        displayFormatter.timeZone = timeZone
        displayFormatter.dateFormat = "MMM d, HH:mm z"

        return ManagedAppleBusyEventDraft(
            summary: "Busy",
            notes: """
            Managed by Calendar Busy Sync verification flow.
            calendarBusySyncManaged=true
            calendarBusySyncKind=verification
            """,
            startDate: roundedStart,
            endDate: endDate,
            windowDescription: "\(displayFormatter.string(from: roundedStart)) - \(displayFormatter.string(from: endDate))"
        )
    }

    private static func roundedUpToFiveMinutes(_ date: Date) -> Date {
        let interval = date.timeIntervalSinceReferenceDate
        let step = 5.0 * 60.0
        let rounded = ceil(interval / step) * step
        return Date(timeIntervalSinceReferenceDate: rounded)
    }
}
