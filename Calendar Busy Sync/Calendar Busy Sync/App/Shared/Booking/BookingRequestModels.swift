import Foundation

nonisolated struct EncryptedBookingRequestEnvelope: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var requestID: BookingRequestID
    var inboxID: BookingInboxID
    var shareID: BookingShareID
    var createdAt: Date
    var expiresAt: Date
    var keyID: String
    var algorithm: String
    var ephemeralPublicKeyJWK: [String: String]?
    var nonce: String
    var ciphertext: String

    var isExpired: Bool {
        expiresAt <= Date()
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case requestID
        case inboxID
        case shareID
        case createdAt
        case expiresAt
        case keyID
        case algorithm
        case ephemeralPublicKeyJWK = "ephemeralPublicKeyJwk"
        case nonce
        case ciphertext
    }

    init(
        schemaVersion: Int,
        requestID: BookingRequestID,
        inboxID: BookingInboxID,
        shareID: BookingShareID,
        createdAt: Date,
        expiresAt: Date,
        keyID: String,
        algorithm: String,
        ephemeralPublicKeyJWK: [String: String]?,
        nonce: String,
        ciphertext: String
    ) {
        self.schemaVersion = schemaVersion
        self.requestID = requestID
        self.inboxID = inboxID
        self.shareID = shareID
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.keyID = keyID
        self.algorithm = algorithm
        self.ephemeralPublicKeyJWK = ephemeralPublicKeyJWK
        self.nonce = nonce
        self.ciphertext = ciphertext
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        requestID = try container.decode(BookingRequestID.self, forKey: .requestID)
        inboxID = try container.decode(BookingInboxID.self, forKey: .inboxID)
        shareID = try container.decode(BookingShareID.self, forKey: .shareID)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        expiresAt = try container.decode(Date.self, forKey: .expiresAt)
        keyID = try container.decode(String.self, forKey: .keyID)
        algorithm = try container.decode(String.self, forKey: .algorithm)
        ephemeralPublicKeyJWK = try container.decodeIfPresent([String: LossyJWKString].self, forKey: .ephemeralPublicKeyJWK)?
            .compactMapValues(\.value)
        nonce = try container.decode(String.self, forKey: .nonce)
        ciphertext = try container.decode(String.self, forKey: .ciphertext)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(requestID, forKey: .requestID)
        try container.encode(inboxID, forKey: .inboxID)
        try container.encode(shareID, forKey: .shareID)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(expiresAt, forKey: .expiresAt)
        try container.encode(keyID, forKey: .keyID)
        try container.encode(algorithm, forKey: .algorithm)
        try container.encodeIfPresent(ephemeralPublicKeyJWK, forKey: .ephemeralPublicKeyJWK)
        try container.encode(nonce, forKey: .nonce)
        try container.encode(ciphertext, forKey: .ciphertext)
    }
}

private struct LossyJWKString: Decodable {
    let value: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = try? container.decode(String.self)
    }
}

nonisolated struct BookingRequestLedgerEntry: Codable, Equatable, Identifiable, Sendable {
    enum Status: String, Codable, Sendable {
        case imported
        case decrypted
        case approved
        case declined
        case expired
    }

    var id: BookingRequestID
    var importedAt: Date
    var status: Status
    var envelopeDigest: String
}

enum BookingPublicArtifactAuditor {
    private static let forbiddenPatterns = [
        #"ya29\.[A-Za-z0-9_\-\.]+"#,
        #"refresh_token"#,
        #"access_token"#,
        #"client_secret"#,
        #"private_key"#,
        #"Bearer\s+[A-Za-z0-9_\-\.]+"#,
    ]

    static func findings(in text: String, forbiddenValues: [String] = []) -> [String] {
        var findings: [String] = []
        let lowercasedText = text.lowercased()

        for value in forbiddenValues where !value.isEmpty {
            if lowercasedText.contains(value.lowercased()) {
                findings.append("Public artifact contains forbidden value.")
            }
        }

        for pattern in forbiddenPatterns {
            if text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
                findings.append("Public artifact contains secret-looking data.")
            }
        }

        return findings
    }
}
