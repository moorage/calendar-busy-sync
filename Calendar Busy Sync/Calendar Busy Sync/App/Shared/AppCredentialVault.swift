import Foundation
import LocalAuthentication
import Security

nonisolated struct AppCredentialVaultPayload: Codable, Equatable, Sendable {
    private static let currentVersion = 1

    var version: Int
    var didMigrateLegacyBookingSecrets: Bool
    var didMigrateLegacyGoogleAccounts: Bool
    var bookingLocalSecrets: BookingLocalSecrets?
    var bookingInboxAdminToken: String?
    var bookingVercelToken: String?
    var bookingGitHubDeployKeyPrivateKey: String?
    var googleAccounts: [StoredGoogleAccount]

    init(
        version: Int = Self.currentVersion,
        didMigrateLegacyBookingSecrets: Bool = false,
        didMigrateLegacyGoogleAccounts: Bool = false,
        bookingLocalSecrets: BookingLocalSecrets? = nil,
        bookingInboxAdminToken: String? = nil,
        bookingVercelToken: String? = nil,
        bookingGitHubDeployKeyPrivateKey: String? = nil,
        googleAccounts: [StoredGoogleAccount] = []
    ) {
        self.version = version
        self.didMigrateLegacyBookingSecrets = didMigrateLegacyBookingSecrets
        self.didMigrateLegacyGoogleAccounts = didMigrateLegacyGoogleAccounts
        self.bookingLocalSecrets = bookingLocalSecrets
        self.bookingInboxAdminToken = bookingInboxAdminToken
        self.bookingVercelToken = bookingVercelToken
        self.bookingGitHubDeployKeyPrivateKey = bookingGitHubDeployKeyPrivateKey
        self.googleAccounts = googleAccounts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        didMigrateLegacyBookingSecrets = try container.decodeIfPresent(
            Bool.self,
            forKey: .didMigrateLegacyBookingSecrets
        ) ?? false
        didMigrateLegacyGoogleAccounts = try container.decodeIfPresent(
            Bool.self,
            forKey: .didMigrateLegacyGoogleAccounts
        ) ?? false
        bookingLocalSecrets = try container.decodeIfPresent(BookingLocalSecrets.self, forKey: .bookingLocalSecrets)
        bookingInboxAdminToken = try container.decodeIfPresent(String.self, forKey: .bookingInboxAdminToken)
        bookingVercelToken = try container.decodeIfPresent(String.self, forKey: .bookingVercelToken)
        bookingGitHubDeployKeyPrivateKey = try container.decodeIfPresent(
            String.self,
            forKey: .bookingGitHubDeployKeyPrivateKey
        )
        googleAccounts = try container.decodeIfPresent([StoredGoogleAccount].self, forKey: .googleAccounts) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case didMigrateLegacyBookingSecrets
        case didMigrateLegacyGoogleAccounts
        case bookingLocalSecrets
        case bookingInboxAdminToken
        case bookingVercelToken
        case bookingGitHubDeployKeyPrivateKey
        case googleAccounts
    }
}

enum AppCredentialVaultError: LocalizedError, Equatable {
    case unreadable(OSStatus)
    case unwritable(OSStatus)
    case corruptPayload
    case accessControlUnavailable(String)

    var errorDescription: String? {
        switch self {
        case let .unreadable(status):
            return "Saved credentials could not be read from the secure store (\(status))."
        case let .unwritable(status):
            return "Saved credentials could not be written to the secure store (\(status))."
        case .corruptPayload:
            return "Saved credentials are corrupt and could not be decoded."
        case let .accessControlUnavailable(message):
            return "Saved credentials could not enable local device authentication: \(message)"
        }
    }
}

enum AppCredentialVaultAccessPolicy: Sendable {
    case deviceKeychain
    case localUserPresence
    case unprotected
}

protocol AppCredentialVaultStoring: Sendable {
    func loadPayloadIfPresent() throws -> AppCredentialVaultPayload?
    func savePayload(_ payload: AppCredentialVaultPayload) throws
    func invalidateCachedPayload()
    func updatePayload(
        _ transform: @Sendable (inout AppCredentialVaultPayload) throws -> Void
    ) throws -> AppCredentialVaultPayload
}

final class AppCredentialVault: AppCredentialVaultStoring, @unchecked Sendable {
    static let shared = AppCredentialVault()

    private let service: String
    private let accountName: String
    private let accessPolicy: AppCredentialVaultAccessPolicy
    private let lock = NSRecursiveLock()
    private var authenticationContext: LAContext?
    private var cachedPayload: AppCredentialVaultPayload?

    init(
        service: String? = nil,
        accountName: String = "app-credential-vault",
        accessPolicy: AppCredentialVaultAccessPolicy = .deviceKeychain
    ) {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "CalendarBusySync"
        self.service = service ?? "\(bundleIdentifier).credentials"
        self.accountName = accountName
        self.accessPolicy = accessPolicy
    }

    func loadPayloadIfPresent() throws -> AppCredentialVaultPayload? {
        lock.lock()
        defer { lock.unlock() }

        if let cachedPayload {
            return cachedPayload
        }

        var query = baseQuery()
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        if accessPolicy == .deviceKeychain {
            query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUISkip
        } else if accessPolicy == .localUserPresence {
            query[kSecUseAuthenticationContext as String] = sharedAuthenticationContext()
        }

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            let payload = try decodePayload(item)
            cachedPayload = payload
            return payload
        case errSecItemNotFound:
            return nil
        case errSecInteractionNotAllowed where accessPolicy == .deviceKeychain,
             errSecAuthFailed where accessPolicy == .deviceKeychain:
            return try migrateLegacyLocalAuthenticationPayloadIfPresent()
        default:
            throw AppCredentialVaultError.unreadable(status)
        }
    }

    func savePayload(_ payload: AppCredentialVaultPayload) throws {
        lock.lock()
        defer { lock.unlock() }

        let data = try JSONEncoder().encode(payload)
        let addStatus = SecItemAdd(try addQuery(data: data) as CFDictionary, nil)
        if addStatus == errSecSuccess {
            cachedPayload = payload
            return
        }

        guard addStatus == errSecDuplicateItem else {
            throw AppCredentialVaultError.unwritable(addStatus)
        }

        let status = SecItemUpdate(
            baseQuery() as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        guard status == errSecSuccess else {
            throw AppCredentialVaultError.unwritable(status)
        }
        cachedPayload = payload
    }

    func invalidateCachedPayload() {
        lock.lock()
        defer { lock.unlock() }

        cachedPayload = nil
    }

    func updatePayload(
        _ transform: @Sendable (inout AppCredentialVaultPayload) throws -> Void
    ) throws -> AppCredentialVaultPayload {
        lock.lock()
        defer { lock.unlock() }

        var payload = try loadPayloadIfPresent() ?? AppCredentialVaultPayload()
        try transform(&payload)
        try savePayload(payload)
        return payload
    }

    private func addQuery(data: Data) throws -> [String: Any] {
        var query = baseQuery()
        query[kSecValueData as String] = data
        switch accessPolicy {
        case .deviceKeychain:
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        case .localUserPresence:
            query[kSecAttrAccessControl as String] = try localAuthenticationAccessControl()
        case .unprotected:
            #if os(iOS)
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            #endif
        }
        return query
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountName,
        ]
    }

    private func legacyLocalAuthenticationReadQuery() -> [String: Any] {
        var query = baseQuery()
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationContext as String] = sharedAuthenticationContext()
        return query
    }

    private func decodePayload(_ item: CFTypeRef?) throws -> AppCredentialVaultPayload {
        guard let data = item as? Data else {
            throw AppCredentialVaultError.corruptPayload
        }
        do {
            return try JSONDecoder().decode(AppCredentialVaultPayload.self, from: data)
        } catch {
            throw AppCredentialVaultError.corruptPayload
        }
    }

    private func migrateLegacyLocalAuthenticationPayloadIfPresent() throws -> AppCredentialVaultPayload? {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(legacyLocalAuthenticationReadQuery() as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            let payload = try decodePayload(item)
            try replaceExistingItemWithDeviceKeychainPayload(payload)
            return payload
        case errSecItemNotFound:
            return nil
        default:
            throw AppCredentialVaultError.unreadable(status)
        }
    }

    private func replaceExistingItemWithDeviceKeychainPayload(_ payload: AppCredentialVaultPayload) throws {
        let data = try JSONEncoder().encode(payload)
        let deleteStatus = SecItemDelete(baseQuery() as CFDictionary)
        guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
            throw AppCredentialVaultError.unwritable(deleteStatus)
        }

        var query = baseQuery()
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw AppCredentialVaultError.unwritable(addStatus)
        }
        cachedPayload = payload
    }

    private func sharedAuthenticationContext() -> LAContext {
        if let authenticationContext {
            return authenticationContext
        }

        let context = LAContext()
        context.localizedReason = "Unlock Calendar Busy Sync credentials."
        context.touchIDAuthenticationAllowableReuseDuration = 300
        authenticationContext = context
        return context
    }

    private func localAuthenticationAccessControl() throws -> SecAccessControl {
        var error: Unmanaged<CFError>?
        guard let accessControl = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .userPresence,
            &error
        ) else {
            let message = error?.takeRetainedValue().localizedDescription ?? "unknown access-control error"
            throw AppCredentialVaultError.accessControlUnavailable(message)
        }

        return accessControl
    }
}
