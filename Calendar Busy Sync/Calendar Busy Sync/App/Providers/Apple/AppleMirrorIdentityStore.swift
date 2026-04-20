import Foundation

enum AppleMirrorIdentityStoreError: LocalizedError, Equatable {
    case corruptPayload
    case encodeFailure

    var errorDescription: String? {
        switch self {
        case .corruptPayload:
            return "Stored Apple mirror metadata is corrupt and could not be decoded."
        case .encodeFailure:
            return "Stored Apple mirror metadata could not be encoded."
        }
    }
}

protocol AppleMirrorIdentityStoring {
    func sourceKey(for token: String) throws -> BusyMirrorSourceKey?
    func setSourceKey(_ sourceKey: BusyMirrorSourceKey, for token: String) throws
    func removeSourceKey(for token: String) throws
}

struct AppleMirrorIdentityStore: AppleMirrorIdentityStoring {
    private let userDefaults: UserDefaults
    private let storageKey: String

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String? = nil
    ) {
        self.userDefaults = userDefaults
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "CalendarBusySync"
        self.storageKey = storageKey ?? "\(bundleIdentifier).apple-mirror-identities"
    }

    func sourceKey(for token: String) throws -> BusyMirrorSourceKey? {
        try loadMappings()[token]
    }

    func setSourceKey(_ sourceKey: BusyMirrorSourceKey, for token: String) throws {
        var mappings = try loadMappings()
        mappings[token] = sourceKey
        try saveMappings(mappings)
    }

    func removeSourceKey(for token: String) throws {
        var mappings = try loadMappings()
        mappings.removeValue(forKey: token)
        try saveMappings(mappings)
    }

    private func loadMappings() throws -> [String: BusyMirrorSourceKey] {
        guard let data = userDefaults.data(forKey: storageKey) else {
            return [:]
        }

        do {
            return try JSONDecoder().decode([String: BusyMirrorSourceKey].self, from: data)
        } catch {
            throw AppleMirrorIdentityStoreError.corruptPayload
        }
    }

    private func saveMappings(_ mappings: [String: BusyMirrorSourceKey]) throws {
        if mappings.isEmpty {
            userDefaults.removeObject(forKey: storageKey)
            return
        }

        let data: Data
        do {
            data = try JSONEncoder().encode(mappings)
        } catch {
            throw AppleMirrorIdentityStoreError.encodeFailure
        }
        userDefaults.set(data, forKey: storageKey)
    }
}

struct AppleManagedMirrorMarker: Equatable {
    static let scheme = "calendarbusysync"
    static let host = "mirror"

    let token: String

    init(token: String) {
        self.token = token
    }

    init?(url: URL?) {
        guard
            let url,
            url.scheme == Self.scheme,
            url.host == Self.host
        else {
            return nil
        }

        let token = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !token.isEmpty else {
            return nil
        }

        self.token = token
    }

    var url: URL {
        URL(string: "\(Self.scheme)://\(Self.host)/\(token)")!
    }

    static func makeToken() -> String {
        UUID().uuidString.lowercased()
    }
}
