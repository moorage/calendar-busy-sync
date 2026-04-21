import Foundation

#if os(iOS)
import BackgroundTasks
import UIKit
#endif

enum IOSBackgroundRefreshAvailability: Equatable {
    case unsupported
    case available
    case denied
    case restricted
}

extension IOSBackgroundRefreshAvailability {
    var statusLabel: String {
        switch self {
        case .unsupported:
            return "Unavailable"
        case .available:
            return "On"
        case .denied:
            return "Off"
        case .restricted:
            return "Restricted"
        }
    }

    var auditStatus: String {
        switch self {
        case .unsupported:
            return "blocked"
        case .available:
            return "ready"
        case .denied:
            return "pending"
        case .restricted:
            return "blocked"
        }
    }
}

enum IOSBackgroundRefreshConstants {
    static let taskIdentifier = "com.matthewpaulmoore.Calendar-Busy-Sync.app-refresh"
    static let earliestBeginInterval: TimeInterval = 15 * 60
}

enum IOSBackgroundRefreshState: Equatable {
    case unsupported
    case denied
    case restricted
    case scheduled(Date)
    case failed(String)
}

protocol IOSBackgroundRefreshScheduling {
    var availability: IOSBackgroundRefreshAvailability { get }
    func submitAppRefresh(identifier: String, earliestBeginDate: Date) throws
    func cancelAppRefresh(identifier: String)
}

struct SystemIOSBackgroundRefreshScheduler: IOSBackgroundRefreshScheduling {
    var availability: IOSBackgroundRefreshAvailability {
        #if os(iOS)
        switch UIApplication.shared.backgroundRefreshStatus {
        case .available:
            return .available
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .restricted
        }
        #else
        return .unsupported
        #endif
    }

    func submitAppRefresh(identifier: String, earliestBeginDate: Date) throws {
        #if os(iOS)
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = earliestBeginDate
        try BGTaskScheduler.shared.submit(request)
        #endif
    }

    func cancelAppRefresh(identifier: String) {
        #if os(iOS)
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
        #endif
    }
}
