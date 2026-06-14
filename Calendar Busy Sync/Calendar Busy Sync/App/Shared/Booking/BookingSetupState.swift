import Foundation

enum BookingSetupStep: String, CaseIterable, Identifiable, Sendable {
    case page
    case publish
    case inbox
    case test

    var id: String { rawValue }

    var title: String {
        switch self {
        case .page:
            return BookingCopy.SetupStep.pageHeading
        case .publish:
            return BookingCopy.SetupStep.publishHeading
        case .inbox:
            return BookingCopy.SetupStep.inboxHeading
        case .test:
            return BookingCopy.SetupStep.testHeading
        }
    }

    var shortTitle: String {
        switch self {
        case .page:
            return "Page"
        case .publish:
            return "Publish"
        case .inbox:
            return "Inbox"
        case .test:
            return "Test"
        }
    }

    var body: String {
        switch self {
        case .page:
            return BookingCopy.SetupStep.pageBody
        case .publish:
            return BookingCopy.SetupStep.publishBody
        case .inbox:
            return BookingCopy.SetupStep.inboxBody
        case .test:
            return BookingCopy.SetupStep.testBody
        }
    }

    var iconName: String {
        switch self {
        case .page:
            return BookingIconography.pageStep.primarySystemName
        case .publish:
            return BookingIconography.publishStep.primarySystemName
        case .inbox:
            return BookingIconography.inboxStep.primarySystemName
        case .test:
            return BookingIconography.testStep.primarySystemName
        }
    }
}

enum BookingPublicationStatus: String, Codable, Equatable, Sendable {
    case notPublished
    case generatedLocally
    case uploaded
    case published
    case needsPublish
    case publishFailed
    case disabled

    var label: String {
        switch self {
        case .notPublished:
            return "Not set up"
        case .generatedLocally:
            return "Generated locally"
        case .uploaded:
            return "Uploaded, waiting for Pages"
        case .published:
            return "Live"
        case .needsPublish:
            return "Live, changes pending"
        case .publishFailed:
            return "Verification failed"
        case .disabled:
            return "Disabled"
        }
    }
}

enum BookingInboxStatus: String, Codable, Equatable, Sendable {
    case notConnected
    case configured
    case reachable
    case connected
    case needsCheck
    case cannotReachInbox
    case allowedOriginMismatch
    case importFailed
    case disabled

    var label: String {
        switch self {
        case .notConnected:
            return "Not connected"
        case .configured:
            return "Configured"
        case .reachable:
            return "Reachable"
        case .connected:
            return "Ready"
        case .needsCheck:
            return "Needs check"
        case .cannotReachInbox:
            return "Cannot reach inbox"
        case .allowedOriginMismatch:
            return "Allowed-origin mismatch"
        case .importFailed:
            return "Import failed"
        case .disabled:
            return "Disabled"
        }
    }
}

enum BookingAppointmentTypeLifecycleStatus: Equatable, Sendable {
    case draft
    case live
    case changedLocally
    case paused
    case noSlots
    case broken(String)

    var label: String {
        switch self {
        case .draft:
            return "Draft"
        case .live:
            return "Live"
        case .changedLocally:
            return "Changed"
        case .paused:
            return "Paused"
        case .noSlots:
            return "No slots"
        case .broken:
            return "Broken"
        }
    }
}

struct BookingSetupSnapshot: Codable, Equatable, Sendable {
    var pageStatus: BookingPublicationStatus
    var inboxStatus: BookingInboxStatus
    var pendingRequestCount: Int
    var lastMessage: String?

    static let notStarted = BookingSetupSnapshot(
        pageStatus: .notPublished,
        inboxStatus: .notConnected,
        pendingRequestCount: 0,
        lastMessage: nil
    )

    var isReady: Bool {
        pageStatus == .published && inboxStatus == .connected
    }

    var hasStarted: Bool {
        pageStatus != .notPublished || inboxStatus != .notConnected || pendingRequestCount > 0
    }

    var headline: String {
        if isReady {
            return BookingCopy.Settings.readyTitle
        }

        return hasStarted ? BookingCopy.Settings.finishTitle : BookingCopy.Settings.setUpTitle
    }

    var detail: String {
        if isReady {
            return BookingCopy.Settings.readyBody
        }

        return hasStarted ? BookingCopy.Settings.finishBody : BookingCopy.Settings.setUpBody
    }

    var primaryActionTitle: String {
        hasStarted ? BookingCopy.Settings.finishAction : BookingCopy.Settings.setUpAction
    }

    var nextSetupStep: BookingSetupStep {
        switch pageStatus {
        case .notPublished, .publishFailed, .disabled:
            return .page
        case .generatedLocally, .uploaded, .needsPublish:
            return .publish
        case .published:
            break
        }

        switch inboxStatus {
        case .notConnected, .configured, .reachable, .needsCheck, .cannotReachInbox, .allowedOriginMismatch, .importFailed, .disabled:
            return .inbox
        case .connected:
            return .test
        }
    }

    var shouldEmphasizePageGeneration: Bool {
        switch pageStatus {
        case .notPublished, .needsPublish, .publishFailed:
            return true
        case .generatedLocally, .uploaded, .published, .disabled:
            return false
        }
    }

    var shouldEmphasizePublish: Bool {
        switch pageStatus {
        case .generatedLocally, .needsPublish:
            return true
        case .notPublished, .uploaded, .published, .publishFailed, .disabled:
            return false
        }
    }

    var shouldEmphasizeVerification: Bool {
        switch pageStatus {
        case .uploaded, .publishFailed:
            return true
        case .notPublished, .generatedLocally, .published, .needsPublish, .disabled:
            return false
        }
    }

    var requestsLabel: String {
        guard pendingRequestCount > 0 else {
            return BookingCopy.StatusCard.noBookingRequests
        }

        return pendingRequestCount == 1 ? "1 pending" : "\(pendingRequestCount) pending"
    }
}
