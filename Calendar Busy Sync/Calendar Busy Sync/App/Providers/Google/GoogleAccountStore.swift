import Foundation
import Security

struct StoredGoogleAccount: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let email: String
    let displayName: String
    let grantedScopes: [String]
    let usesCustomOAuthApp: Bool
    let archivedUserData: Data

    var connectedAccount: GoogleConnectedAccount {
        GoogleConnectedAccount(
            id: id,
            email: email,
            displayName: displayName,
            grantedScopes: grantedScopes,
            usesCustomOAuthApp: usesCustomOAuthApp,
            serverAuthCodeAvailable: false
        )
    }
}

struct GoogleAuthorizedAccount {
    let storedAccount: StoredGoogleAccount
    let accessToken: String
}

protocol GoogleAccountStoring {
    func loadAccounts() throws -> [StoredGoogleAccount]
    func saveAccounts(_ accounts: [StoredGoogleAccount]) throws
    func upsertAccount(_ account: StoredGoogleAccount) throws -> [StoredGoogleAccount]
    func removeAccount(id: String) throws -> [StoredGoogleAccount]
    func invalidateCachedCredentials()
}

extension GoogleAccountStoring {
    func invalidateCachedCredentials() {}
}

enum GoogleAccountStoreError: LocalizedError, Equatable {
    case unreadable(OSStatus)
    case unwritable(OSStatus)
    case corruptPayload

    var errorDescription: String? {
        switch self {
        case let .unreadable(status):
            return "Stored Google accounts could not be read from the secure store (\(status))."
        case let .unwritable(status):
            return "Stored Google accounts could not be written to the secure store (\(status))."
        case .corruptPayload:
            return "Stored Google accounts are corrupt and could not be decoded."
        }
    }
}

struct GoogleAccountStore: GoogleAccountStoring {
    private let service: String
    private let accountName: String
    private let vault: any AppCredentialVaultStoring

    init(
        service: String? = nil,
        accountName: String = "connected-google-accounts",
        vault: (any AppCredentialVaultStoring)? = nil
    ) {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "CalendarBusySync"
        self.service = service ?? "\(bundleIdentifier).google-accounts"
        self.accountName = accountName
        self.vault = vault ?? AppCredentialVault.shared
    }

    func loadAccounts() throws -> [StoredGoogleAccount] {
        try googlePayload().googleAccounts
    }

    func saveAccounts(_ accounts: [StoredGoogleAccount]) throws {
        var payload = try googlePayload()
        payload.googleAccounts = accounts
        payload.didMigrateLegacyGoogleAccounts = true
        try vault.savePayload(payload)
    }

    func upsertAccount(_ account: StoredGoogleAccount) throws -> [StoredGoogleAccount] {
        let payload = try vault.updatePayload { payload in
            try migrateLegacyGoogleAccountsIfNeeded(into: &payload)
            payload.googleAccounts.removeAll(where: { $0.id == account.id })
            payload.googleAccounts.insert(account, at: 0)
            payload.didMigrateLegacyGoogleAccounts = true
        }
        return payload.googleAccounts
    }

    func removeAccount(id: String) throws -> [StoredGoogleAccount] {
        let payload = try vault.updatePayload { payload in
            try migrateLegacyGoogleAccountsIfNeeded(into: &payload)
            payload.googleAccounts.removeAll(where: { $0.id == id })
            payload.didMigrateLegacyGoogleAccounts = true
        }
        return payload.googleAccounts
    }

    func invalidateCachedCredentials() {
        vault.invalidateCachedPayload()
    }

    private func googlePayload() throws -> AppCredentialVaultPayload {
        if var payload = try vault.loadPayloadIfPresent() {
            let originalPayload = payload
            try migrateLegacyGoogleAccountsIfNeeded(into: &payload)
            if payload != originalPayload {
                try vault.savePayload(payload)
            }
            return payload
        } else {
            let legacyAccounts = try loadLegacyAccounts()
            guard !legacyAccounts.isEmpty else {
                return AppCredentialVaultPayload(didMigrateLegacyGoogleAccounts: true)
            }

            let payload = AppCredentialVaultPayload(
                didMigrateLegacyGoogleAccounts: true,
                googleAccounts: legacyAccounts
            )
            try vault.savePayload(payload)
            return payload
        }
    }

    private func migrateLegacyGoogleAccountsIfNeeded(into payload: inout AppCredentialVaultPayload) throws {
        guard !payload.didMigrateLegacyGoogleAccounts else {
            return
        }

        let legacyAccounts = try loadLegacyAccounts()
        if payload.googleAccounts.isEmpty, !legacyAccounts.isEmpty {
            payload.googleAccounts = legacyAccounts
        }
        payload.didMigrateLegacyGoogleAccounts = true
    }

    private func loadLegacyAccounts() throws -> [StoredGoogleAccount] {
        var query = baseQuery
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            break
        case errSecItemNotFound:
            return []
        default:
            throw GoogleAccountStoreError.unreadable(status)
        }

        guard let data = item as? Data else {
            throw GoogleAccountStoreError.corruptPayload
        }

        do {
            return try JSONDecoder().decode([StoredGoogleAccount].self, from: data)
        } catch {
            throw GoogleAccountStoreError.corruptPayload
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountName,
        ]
    }
}
