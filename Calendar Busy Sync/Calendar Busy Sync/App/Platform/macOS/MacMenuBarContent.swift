#if os(macOS)
import SwiftUI

struct MacMenuBarContent: View {
    @ObservedObject var appModel: AppModel
    @ObservedObject var shellModel: MacUtilityShellModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(appModel.currentActivitySummary, systemImage: appModel.currentActivityIconName)
                .font(.caption.weight(.medium))
                .lineLimit(2)

            Label(appModel.pendingActivityLabel, systemImage: "clock.badge.exclamationmark")
                .font(.caption)
                .foregroundStyle(.secondary)

            if appModel.failureCount > 0 {
                Label(appModel.failureCountLabel, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Divider()

            Button(shellModel.settingsMenuTitle) {
                openScene(AppSceneIDs.settings)
            }
            .accessibilityIdentifier(AccessibilityIDs.menuBarOpenSettingsButton)

            Button(shellModel.logsMenuTitle) {
                openScene(AppSceneIDs.auditTrail)
            }
            .accessibilityIdentifier(AccessibilityIDs.menuBarOpenLogsButton)

            Button("Sync Now") {
                Task {
                    await appModel.syncNow()
                }
            }
            .disabled(!appModel.canSyncNow)
            .accessibilityIdentifier(AccessibilityIDs.menuBarSyncNowButton)

            Toggle(
                "Launch at Login",
                isOn: Binding(
                    get: { shellModel.launchAtLoginEnabled },
                    set: { shellModel.setLaunchAtLoginEnabled($0) }
                )
            )
            .accessibilityIdentifier(AccessibilityIDs.menuBarLaunchAtLoginToggle)

            if let message = shellModel.launchAtLoginStatusMessage {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Button("Quit Calendar Busy Sync") {
                NSApplication.shared.terminate(nil)
            }
            .accessibilityIdentifier(AccessibilityIDs.menuBarQuitButton)
        }
        .frame(width: 260, alignment: .leading)
        .padding(10)
        .task {
            await appModel.prepareIfNeeded()
            shellModel.refreshLaunchAtLoginState()
        }
        .onOpenURL { url in
            appModel.handleIncomingURL(url)
            shellModel.activateApp()
        }
    }

    private func openScene(_ sceneID: String) {
        openWindow(id: sceneID)
        shellModel.activateApp()
    }
}
#endif
