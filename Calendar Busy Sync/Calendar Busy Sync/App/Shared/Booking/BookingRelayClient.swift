import Foundation

struct BookingRelayAdminToken: RawRepresentable, Equatable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }
}

nonisolated struct BookingRelayRequestPage: Codable, Equatable, Sendable {
    var requests: [EncryptedBookingRequestEnvelope]
    var cursor: String?
}

nonisolated struct BookingRelayHealthResponse: Codable, Equatable, Sendable {
    var ok: Bool
    var allowedOrigin: String?
    var storage: String?
    var storageReady: Bool?
}

enum BookingRelayClientError: Error, Equatable {
    case invalidResponse
    case requestRejected(statusCode: Int)

    var isAuthenticationFailure: Bool {
        if case let .requestRejected(statusCode) = self {
            return statusCode == 401
        }
        return false
    }
}

struct BookingRelayClient: Sendable {
    var relayURL: BookingRelayURL
    var adminToken: BookingRelayAdminToken
    var session: URLSession

    init(
        relayURL: BookingRelayURL,
        adminToken: BookingRelayAdminToken,
        session: URLSession = .shared
    ) {
        self.relayURL = relayURL
        self.adminToken = adminToken
        self.session = session
    }

    func healthCheck() async throws -> BookingRelayHealthResponse? {
        let request = BookingRelayRequestBuilder.healthRequest(relayURL: relayURL)
        let (data, response) = try await session.data(for: request)
        try Self.validate(response: response)
        return try? Self.decoder.decode(BookingRelayHealthResponse.self, from: data)
    }

    func fetchRequests(
        inboxID: BookingInboxID,
        cursor: String?
    ) async throws -> BookingRelayRequestPage {
        let request = BookingRelayRequestBuilder.listRequestsRequest(
            relayURL: relayURL,
            inboxID: inboxID,
            cursor: cursor,
            adminToken: adminToken
        )
        let (data, response) = try await session.data(for: request)
        try Self.validate(response: response)
        return try Self.decoder.decode(BookingRelayRequestPage.self, from: data)
    }

    func deleteRequest(
        inboxID: BookingInboxID,
        requestID: BookingRequestID
    ) async throws {
        let request = BookingRelayRequestBuilder.deleteRequest(
            relayURL: relayURL,
            inboxID: inboxID,
            requestID: requestID,
            adminToken: adminToken
        )
        let (_, response) = try await session.data(for: request)
        try Self.validate(response: response)
    }

    private static func validate(response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BookingRelayClientError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw BookingRelayClientError.requestRejected(statusCode: httpResponse.statusCode)
        }
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

enum BookingRelayRequestBuilder {
    static func healthRequest(relayURL: BookingRelayURL) -> URLRequest {
        var request = URLRequest(url: relayURL.url.appendingPathComponent("healthz"))
        request.httpMethod = "GET"
        return request
    }

    static func listRequestsRequest(
        relayURL: BookingRelayURL,
        inboxID: BookingInboxID,
        cursor: String?,
        adminToken: BookingRelayAdminToken
    ) -> URLRequest {
        var components = URLComponents(
            url: relayURL.url
                .appendingPathComponent("v1")
                .appendingPathComponent("inboxes")
                .appendingPathComponent(inboxID.rawValue)
                .appendingPathComponent("requests"),
            resolvingAgainstBaseURL: false
        )!
        if let cursor, !cursor.isEmpty {
            components.queryItems = [URLQueryItem(name: "cursor", value: cursor)]
        }

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(adminToken.rawValue)", forHTTPHeaderField: "Authorization")
        return request
    }

    static func deleteRequest(
        relayURL: BookingRelayURL,
        inboxID: BookingInboxID,
        requestID: BookingRequestID,
        adminToken: BookingRelayAdminToken
    ) -> URLRequest {
        var request = URLRequest(
            url: relayURL.url
                .appendingPathComponent("v1")
                .appendingPathComponent("inboxes")
                .appendingPathComponent(inboxID.rawValue)
                .appendingPathComponent("requests")
                .appendingPathComponent(requestID.rawValue)
        )
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(adminToken.rawValue)", forHTTPHeaderField: "Authorization")
        return request
    }
}
