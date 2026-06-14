import CryptoKit
import Foundation

enum BookingKeyMaterial {
    static func publicKey(from privateKey: P256.KeyAgreement.PrivateKey, keyID: String) -> BookingPublicKey {
        publicKey(from: privateKey.publicKey, keyID: keyID)
    }

    static func publicKey(from publicKey: P256.KeyAgreement.PublicKey, keyID: String) -> BookingPublicKey {
        let x963 = publicKey.x963Representation
        let x = Data(x963[1..<33]).base64URLEncodedString()
        let y = Data(x963[33..<65]).base64URLEncodedString()

        return BookingPublicKey(
            keyID: keyID,
            jwk: [
                "kty": "EC",
                "crv": "P-256",
                "x": x,
                "y": y,
            ]
        )
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
