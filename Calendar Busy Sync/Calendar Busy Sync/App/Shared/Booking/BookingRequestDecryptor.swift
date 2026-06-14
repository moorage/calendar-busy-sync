import CryptoKit
import Foundation

enum BookingRequestDecryptionError: Error, Equatable {
    case missingEphemeralPublicKey
    case invalidEphemeralPublicKey
    case invalidNonce
    case invalidCiphertext
}

enum BookingRequestDecryptor {
    static func decrypt(
        _ envelope: EncryptedBookingRequestEnvelope,
        using privateKey: P256.KeyAgreement.PrivateKey
    ) throws -> Data {
        guard let jwk = envelope.ephemeralPublicKeyJWK,
              let x = Data(base64URLEncoded: jwk["x"] ?? ""),
              let y = Data(base64URLEncoded: jwk["y"] ?? "")
        else {
            throw BookingRequestDecryptionError.missingEphemeralPublicKey
        }

        let publicKeyData = Data([0x04]) + x + y
        let publicKey: P256.KeyAgreement.PublicKey
        do {
            publicKey = try P256.KeyAgreement.PublicKey(x963Representation: publicKeyData)
        } catch {
            throw BookingRequestDecryptionError.invalidEphemeralPublicKey
        }

        guard let nonceData = Data(base64URLEncoded: envelope.nonce),
              let nonce = try? AES.GCM.Nonce(data: nonceData)
        else {
            throw BookingRequestDecryptionError.invalidNonce
        }

        guard let sealedBytes = Data(base64URLEncoded: envelope.ciphertext),
              sealedBytes.count > 16
        else {
            throw BookingRequestDecryptionError.invalidCiphertext
        }

        let ciphertext = sealedBytes.dropLast(16)
        let tag = sealedBytes.suffix(16)
        let sealedBox = try AES.GCM.SealedBox(
            nonce: nonce,
            ciphertext: ciphertext,
            tag: tag
        )
        let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: publicKey)
        let symmetricKey = sharedSecret.withUnsafeBytes { bytes in
            SymmetricKey(data: Data(bytes))
        }

        return try AES.GCM.open(sealedBox, using: symmetricKey)
    }
}

struct BookingRequestLedger: Equatable, Sendable {
    private(set) var entriesByID: [BookingRequestID: BookingRequestLedgerEntry]

    init(entries: [BookingRequestLedgerEntry] = []) {
        self.entriesByID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
    }

    mutating func importEnvelope(
        _ envelope: EncryptedBookingRequestEnvelope,
        digest: String,
        now: Date
    ) -> BookingRequestLedgerEntry? {
        guard entriesByID[envelope.requestID] == nil else {
            return nil
        }

        let entry = BookingRequestLedgerEntry(
            id: envelope.requestID,
            importedAt: now,
            status: envelope.expiresAt <= now ? .expired : .imported,
            envelopeDigest: digest
        )
        entriesByID[entry.id] = entry
        return entry
    }
}

private extension Data {
    init?(base64URLEncoded value: String) {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - base64.count % 4) % 4
        base64.append(String(repeating: "=", count: padding))
        self.init(base64Encoded: base64)
    }
}
