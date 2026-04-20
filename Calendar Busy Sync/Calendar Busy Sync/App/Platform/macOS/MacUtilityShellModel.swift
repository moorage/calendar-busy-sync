#if os(macOS)
import AppKit
import Combine
import Foundation
import ServiceManagement

final class MacUtilityShellModel: ObservableObject {
    private(set) var isSettingsWindowOpen = false
    private(set) var isAuditTrailWindowOpen = false
    private(set) var launchAtLoginEnabled: Bool
    private(set) var launchAtLoginStatusMessage: String?

    private let launchAtLoginService: any MacLaunchAtLoginControlling
    private var hasConsumedInitialSettingsWindowSuppression = false

    init(launchAtLoginService: (any MacLaunchAtLoginControlling)? = nil) {
        let resolvedService = launchAtLoginService ?? MacLaunchAtLoginService()
        self.launchAtLoginService = resolvedService
        self.launchAtLoginEnabled = resolvedService.status == .enabled
        self.launchAtLoginStatusMessage = Self.statusMessage(for: resolvedService.status)
    }

    var menuBarIconName: String {
        if isSettingsWindowOpen {
            return "calendar.circle.fill"
        }

        switch launchAtLoginService.status {
        case .requiresApproval:
            return "calendar.badge.exclamationmark"
        default:
            return "calendar.circle"
        }
    }

    var settingsMenuTitle: String {
        isSettingsWindowOpen ? "Bring Settings Forward" : "Open Settings"
    }

    var logsMenuTitle: String {
        isAuditTrailWindowOpen ? "Bring Logs Forward" : "Open Logs"
    }

    func setWindowOpen(_ isOpen: Bool, for sceneID: String) {
        switch sceneID {
        case AppSceneIDs.settings:
            guard isSettingsWindowOpen != isOpen else { return }
            objectWillChange.send()
            isSettingsWindowOpen = isOpen
        case AppSceneIDs.auditTrail:
            guard isAuditTrailWindowOpen != isOpen else { return }
            objectWillChange.send()
            isAuditTrailWindowOpen = isOpen
        default:
            break
        }
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        do {
            try launchAtLoginService.setEnabled(enabled)
            refreshLaunchAtLoginState()
        } catch {
            refreshLaunchAtLoginState()
            guard launchAtLoginStatusMessage != error.localizedDescription else {
                return
            }
            objectWillChange.send()
            launchAtLoginStatusMessage = error.localizedDescription
        }
    }

    func refreshLaunchAtLoginState() {
        let status = launchAtLoginService.status
        let nextEnabled = status == .enabled
        let nextMessage = Self.statusMessage(for: status)
        guard launchAtLoginEnabled != nextEnabled || launchAtLoginStatusMessage != nextMessage else {
            return
        }

        objectWillChange.send()
        launchAtLoginEnabled = status == .enabled
        launchAtLoginStatusMessage = nextMessage
    }

    func shouldSuppressInitialSettingsWindow(uiTestMode: Bool) -> Bool {
        guard !uiTestMode, !hasConsumedInitialSettingsWindowSuppression else {
            return false
        }

        hasConsumedInitialSettingsWindowSuppression = true
        return true
    }

    func activateApp() {
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private static func statusMessage(for status: SMAppService.Status) -> String? {
        switch status {
        case .enabled:
            return nil
        case .requiresApproval:
            return "Launch at login still needs approval in System Settings."
        case .notFound:
            return "Launch-at-login registration is unavailable for this build."
        case .notRegistered:
            return nil
        @unknown default:
            return "Launch-at-login status is unavailable."
        }
    }
}
#endif
