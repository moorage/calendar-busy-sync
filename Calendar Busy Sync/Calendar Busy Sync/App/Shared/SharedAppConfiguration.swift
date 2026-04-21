import Foundation

enum SharedConfigurationSyncState: Equatable {
    case disabled
    case unavailable
    case idle
    case syncing
    case succeeded(message: String, at: Date)
    case failed(message: String, at: Date)

    var statusLabel: String {
        switch self {
        case .disabled:
            return "Off"
        case .unavailable:
            return "Unavailable"
        case .idle:
            return "Ready"
        case .syncing:
            return "Syncing…"
        case .succeeded:
            return "Updated"
        case .failed:
            return "Failed"
        }
    }

    var detail: String {
        switch self {
        case .disabled:
            return "Shared settings are off on this device. Calendar choices and advanced preferences stay local here."
        case .unavailable:
            return "iCloud is unavailable right now, so this device will keep local settings until iCloud returns."
        case .idle:
            return "Shared settings are enabled. Start an iCloud sync to compare this device with the shared configuration now."
        case let .succeeded(message, _), let .failed(message, _):
            return message
        case .syncing:
            return "Starting an iCloud shared-settings sync request now."
        }
    }

    var updatedAt: Date? {
        switch self {
        case let .succeeded(_, at), let .failed(_, at):
            return at
        case .disabled, .unavailable, .idle, .syncing:
            return nil
        }
    }

    var isFailure: Bool {
        if case .failed = self {
            return true
        }

        return false
    }
}

struct SharedAppleCalendarReference: Codable, Equatable {
    let title: String
    let sourceTitle: String
    let sourceKind: AppleCalendarSourceKind

    init(calendar: AppleCalendarSummary) {
        self.title = calendar.title
        self.sourceTitle = calendar.sourceTitle
        self.sourceKind = calendar.sourceKind
    }
}

struct SharedAppConfiguration: Codable, Equatable {
    let updatedAt: Date
    let pollIntervalMinutes: Int
    let auditTrailLogLengthRawValue: String
    let isAppleCalendarEnabled: Bool
    let selectedAppleCalendarReference: SharedAppleCalendarReference?
    let usesCustomGoogleOAuthApp: Bool
    let customGoogleOAuthClientID: String
    let customGoogleOAuthServerClientID: String
    let googleSelectedCalendarIDs: [String: String]
    let activeGoogleAccountID: String?
    let googleAccountDescriptors: [SharedGoogleAccountDescriptor]

    var auditTrailLogLength: AuditTrailLogLength {
        AuditTrailLogLength(rawValue: auditTrailLogLengthRawValue) ?? .last1000
    }

    init(
        updatedAt: Date,
        pollIntervalMinutes: Int,
        auditTrailLogLengthRawValue: String,
        isAppleCalendarEnabled: Bool,
        selectedAppleCalendarReference: SharedAppleCalendarReference?,
        usesCustomGoogleOAuthApp: Bool,
        customGoogleOAuthClientID: String,
        customGoogleOAuthServerClientID: String,
        googleSelectedCalendarIDs: [String: String],
        activeGoogleAccountID: String?,
        googleAccountDescriptors: [SharedGoogleAccountDescriptor] = []
    ) {
        self.updatedAt = updatedAt
        self.pollIntervalMinutes = pollIntervalMinutes
        self.auditTrailLogLengthRawValue = auditTrailLogLengthRawValue
        self.isAppleCalendarEnabled = isAppleCalendarEnabled
        self.selectedAppleCalendarReference = selectedAppleCalendarReference
        self.usesCustomGoogleOAuthApp = usesCustomGoogleOAuthApp
        self.customGoogleOAuthClientID = customGoogleOAuthClientID
        self.customGoogleOAuthServerClientID = customGoogleOAuthServerClientID
        self.googleSelectedCalendarIDs = googleSelectedCalendarIDs
        self.activeGoogleAccountID = activeGoogleAccountID
        self.googleAccountDescriptors = googleAccountDescriptors
    }

    private enum CodingKeys: String, CodingKey {
        case updatedAt
        case pollIntervalMinutes
        case auditTrailLogLengthRawValue
        case isAppleCalendarEnabled
        case selectedAppleCalendarReference
        case usesCustomGoogleOAuthApp
        case customGoogleOAuthClientID
        case customGoogleOAuthServerClientID
        case googleSelectedCalendarIDs
        case activeGoogleAccountID
        case googleAccountDescriptors
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        pollIntervalMinutes = try container.decode(Int.self, forKey: .pollIntervalMinutes)
        auditTrailLogLengthRawValue = try container.decode(String.self, forKey: .auditTrailLogLengthRawValue)
        isAppleCalendarEnabled = try container.decode(Bool.self, forKey: .isAppleCalendarEnabled)
        selectedAppleCalendarReference = try container.decodeIfPresent(SharedAppleCalendarReference.self, forKey: .selectedAppleCalendarReference)
        usesCustomGoogleOAuthApp = try container.decode(Bool.self, forKey: .usesCustomGoogleOAuthApp)
        customGoogleOAuthClientID = try container.decode(String.self, forKey: .customGoogleOAuthClientID)
        customGoogleOAuthServerClientID = try container.decode(String.self, forKey: .customGoogleOAuthServerClientID)
        googleSelectedCalendarIDs = try container.decode([String: String].self, forKey: .googleSelectedCalendarIDs)
        activeGoogleAccountID = try container.decodeIfPresent(String.self, forKey: .activeGoogleAccountID)
        googleAccountDescriptors = try container.decodeIfPresent([SharedGoogleAccountDescriptor].self, forKey: .googleAccountDescriptors) ?? []
    }
}

protocol SharedAppConfigurationStoring: AnyObject {
    var isAvailable: Bool { get }
    func loadConfiguration() -> SharedAppConfiguration?
    func saveConfiguration(_ configuration: SharedAppConfiguration)
    func startObserving(_ onChange: @escaping @MainActor (SharedAppConfiguration) -> Void)
    @discardableResult
    func requestSync() -> Bool
}

final class ICloudSharedAppConfigurationStore: SharedAppConfigurationStoring {
    private enum StorageKey {
        static let sharedConfiguration = "shared-app-configuration.v1"
    }

    private let store: NSUbiquitousKeyValueStore
    private let notificationCenter: NotificationCenter
    private let ubiquityIdentityTokenProvider: () -> Any?
    private var observer: NSObjectProtocol?

    init(
        store: NSUbiquitousKeyValueStore = .default,
        notificationCenter: NotificationCenter = .default,
        ubiquityIdentityTokenProvider: @escaping () -> Any? = { FileManager.default.ubiquityIdentityToken }
    ) {
        self.store = store
        self.notificationCenter = notificationCenter
        self.ubiquityIdentityTokenProvider = ubiquityIdentityTokenProvider
    }

    deinit {
        if let observer {
            notificationCenter.removeObserver(observer)
        }
    }

    var isAvailable: Bool {
        ubiquityIdentityTokenProvider() != nil
    }

    func loadConfiguration() -> SharedAppConfiguration? {
        guard isAvailable else {
            return nil
        }

        store.synchronize()
        guard let data = store.data(forKey: StorageKey.sharedConfiguration) else {
            return nil
        }

        return try? JSONDecoder().decode(SharedAppConfiguration.self, from: data)
    }

    func saveConfiguration(_ configuration: SharedAppConfiguration) {
        guard isAvailable else {
            return
        }

        guard let data = try? JSONEncoder().encode(configuration) else {
            return
        }

        store.set(data, forKey: StorageKey.sharedConfiguration)
        store.synchronize()
    }

    func startObserving(_ onChange: @escaping @MainActor (SharedAppConfiguration) -> Void) {
        if observer != nil {
            return
        }

        observer = notificationCenter.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            queue: nil
        ) { [weak self] _ in
            guard let self, let configuration = self.loadConfiguration() else {
                return
            }

            Task { @MainActor in
                onChange(configuration)
            }
        }
    }

    @discardableResult
    func requestSync() -> Bool {
        guard isAvailable else {
            return false
        }

        return store.synchronize()
    }
}
