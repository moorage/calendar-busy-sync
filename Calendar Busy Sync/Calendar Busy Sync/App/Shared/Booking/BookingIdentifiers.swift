import Foundation

nonisolated protocol BookingIdentifier: RawRepresentable, Codable, Hashable, Sendable where RawValue == String {
    init(rawValue: String)
}

extension BookingIdentifier {
    nonisolated init(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var description: String {
        rawValue
    }
}

struct BookingProfileID: BookingIdentifier {
    let rawValue: String
}

struct AppointmentTypeID: BookingIdentifier {
    let rawValue: String
}

struct BookingShareID: BookingIdentifier {
    let rawValue: String
}

struct BookingInboxID: BookingIdentifier {
    let rawValue: String
}

struct BookingSlotID: BookingIdentifier {
    let rawValue: String
}

struct BookingRequestID: BookingIdentifier {
    let rawValue: String
}

struct BookingPrivateKeyReference: BookingIdentifier {
    let rawValue: String
}

struct SignedBookingSlotToken: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: String

    nonisolated init(rawValue: String) {
        self.rawValue = rawValue
    }

    nonisolated init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.rawValue = try container.decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var description: String {
        rawValue
    }
}

struct BookingRelayURL: Codable, Equatable, Sendable {
    let url: URL

    init(_ url: URL) throws {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" else {
            throw BookingConfigurationError.invalidRelayURL("Inbox URL must use HTTPS.")
        }

        guard url.host?.isEmpty == false else {
            throw BookingConfigurationError.invalidRelayURL("Inbox URL must include a host.")
        }

        self.url = url
    }
}

struct BookingPublicKey: Codable, Equatable, Sendable {
    var keyID: String
    var jwk: [String: String]

    init(keyID: String, jwk: [String: String]) {
        self.keyID = keyID
        self.jwk = jwk
    }
}

enum BookingIdentifierValidator {
    private static let minimumSlugLength = 3
    private static let allowedPattern = #"^[a-z0-9][a-z0-9-]{1,62}[a-z0-9]$"#

    static func validateSlug(_ value: String, fieldName: String) throws {
        guard value.count >= minimumSlugLength else {
            throw BookingConfigurationError.invalidField(
                "\(fieldName) must be at least \(minimumSlugLength) characters."
            )
        }

        guard value.range(of: allowedPattern, options: .regularExpression) != nil else {
            throw BookingConfigurationError.invalidField(
                "\(fieldName) must use lowercase letters, numbers, and hyphens."
            )
        }
    }
}
