import Foundation

enum GoogleCalendarServiceError: LocalizedError, Equatable {
    case missingAccessToken
    case invalidResponse
    case api(statusCode: Int, message: String)
    case invalidEventDate

    var errorDescription: String? {
        switch self {
        case .missingAccessToken:
            return "Google Sign-In did not return an access token for Calendar API calls."
        case .invalidResponse:
            return "Google Calendar returned an unexpected response."
        case let .api(statusCode, message):
            return "Google Calendar API error \(statusCode): \(message)"
        case .invalidEventDate:
            return "Google Calendar returned an event with an invalid date."
        }
    }
}

struct GoogleCalendarService {
    private let session: URLSession
    private let now: () -> Date
    private let timeZone: () -> TimeZone

    init(
        session: URLSession = .shared,
        now: @escaping () -> Date = Date.init,
        timeZone: @escaping () -> TimeZone = { .current }
    ) {
        self.session = session
        self.now = now
        self.timeZone = timeZone
    }

    func listWritableCalendars(accessToken: String) async throws -> [GoogleCalendarSummary] {
        let response: CalendarListResponse = try await performJSONRequest(
            accessToken: accessToken,
            method: "GET",
            path: "/calendar/v3/users/me/calendarList",
            queryItems: [
                URLQueryItem(name: "minAccessRole", value: GoogleCalendarAccessRole.writer.rawValue),
                URLQueryItem(name: "showHidden", value: "false"),
            ],
            body: Optional<InsertEventRequest>.none
        )

        return response.items.sorted {
            if $0.isPrimary != $1.isPrimary {
                return $0.isPrimary && !$1.isPrimary
            }
            return $0.summary.localizedCaseInsensitiveCompare($1.summary) == .orderedAscending
        }
    }

    func createManagedBusyEvent(
        in calendar: GoogleCalendarSummary,
        accessToken: String
    ) async throws -> GoogleManagedEventRecord {
        let draft = ManagedBusyEventDraft.verification(now: now(), timeZone: timeZone())
        let payload = InsertEventRequest(
            summary: draft.summary,
            description: draft.description,
            visibility: "private",
            transparency: "opaque",
            reminders: EventReminders(useDefault: false),
            extendedProperties: EventExtendedProperties(
                privateProperties: [
                    "calendarBusySyncManaged": "true",
                    "calendarBusySyncKind": "verification",
                ]
            ),
            start: draft.start,
            end: draft.end
        )

        let response: InsertEventResponse = try await performJSONRequest(
            accessToken: accessToken,
            method: "POST",
            path: "/calendar/v3/calendars/\(calendar.id.urlPathComponentEncoded)/events",
            queryItems: [
                URLQueryItem(name: "sendUpdates", value: "none"),
            ],
            body: payload
        )

        return GoogleManagedEventRecord(
            calendarID: calendar.id,
            calendarName: calendar.summary,
            eventID: response.id,
            summary: response.summary ?? draft.summary,
            windowDescription: draft.windowDescription
        )
    }

    func listBusySourceEvents(
        in participant: BusyMirrorParticipant,
        calendarTimeZone: String?,
        window: DateInterval,
        accessToken: String
    ) async throws -> [BusyMirrorSourceEvent] {
        let response: CalendarEventsResponse = try await performJSONRequest(
            accessToken: accessToken,
            method: "GET",
            path: "/calendar/v3/calendars/\(participant.calendarID.urlPathComponentEncoded)/events",
            queryItems: [
                URLQueryItem(name: "singleEvents", value: "true"),
                URLQueryItem(name: "showDeleted", value: "false"),
                URLQueryItem(name: "orderBy", value: "startTime"),
                URLQueryItem(name: "timeMin", value: RFC3339.format(window.start)),
                URLQueryItem(name: "timeMax", value: RFC3339.format(window.end)),
            ],
            body: Optional<InsertEventRequest>.none
        )

        return try response.items.compactMap { item in
            guard item.status?.lowercased() != "cancelled" else {
                return nil
            }
            guard !item.isManagedBusyMirror else {
                return nil
            }
            guard item.isEligibleSourceEvent else {
                return nil
            }

            let eventWindow = try item.window(calendarTimeZone: calendarTimeZone)
            return BusyMirrorSourceEvent(
                key: BusyMirrorSourceKey(
                    provider: .google,
                    calendarID: participant.calendarID,
                    eventID: item.id
                ),
                participantID: participant.id,
                startDate: eventWindow.startDate,
                endDate: eventWindow.endDate,
                isAllDay: eventWindow.isAllDay
            )
        }
    }

    func listManagedMirrorEvents(
        in participant: BusyMirrorParticipant,
        calendarTimeZone: String?,
        window: DateInterval,
        accessToken: String
    ) async throws -> [ExistingBusyMirrorEvent] {
        let response: CalendarEventsResponse = try await performJSONRequest(
            accessToken: accessToken,
            method: "GET",
            path: "/calendar/v3/calendars/\(participant.calendarID.urlPathComponentEncoded)/events",
            queryItems: [
                URLQueryItem(name: "singleEvents", value: "true"),
                URLQueryItem(name: "showDeleted", value: "false"),
                URLQueryItem(name: "timeMin", value: RFC3339.format(window.start)),
                URLQueryItem(name: "timeMax", value: RFC3339.format(window.end)),
                URLQueryItem(name: "privateExtendedProperty", value: "\(ManagedMirrorMetadata.keys.managed)=true"),
                URLQueryItem(name: "privateExtendedProperty", value: "\(ManagedMirrorMetadata.keys.kind)=mirror"),
            ],
            body: Optional<InsertEventRequest>.none
        )

        return try response.items.compactMap { item in
            guard let metadata = item.managedMirrorMetadata else {
                return nil
            }

            let eventWindow = try item.window(calendarTimeZone: calendarTimeZone)
            return ExistingBusyMirrorEvent(
                identity: BusyMirrorIdentity(
                    sourceKey: metadata.sourceKey,
                    targetParticipantID: participant.id
                ),
                targetParticipant: participant,
                eventID: item.id,
                startDate: eventWindow.startDate,
                endDate: eventWindow.endDate,
                isAllDay: eventWindow.isAllDay
            )
        }
    }

    func listBusyTargetBlocks(
        in participant: BusyMirrorParticipant,
        calendarTimeZone: String?,
        window: DateInterval,
        accessToken: String
    ) async throws -> [BusyMirrorTargetBusyBlock] {
        let response: CalendarEventsResponse = try await performJSONRequest(
            accessToken: accessToken,
            method: "GET",
            path: "/calendar/v3/calendars/\(participant.calendarID.urlPathComponentEncoded)/events",
            queryItems: [
                URLQueryItem(name: "singleEvents", value: "true"),
                URLQueryItem(name: "showDeleted", value: "false"),
                URLQueryItem(name: "timeMin", value: RFC3339.format(window.start)),
                URLQueryItem(name: "timeMax", value: RFC3339.format(window.end)),
            ],
            body: Optional<InsertEventRequest>.none
        )

        return try response.items.compactMap { item in
            guard item.status?.lowercased() != "cancelled" else {
                return nil
            }
            guard item.blocksTime else {
                return nil
            }

            let eventWindow = try item.window(calendarTimeZone: calendarTimeZone)
            let managedMirrorIdentity = item.managedMirrorMetadata.map {
                BusyMirrorIdentity(
                    sourceKey: $0.sourceKey,
                    targetParticipantID: participant.id
                )
            }

            return BusyMirrorTargetBusyBlock(
                targetParticipant: participant,
                eventID: item.id,
                startDate: eventWindow.startDate,
                endDate: eventWindow.endDate,
                isAllDay: eventWindow.isAllDay,
                managedMirrorIdentity: managedMirrorIdentity
            )
        }
    }

    func createManagedMirrorEvent(
        desiredMirror: DesiredBusyMirrorEvent,
        accessToken: String
    ) async throws {
        let payload = InsertEventRequest.mirror(for: desiredMirror)
        _ = try await performJSONRequest(
            accessToken: accessToken,
            method: "POST",
            path: "/calendar/v3/calendars/\(desiredMirror.targetParticipant.calendarID.urlPathComponentEncoded)/events",
            queryItems: [
                URLQueryItem(name: "sendUpdates", value: "none"),
            ],
            body: payload
        ) as InsertEventResponse
    }

    func updateManagedMirrorEvent(
        _ existingMirror: ExistingBusyMirrorEvent,
        desiredMirror: DesiredBusyMirrorEvent,
        accessToken: String
    ) async throws {
        let payload = InsertEventRequest.mirror(for: desiredMirror)
        _ = try await performJSONRequest(
            accessToken: accessToken,
            method: "PATCH",
            path: "/calendar/v3/calendars/\(existingMirror.targetParticipant.calendarID.urlPathComponentEncoded)/events/\(existingMirror.eventID.urlPathComponentEncoded)",
            queryItems: [
                URLQueryItem(name: "sendUpdates", value: "none"),
            ],
            body: payload
        ) as InsertEventResponse
    }

    func deleteManagedMirrorEvent(
        _ existingMirror: ExistingBusyMirrorEvent,
        accessToken: String
    ) async throws {
        _ = try await performRequest(
            accessToken: accessToken,
            method: "DELETE",
            path: "/calendar/v3/calendars/\(existingMirror.targetParticipant.calendarID.urlPathComponentEncoded)/events/\(existingMirror.eventID.urlPathComponentEncoded)",
            queryItems: [
                URLQueryItem(name: "sendUpdates", value: "none"),
            ],
            body: Optional<InsertEventRequest>.none
        )
    }

    func deleteManagedBusyEvent(
        _ event: GoogleManagedEventRecord,
        accessToken: String
    ) async throws {
        _ = try await performRequest(
            accessToken: accessToken,
            method: "DELETE",
            path: "/calendar/v3/calendars/\(event.calendarID.urlPathComponentEncoded)/events/\(event.eventID.urlPathComponentEncoded)",
            queryItems: [
                URLQueryItem(name: "sendUpdates", value: "none"),
            ],
            body: Optional<InsertEventRequest>.none
        )
    }

    private func performJSONRequest<Response: Decodable, Body: Encodable>(
        accessToken: String,
        method: String,
        path: String,
        queryItems: [URLQueryItem],
        body: Body?
    ) async throws -> Response {
        let (data, _) = try await performRequest(
            accessToken: accessToken,
            method: method,
            path: path,
            queryItems: queryItems,
            body: body
        )

        if Response.self == EmptyResponse.self {
            return EmptyResponse() as! Response
        }

        let decoder = JSONDecoder()
        return try decoder.decode(Response.self, from: data)
    }

    private func performRequest<Body: Encodable>(
        accessToken: String,
        method: String,
        path: String,
        queryItems: [URLQueryItem],
        body: Body?
    ) async throws -> (Data, HTTPURLResponse) {
        let token = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            throw GoogleCalendarServiceError.missingAccessToken
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.googleapis.com"
        components.percentEncodedPath = path
        components.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components.url else {
            throw GoogleCalendarServiceError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body {
            let encoder = JSONEncoder()
            request.httpBody = try encoder.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GoogleCalendarServiceError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = decodedErrorMessage(from: data) ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw GoogleCalendarServiceError.api(statusCode: httpResponse.statusCode, message: message)
        }

        return (data, httpResponse)
    }

    private func decodedErrorMessage(from data: Data) -> String? {
        let decoder = JSONDecoder()
        if let payload = try? decoder.decode(GoogleAPIErrorEnvelope.self, from: data) {
            return payload.error.message
        }

        let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return raw?.isEmpty == false ? raw : nil
    }
}

private struct CalendarListResponse: Decodable {
    let items: [GoogleCalendarSummary]
}

private struct CalendarEventsResponse: Decodable {
    let items: [GoogleCalendarEventItem]
}

private struct GoogleAPIErrorEnvelope: Decodable {
    struct Payload: Decodable {
        let message: String
    }

    let error: Payload
}

private struct InsertEventResponse: Decodable {
    let id: String
    let summary: String?
}

private struct InsertEventRequest: Encodable {
    let summary: String
    let description: String
    let visibility: String
    let transparency: String
    let reminders: EventReminders
    let extendedProperties: EventExtendedProperties
    let start: EventDateTime
    let end: EventDateTime

    static func mirror(for desiredMirror: DesiredBusyMirrorEvent) -> InsertEventRequest {
        InsertEventRequest(
            summary: "Busy",
            description: "Managed by Calendar Busy Sync mirror reconciliation.",
            visibility: "private",
            transparency: "opaque",
            reminders: EventReminders(useDefault: false),
            extendedProperties: EventExtendedProperties(
                privateProperties: ManagedMirrorMetadata.privateProperties(for: desiredMirror.identity)
            ),
            start: EventDateTime.from(
                startDate: desiredMirror.startDate,
                endDate: desiredMirror.endDate,
                isAllDay: desiredMirror.isAllDay
            ).start,
            end: EventDateTime.from(
                startDate: desiredMirror.startDate,
                endDate: desiredMirror.endDate,
                isAllDay: desiredMirror.isAllDay
            ).end
        )
    }
}

private struct EventReminders: Encodable {
    let useDefault: Bool
}

private struct EventExtendedProperties: Encodable {
    enum CodingKeys: String, CodingKey {
        case privateProperties = "private"
    }

    let privateProperties: [String: String]
}

private struct EventDateTime: Encodable {
    let dateTime: String?
    let timeZone: String?
    let date: String?

    static func from(
        startDate: Date,
        endDate: Date,
        isAllDay: Bool
    ) -> (start: EventDateTime, end: EventDateTime) {
        if isAllDay {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyy-MM-dd"
            return (
                EventDateTime(dateTime: nil, timeZone: nil, date: formatter.string(from: startDate)),
                EventDateTime(dateTime: nil, timeZone: nil, date: formatter.string(from: endDate))
            )
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = .current
        return (
            EventDateTime(dateTime: formatter.string(from: startDate), timeZone: TimeZone.current.identifier, date: nil),
            EventDateTime(dateTime: formatter.string(from: endDate), timeZone: TimeZone.current.identifier, date: nil)
        )
    }
}

private struct EmptyResponse: Decodable {}

private struct ManagedBusyEventDraft {
    let summary: String
    let description: String
    let start: EventDateTime
    let end: EventDateTime
    let windowDescription: String

    static func verification(now: Date, timeZone: TimeZone) -> ManagedBusyEventDraft {
        let roundedStart = roundedUpToFiveMinutes(now)
        let endDate = roundedStart.addingTimeInterval(30 * 60)
        let timestampFormatter = ISO8601DateFormatter()
        timestampFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        timestampFormatter.timeZone = timeZone

        let displayFormatter = DateFormatter()
        displayFormatter.locale = Locale(identifier: "en_US_POSIX")
        displayFormatter.timeZone = timeZone
        displayFormatter.dateFormat = "MMM d, HH:mm z"

        let summary = "Busy"
        return ManagedBusyEventDraft(
            summary: summary,
            description: "Managed by Calendar Busy Sync verification flow.",
            start: EventDateTime(
                dateTime: timestampFormatter.string(from: roundedStart),
                timeZone: timeZone.identifier,
                date: nil
            ),
            end: EventDateTime(
                dateTime: timestampFormatter.string(from: endDate),
                timeZone: timeZone.identifier,
                date: nil
            ),
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

private struct GoogleCalendarEventItem: Decodable {
    let id: String
    let status: String?
    let transparency: String?
    let start: GoogleEventDatePayload
    let end: GoogleEventDatePayload
    let attendees: [GoogleEventAttendeePayload]?
    let organizer: GoogleEventActorPayload?
    let extendedProperties: EventExtendedPropertiesPayload?

    var blocksTime: Bool {
        transparency?.lowercased() != "transparent"
    }

    var isEligibleSourceEvent: Bool {
        GoogleMirrorEligibility.shouldMirror(
            blocksTime: blocksTime,
            organizerIsCurrentUser: organizer?.isCurrentUser == true,
            attendees: attendees?.map(\.mirrorAttendee)
        )
    }

    var isManagedBusyMirror: Bool {
        managedMirrorMetadata != nil
    }

    var managedMirrorMetadata: ManagedMirrorMetadata? {
        guard let properties = extendedProperties?.privateProperties else {
            return nil
        }
        return ManagedMirrorMetadata(privateProperties: properties)
    }

    func window(calendarTimeZone: String?) throws -> (startDate: Date, endDate: Date, isAllDay: Bool) {
        let resolvedTimeZone = calendarTimeZone.flatMap(TimeZone.init(identifier:)) ?? .current
        return try (
            startDate: start.resolvedDate(defaultTimeZone: resolvedTimeZone),
            endDate: end.resolvedDate(defaultTimeZone: resolvedTimeZone),
            isAllDay: start.date != nil
        )
    }
}

private struct GoogleEventAttendeePayload: Decodable {
    enum CodingKeys: String, CodingKey {
        case isCurrentUser = "self"
        case responseStatus
    }

    let isCurrentUser: Bool?
    let responseStatus: String?

    var mirrorAttendee: GoogleMirrorAttendee {
        GoogleMirrorAttendee(
            isCurrentUser: isCurrentUser ?? false,
            responseStatus: responseStatus
        )
    }
}

private struct GoogleEventActorPayload: Decodable {
    enum CodingKeys: String, CodingKey {
        case isCurrentUser = "self"
    }

    let isCurrentUser: Bool?
}

private struct GoogleEventDatePayload: Decodable {
    let dateTime: String?
    let date: String?
    let timeZone: String?

    func resolvedDate(defaultTimeZone: TimeZone) throws -> Date {
        if let dateTime {
            if let parsed = RFC3339.parse(dateTime) {
                return parsed
            }
            throw GoogleCalendarServiceError.invalidEventDate
        }

        guard let date else {
            throw GoogleCalendarServiceError.invalidEventDate
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = defaultTimeZone
        formatter.dateFormat = "yyyy-MM-dd"
        guard let parsed = formatter.date(from: date) else {
            throw GoogleCalendarServiceError.invalidEventDate
        }
        return parsed
    }
}

private struct EventExtendedPropertiesPayload: Decodable {
    enum CodingKeys: String, CodingKey {
        case privateProperties = "private"
    }

    let privateProperties: [String: String]?
}

private struct ManagedMirrorMetadata {
    struct Keys {
        let managed = "calendarBusySyncManaged"
        let kind = "calendarBusySyncKind"
        let sourceProvider = "calendarBusySyncSourceProvider"
        let sourceCalendarID = "calendarBusySyncSourceCalendarID"
        let sourceEventID = "calendarBusySyncSourceEventID"
    }

    static let keys = Keys()

    let sourceKey: BusyMirrorSourceKey

    init?(privateProperties: [String: String]) {
        guard
            privateProperties[Self.keys.managed] == "true",
            privateProperties[Self.keys.kind] == "mirror",
            let providerRawValue = privateProperties[Self.keys.sourceProvider],
            let provider = BusyMirrorProvider(rawValue: providerRawValue),
            let sourceCalendarID = privateProperties[Self.keys.sourceCalendarID],
            let sourceEventID = privateProperties[Self.keys.sourceEventID]
        else {
            return nil
        }

        self.sourceKey = BusyMirrorSourceKey(
            provider: provider,
            calendarID: sourceCalendarID,
            eventID: sourceEventID
        )
    }

    static func privateProperties(for identity: BusyMirrorIdentity) -> [String: String] {
        [
            Self.keys.managed: "true",
            Self.keys.kind: "mirror",
            Self.keys.sourceProvider: identity.sourceKey.provider.rawValue,
            Self.keys.sourceCalendarID: identity.sourceKey.calendarID,
            Self.keys.sourceEventID: identity.sourceKey.eventID,
        ]
    }
}

private enum RFC3339 {
    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let basicFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func format(_ date: Date) -> String {
        fractionalFormatter.string(from: date)
    }

    static func parse(_ value: String) -> Date? {
        fractionalFormatter.date(from: value) ?? basicFormatter.date(from: value)
    }
}

private extension String {
    var urlPathComponentEncoded: String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}
