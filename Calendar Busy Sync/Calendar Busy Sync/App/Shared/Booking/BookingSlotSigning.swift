import CryptoKit
import Foundation

nonisolated struct BookingSlotClaim: Codable, Equatable, Sendable {
    var appointmentTypeID: AppointmentTypeID
    var slotID: BookingSlotID
    var startsAt: Date
    var endsAt: Date
    var generatedAt: Date
    var expiresAt: Date
    var nonce: String
    var signingKeyVersion: String
}

enum BookingSlotSigningError: Error, Equatable {
    case weakSigningSecret
    case malformedToken
    case invalidSignature
}

nonisolated struct BookingSlotSigner: Sendable {
    private let key: SymmetricKey

    init(secret: Data) throws {
        guard secret.count >= 32 else {
            throw BookingSlotSigningError.weakSigningSecret
        }

        self.key = SymmetricKey(data: secret)
    }

    func sign(_ claim: BookingSlotClaim) throws -> SignedBookingSlotToken {
        let payload = try Self.encoder.encode(claim)
        let signature = Data(HMAC<SHA256>.authenticationCode(for: payload, using: key))
        return SignedBookingSlotToken("\(payload.base64URLEncodedString()).\(signature.base64URLEncodedString())")
    }

    func verifiedClaim(from token: SignedBookingSlotToken) throws -> BookingSlotClaim {
        let parts = token.rawValue.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let payload = Data(base64URLEncoded: String(parts[0])),
              let signature = Data(base64URLEncoded: String(parts[1]))
        else {
            throw BookingSlotSigningError.malformedToken
        }

        guard HMAC<SHA256>.isValidAuthenticationCode(signature, authenticating: payload, using: key) else {
            throw BookingSlotSigningError.invalidSignature
        }

        return try Self.decoder.decode(BookingSlotClaim.self, from: payload)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

private extension Data {
    nonisolated init?(base64URLEncoded value: String) {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - base64.count % 4) % 4
        base64.append(String(repeating: "=", count: padding))
        self.init(base64Encoded: base64)
    }

    nonisolated func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
