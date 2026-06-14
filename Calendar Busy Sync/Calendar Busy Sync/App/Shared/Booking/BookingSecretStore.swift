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
    func loadGitHubDeployKeyPrivateKey() throws -> String?
    func saveGitHubDeployKeyPrivateKey(_ privateKey: String) throws
    func deleteLegacyGitHubToken() throws
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
        static let githubToken = "booking-github-token"
        static let githubDeployKeyPrivateKey = "booking-github-deploy-key-private-key"
    }

    private let service: String

    init(service: String? = nil) {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "CalendarBusySync"
        self.service = service ?? "\(bundleIdentifier).booking"
    }

    func loadSecrets() throws -> BookingLocalSecrets? {
        guard let data = try loadData(account: Account.localSecrets) else {
            return nil
        }

        do {
            return try JSONDecoder().decode(BookingLocalSecrets.self, from: data)
        } catch {
            throw BookingSecretStoreError.corruptPayload
        }
    }

    func saveSecrets(_ secrets: BookingLocalSecrets) throws {
        try saveData(try JSONEncoder().encode(secrets), account: Account.localSecrets)
    }

    func loadAdminToken() throws -> String? {
        guard let data = try loadData(account: Account.adminToken) else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    func saveAdminToken(_ token: String) throws {
        try saveToken(token, account: Account.adminToken)
    }

    func loadGitHubDeployKeyPrivateKey() throws -> String? {
        guard let data = try loadData(account: Account.githubDeployKeyPrivateKey) else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    func saveGitHubDeployKeyPrivateKey(_ privateKey: String) throws {
        try saveToken(privateKey, account: Account.githubDeployKeyPrivateKey)
    }

    func deleteLegacyGitHubToken() throws {
        try deleteData(account: Account.githubToken)
    }

    private func saveToken(_ token: String, account: String) throws {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedToken.isEmpty {
            try deleteData(account: account)
            return
        }

        try saveData(Data(trimmedToken.utf8), account: account)
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

    private func saveData(_ data: Data, account: String) throws {
        let addStatus = SecItemAdd(writeQuery(data: data, account: account) as CFDictionary, nil)
        if addStatus == errSecSuccess {
            return
        }

        guard addStatus == errSecDuplicateItem else {
            throw BookingSecretStoreError.unwritable(addStatus)
        }

        let status = SecItemUpdate(
            baseQuery(account: account) as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        guard status == errSecSuccess else {
            throw BookingSecretStoreError.unwritable(status)
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

    private func writeQuery(data: Data, account: String) -> [String: Any] {
        var query = baseQuery(account: account)
        query[kSecValueData as String] = data
        #if os(iOS)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        #endif
        return query
    }
}
