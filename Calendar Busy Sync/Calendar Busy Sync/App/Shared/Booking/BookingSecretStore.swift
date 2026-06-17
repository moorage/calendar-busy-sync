import CryptoKit
import Foundation
import Security

nonisolated struct BookingLocalSecrets: Codable, Equatable, Sendable {
    var keyID: String
    var inboxID: BookingInboxID
    var privateKeyRawRepresentation: Data
    var slotSigningSecret: Data

    var privateKey: P256.KeyAgreement.PrivateKey {
        get throws {
            try P256.KeyAgreement.PrivateKey(rawRepresentation: privateKeyRawRepresentation)
        }
    }

    var slotSigner: BookingSlotSigner {
        get throws {
            try BookingSlotSigner(secret: slotSigningSecret)
        }
    }

    static func generate() -> BookingLocalSecrets {
        let privateKey = P256.KeyAgreement.PrivateKey()
        let signingSecret = SymmetricKey(size: .bits256).withUnsafeBytes { bytes in
            Data(bytes)
        }
        let suffix = UUID().uuidString.lowercased()
        return BookingLocalSecrets(
            keyID: "booking-key-\(suffix)",
            inboxID: BookingInboxID("inbox-\(suffix)"),
            privateKeyRawRepresentation: privateKey.rawRepresentation,
            slotSigningSecret: signingSecret
        )
    }
}

protocol BookingSecretStoring: Sendable {
    func loadSecrets() throws -> BookingLocalSecrets?
    func saveSecrets(_ secrets: BookingLocalSecrets) throws
    func loadAdminToken() throws -> String?
    func saveAdminToken(_ token: String) throws
    func loadVercelToken() throws -> String?
    func saveVercelToken(_ token: String) throws
    func loadGitHubDeployKeyPrivateKey() throws -> String?
    func saveGitHubDeployKeyPrivateKey(_ privateKey: String) throws
    func deleteLegacyGitHubToken() throws
    func invalidateCachedSecrets()
}

extension BookingSecretStoring {
    func invalidateCachedSecrets() {}
}

enum BookingSecretStoreError: LocalizedError, Equatable {
    case unreadable(OSStatus)
    case unwritable(OSStatus)
    case corruptPayload
    case missingSecrets

    var errorDescription: String? {
        switch self {
        case let .unreadable(status):
            return "Booking secrets could not be read from the secure store (\(status))."
        case let .unwritable(status):
            return "Booking secrets could not be written to the secure store (\(status))."
        case .corruptPayload:
            return "Booking secrets are corrupt and could not be decoded."
        case .missingSecrets:
            return "Create and publish a booking page from this app before importing requests."
        }
    }
}

struct BookingKeychainSecretStore: BookingSecretStoring {
    private enum Account {
        static let localSecrets = "booking-local-secrets"
        static let adminToken = "booking-inbox-admin-token"
        static let vercelToken = "booking-vercel-token"
        static let githubToken = "booking-github-token"
        static let githubDeployKeyPrivateKey = "booking-github-deploy-key-private-key"
    }

    private let service: String
    private let vault: any AppCredentialVaultStoring

    init(service: String? = nil, vault: (any AppCredentialVaultStoring)? = nil) {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "CalendarBusySync"
        self.service = service ?? "\(bundleIdentifier).booking"
        self.vault = vault ?? AppCredentialVault.shared
    }

    func loadSecrets() throws -> BookingLocalSecrets? {
        try bookingPayload().bookingLocalSecrets
    }

    func saveSecrets(_ secrets: BookingLocalSecrets) throws {
        var payload = try bookingPayload()
        payload.bookingLocalSecrets = secrets
        payload.didMigrateLegacyBookingSecrets = true
        try vault.savePayload(payload)
    }

    func loadAdminToken() throws -> String? {
        try bookingPayload().bookingInboxAdminToken
    }

    func saveAdminToken(_ token: String) throws {
        try saveToken(token) { payload, normalizedToken in
            payload.bookingInboxAdminToken = normalizedToken
        }
    }

    func loadVercelToken() throws -> String? {
        try bookingPayload().bookingVercelToken
    }

    func saveVercelToken(_ token: String) throws {
        try saveToken(token) { payload, normalizedToken in
            payload.bookingVercelToken = normalizedToken
        }
    }

    func loadGitHubDeployKeyPrivateKey() throws -> String? {
        try bookingPayload().bookingGitHubDeployKeyPrivateKey
    }

    func saveGitHubDeployKeyPrivateKey(_ privateKey: String) throws {
        try saveToken(privateKey) { payload, normalizedToken in
            payload.bookingGitHubDeployKeyPrivateKey = normalizedToken
        }
    }

    func deleteLegacyGitHubToken() throws {
        try deleteData(account: Account.githubToken)
    }

    func invalidateCachedSecrets() {
        vault.invalidateCachedPayload()
    }

    private func saveToken(
        _ token: String,
        assign: (inout AppCredentialVaultPayload, String?) -> Void
    ) throws {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        var payload = try bookingPayload()
        assign(&payload, trimmedToken.isEmpty ? nil : trimmedToken)
        payload.didMigrateLegacyBookingSecrets = true
        try vault.savePayload(payload)
    }

    private func bookingPayload() throws -> AppCredentialVaultPayload {
        if var payload = try vault.loadPayloadIfPresent() {
            let originalPayload = payload
            try migrateLegacyBookingSecretsIfNeeded(into: &payload)
            if !payload.didMigrateLegacyBookingSecrets {
                payload.didMigrateLegacyBookingSecrets = true
            }
            if payload != originalPayload {
                try vault.savePayload(payload)
            }
            return payload
        } else {
            var payload = AppCredentialVaultPayload()
            try migrateLegacyBookingSecretsIfNeeded(into: &payload)
            guard payload.didMigrateLegacyBookingSecrets else {
                return payload
            }
            try vault.savePayload(payload)
            return payload
        }
    }

    private func migrateLegacyBookingSecretsIfNeeded(into payload: inout AppCredentialVaultPayload) throws {
        guard !payload.didMigrateLegacyBookingSecrets else {
            return
        }

        var didFindLegacySecret = false
        if payload.bookingLocalSecrets == nil,
           let data = try loadData(account: Account.localSecrets) {
            do {
                payload.bookingLocalSecrets = try JSONDecoder().decode(BookingLocalSecrets.self, from: data)
                didFindLegacySecret = true
            } catch {
                throw BookingSecretStoreError.corruptPayload
            }
        }
        if payload.bookingInboxAdminToken == nil,
           let data = try loadData(account: Account.adminToken),
           let token = String(data: data, encoding: .utf8) {
            payload.bookingInboxAdminToken = token
            didFindLegacySecret = true
        }
        if payload.bookingVercelToken == nil,
           let data = try loadData(account: Account.vercelToken),
           let token = String(data: data, encoding: .utf8) {
            payload.bookingVercelToken = token
            didFindLegacySecret = true
        }
        if payload.bookingGitHubDeployKeyPrivateKey == nil,
           let data = try loadData(account: Account.githubDeployKeyPrivateKey),
           let privateKey = String(data: data, encoding: .utf8) {
            payload.bookingGitHubDeployKeyPrivateKey = privateKey
            didFindLegacySecret = true
        }

        if didFindLegacySecret {
            payload.didMigrateLegacyBookingSecrets = true
        }
    }

    private func loadData(account: String) throws -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                throw BookingSecretStoreError.corruptPayload
            }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw BookingSecretStoreError.unreadable(status)
        }
    }

    private func deleteData(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw BookingSecretStoreError.unwritable(status)
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
