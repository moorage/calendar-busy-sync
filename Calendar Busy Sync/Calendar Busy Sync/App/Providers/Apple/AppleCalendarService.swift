import EventKit
import Foundation

protocol AppleCalendarProviding: AnyObject {
    func authorizationState() -> AppleCalendarAuthorizationState
    func requestAccessIfNeeded() async throws -> AppleCalendarAuthorizationState
    func listWritableCalendars() throws -> [AppleCalendarSummary]
    func createManagedBusyEvent(in calendar: AppleCalendarSummary) throws -> AppleManagedEventRecord
    func deleteManagedBusyEvent(_ event: AppleManagedEventRecord) throws
}

enum AppleCalendarServiceError: LocalizedError, Equatable {
    case notConnected
    case accessDenied
    case accessRestricted
    case calendarNotFound
    case managedEventMissing
    case requestFailed(String)

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
        }
    }
}

@MainActor
final class AppleCalendarService: AppleCalendarProviding {
    private let eventStore: EKEventStore
    private let now: () -> Date
    private let timeZone: () -> TimeZone

    init(
        eventStore: EKEventStore = EKEventStore(),
        now: @escaping () -> Date = Date.init,
        timeZone: @escaping () -> TimeZone = { .current }
    ) {
        self.eventStore = eventStore
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

    private static func authorizationState(from status: EKAuthorizationStatus) -> AppleCalendarAuthorizationState {
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
            if #available(iOS 17.0, macOS 14.0, *) {
                switch status {
                case .fullAccess, .writeOnly:
                    return .granted
                default:
                    return .denied
                }
            }

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
