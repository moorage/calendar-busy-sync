import Foundation

enum GoogleCalendarServiceError: LocalizedError, Equatable {
    case missingAccessToken
    case invalidResponse
    case api(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .missingAccessToken:
            return "Google Sign-In did not return an access token for Calendar API calls."
        case .invalidResponse:
            return "Google Calendar returned an unexpected response."
        case let .api(statusCode, message):
            return "Google Calendar API error \(statusCode): \(message)"
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
    let dateTime: String
    let timeZone: String
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
                timeZone: timeZone.identifier
            ),
            end: EventDateTime(
                dateTime: timestampFormatter.string(from: endDate),
                timeZone: timeZone.identifier
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

private extension String {
    var urlPathComponentEncoded: String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}
