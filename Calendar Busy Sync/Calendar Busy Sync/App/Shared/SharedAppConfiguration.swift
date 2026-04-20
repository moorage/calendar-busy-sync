import Foundation

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

    var auditTrailLogLength: AuditTrailLogLength {
        AuditTrailLogLength(rawValue: auditTrailLogLengthRawValue) ?? .last1000
    }
}

protocol SharedAppConfigurationStoring: AnyObject {
    var isAvailable: Bool { get }
    func loadConfiguration() -> SharedAppConfiguration?
    func saveConfiguration(_ configuration: SharedAppConfiguration)
    func startObserving(_ onChange: @escaping @MainActor (SharedAppConfiguration) -> Void)
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
}
