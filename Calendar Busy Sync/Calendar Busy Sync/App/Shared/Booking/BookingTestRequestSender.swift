import CryptoKit
import Foundation

struct BookingTestRequestSender: Sendable {
    var session: URLSession = .shared
    var now: @Sendable () -> Date = { Date() }
    var uuid: @Sendable () -> UUID = { UUID() }

    func sendTestRequest(bookingPageURL: URL, inboxURL: BookingRelayURL) async throws {
        let pageBaseURL = Self.pageBaseURL(from: bookingPageURL)
        async let config = fetchConfig(from: pageBaseURL)
        async let availability = fetchAvailability(from: pageBaseURL)
        let resolvedConfig = try await config
        let resolvedAvailability = try await availability

        guard let slot = resolvedAvailability.slots.first else {
            throw BookingTestRequestSenderError.noPublishedSlots
        }

        let createdAt = now()
        let plaintext = BookingTestRequestPlaintext(
            requestID: BookingRequestID(uuid().uuidString),
            appointmentTypeID: slot.appointmentTypeID,
            slotID: slot.id,
            slotToken: slot.token,
            visitor: BookingTestVisitor(
                name: "Calendar Busy Sync Test",
                email: "test@example.com",
                topic: "Setup test request"
            ),
            browserTimeZone: TimeZone.current.identifier,
            createdAt: createdAt
        )
        let envelope = try Self.encrypt(
            plaintext: plaintext,
            slot: slot,
            config: resolvedConfig,
            createdAt: createdAt
        )
        let request = try Self.postRequest(
            envelope: envelope,
            inboxURL: inboxURL,
            inboxID: resolvedConfig.inbox.id,
            origin: Self.originHeader(from: bookingPageURL)
        )
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode)
        else {
            throw BookingRelayClientError.invalidResponse
        }
    }

    private func fetchConfig(from pageBaseURL: URL) async throws -> BookingPublishedSiteConfig {
        let (data, response) = try await session.data(from: pageBaseURL.appendingPathComponent("public/site-config.json"))
        try Self.validate(response: response)
        return try Self.decoder.decode(BookingPublishedSiteConfig.self, from: data)
    }

    private func fetchAvailability(from pageBaseURL: URL) async throws -> BookingPublishedAvailability {
        let (data, response) = try await session.data(from: pageBaseURL.appendingPathComponent("public/availability/slots.json"))
        try Self.validate(response: response)
        return try Self.decoder.decode(BookingPublishedAvailability.self, from: data)
    }

    static func encrypt(
        plaintext: BookingTestRequestPlaintext,
        slot: BookingPublishedSlot,
        config: BookingPublishedSiteConfig,
        createdAt: Date
    ) throws -> EncryptedBookingRequestEnvelope {
        guard let x = Data(base64URLEncodedBookingValue: config.encryption.publicKeyJWK["x"] ?? ""),
              let y = Data(base64URLEncodedBookingValue: config.encryption.publicKeyJWK["y"] ?? "")
        else {
            throw BookingTestRequestSenderError.invalidPublicKey
        }

        let recipientPublicKey = try P256.KeyAgreement.PublicKey(x963Representation: Data([0x04]) + x + y)
        let ephemeralPrivateKey = P256.KeyAgreement.PrivateKey()
        let sharedSecret = try ephemeralPrivateKey.sharedSecretFromKeyAgreement(with: recipientPublicKey)
        let symmetricKey = sharedSecret.withUnsafeBytes { bytes in
            SymmetricKey(data: Data(bytes))
        }
        let nonce = AES.GCM.Nonce()
        let plaintextData = try encoder.encode(plaintext)
        let sealedBox = try AES.GCM.seal(plaintextData, using: symmetricKey, nonce: nonce)
        let ephemeralJWK = BookingKeyMaterial.publicKey(
            from: ephemeralPrivateKey.publicKey,
            keyID: config.encryption.keyID
        ).jwk

        return EncryptedBookingRequestEnvelope(
            schemaVersion: 1,
            requestID: plaintext.requestID,
            inboxID: config.inbox.id,
            shareID: config.share.id,
            createdAt: createdAt,
            expiresAt: slot.expiresAt,
            keyID: config.encryption.keyID,
            algorithm: "ECDH-P256-AES-GCM",
            ephemeralPublicKeyJWK: ephemeralJWK,
            nonce: nonce.withUnsafeBytes { Data($0) }.base64URLEncodedBookingString(),
            ciphertext: (sealedBox.ciphertext + sealedBox.tag).base64URLEncodedBookingString()
        )
    }

    private static func postRequest(
        envelope: EncryptedBookingRequestEnvelope,
        inboxURL: BookingRelayURL,
        inboxID: BookingInboxID,
        origin: String
    ) throws -> URLRequest {
        var request = URLRequest(
            url: inboxURL.url
                .appendingPathComponent("v1")
                .appendingPathComponent("inboxes")
                .appendingPathComponent(inboxID.rawValue)
                .appendingPathComponent("requests")
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(origin, forHTTPHeaderField: "origin")
        request.httpBody = try encoder.encode(envelope)
        return request
    }

    private static func validate(response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode)
        else {
            throw BookingRelayClientError.invalidResponse
        }
    }

    private static func pageBaseURL(from url: URL) -> URL {
        if url.pathExtension.isEmpty {
            return url
        }
        return url.deletingLastPathComponent()
    }

    private static func originHeader(from url: URL) throws -> String {
        guard let scheme = url.scheme, let host = url.host else {
            throw BookingConfigurationError.invalidField("Booking page URL must include a host.")
        }

        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = url.port
        guard let origin = components.url?.absoluteString else {
            throw BookingConfigurationError.invalidField("Booking page URL must include a host.")
        }
        return origin
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()
}

enum BookingTestRequestSenderError: Error, Equatable {
    case invalidPublicKey
    case noPublishedSlots
}

nonisolated struct BookingPublishedSiteConfig: Decodable, Equatable, Sendable {
    var share: BookingPublishedShare
    var inbox: BookingPublishedInbox
    var encryption: BookingPublishedEncryption
}

nonisolated struct BookingPublishedShare: Decodable, Equatable, Sendable {
    var id: BookingShareID
}

nonisolated struct BookingPublishedInbox: Decodable, Equatable, Sendable {
    var id: BookingInboxID
    var url: URL
}

nonisolated struct BookingPublishedEncryption: Decodable, Equatable, Sendable {
    var keyID: String
    var publicKeyJWK: [String: String]

    private enum CodingKeys: String, CodingKey {
        case keyID
        case publicKeyJWK = "publicKeyJwk"
    }

    init(keyID: String, publicKeyJWK: [String: String]) {
        self.keyID = keyID
        self.publicKeyJWK = publicKeyJWK
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyID = try container.decode(String.self, forKey: .keyID)
        publicKeyJWK = try container.decode([String: FlexibleJWKValue].self, forKey: .publicKeyJWK)
            .mapValues(\.stringValue)
    }
}

nonisolated private struct FlexibleJWKValue: Decodable {
    var stringValue: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            stringValue = string
        } else if let bool = try? container.decode(Bool.self) {
            stringValue = bool ? "true" : "false"
        } else if let number = try? container.decode(Int.self) {
            stringValue = String(number)
        } else {
            throw DecodingError.typeMismatch(
                String.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "JWK values must be strings, booleans, or integers."
                )
            )
        }
    }
}

nonisolated struct BookingPublishedAvailability: Decodable, Equatable, Sendable {
    var slots: [BookingPublishedSlot]
}

nonisolated struct BookingPublishedSlot: Decodable, Equatable, Sendable {
    var id: BookingSlotID
    var appointmentTypeID: AppointmentTypeID
    var startsAt: Date
    var endsAt: Date
    var expiresAt: Date
    var token: SignedBookingSlotToken
}

struct BookingTestRequestPlaintext: Encodable, Equatable, Sendable {
    var requestID: BookingRequestID
    var appointmentTypeID: AppointmentTypeID
    var slotID: BookingSlotID
    var slotToken: SignedBookingSlotToken
    var visitor: BookingTestVisitor
    var browserTimeZone: String
    var createdAt: Date
}

struct BookingTestVisitor: Encodable, Equatable, Sendable {
    var name: String
    var email: String
    var topic: String
    var guestEmails: [String] = []
}

private extension Data {
    init?(base64URLEncodedBookingValue value: String) {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - base64.count % 4) % 4
        base64.append(String(repeating: "=", count: padding))
        self.init(base64Encoded: base64)
    }

    func base64URLEncodedBookingString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
