import Foundation
import Security

struct StoredGoogleAccount: Codable, Equatable, Identifiable {
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

    init(
        service: String? = nil,
        accountName: String = "connected-google-accounts"
    ) {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "CalendarBusySync"
        self.service = service ?? "\(bundleIdentifier).google-accounts"
        self.accountName = accountName
    }

    func loadAccounts() throws -> [StoredGoogleAccount] {
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

    func saveAccounts(_ accounts: [StoredGoogleAccount]) throws {
        if accounts.isEmpty {
            let status = SecItemDelete(baseQuery as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw GoogleAccountStoreError.unwritable(status)
            }
            return
        }

        let data = try JSONEncoder().encode(accounts)
        let addStatus = SecItemAdd(writeQuery(data: data) as CFDictionary, nil)
        if addStatus == errSecSuccess {
            return
        }

        guard addStatus == errSecDuplicateItem else {
            throw GoogleAccountStoreError.unwritable(addStatus)
        }

        let status = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        guard status == errSecSuccess else {
            throw GoogleAccountStoreError.unwritable(status)
        }
    }

    func upsertAccount(_ account: StoredGoogleAccount) throws -> [StoredGoogleAccount] {
        var accounts = try loadAccounts()
        accounts.removeAll(where: { $0.id == account.id })
        accounts.insert(account, at: 0)
        try saveAccounts(accounts)
        return accounts
    }

    func removeAccount(id: String) throws -> [StoredGoogleAccount] {
        let accounts = try loadAccounts().filter { $0.id != id }
        try saveAccounts(accounts)
        return accounts
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountName,
        ]
    }

    private func writeQuery(data: Data) -> [String: Any] {
        var query = baseQuery
        query[kSecValueData as String] = data
        #if os(iOS)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        #endif
        return query
    }
}
