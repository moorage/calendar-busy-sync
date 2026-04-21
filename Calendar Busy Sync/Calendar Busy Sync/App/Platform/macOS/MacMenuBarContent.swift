#if os(macOS)
import SwiftUI

struct MacMenuBarContent: View {
    @ObservedObject var appModel: AppModel
    @ObservedObject var shellModel: MacUtilityShellModel
    @Environment(\.openWindow) private var openWindow
    @State private var presentedSnapshot: MenuPresentationSnapshot?

    var body: some View {
        let snapshot = presentedSnapshot ?? MenuPresentationSnapshot(appModel: appModel, shellModel: shellModel)

        VStack(alignment: .leading, spacing: 10) {
            Label(snapshot.currentActivitySummary, systemImage: snapshot.currentActivityIconName)
                .font(.caption.weight(.medium))
                .lineLimit(2)

            Label(snapshot.pendingActivityLabel, systemImage: "clock.badge.exclamationmark")
                .font(.caption)
                .foregroundStyle(.secondary)

            if snapshot.failureCount > 0 {
                Label(snapshot.failureCountLabel, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Divider()

            Button(snapshot.settingsMenuTitle) {
                openScene(AppSceneIDs.settings)
            }
            .accessibilityIdentifier(AccessibilityIDs.menuBarOpenSettingsButton)

            Button(snapshot.logsMenuTitle) {
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
        .onAppear {
            presentedSnapshot = MenuPresentationSnapshot(appModel: appModel, shellModel: shellModel)
        }
        .onDisappear {
            presentedSnapshot = nil
        }
        .task {
            await appModel.prepareIfNeeded()
            shellModel.refreshLaunchAtLoginState()
        }
    }

    private func openScene(_ sceneID: String) {
        shellModel.presentScene(sceneID) { targetSceneID in
            openWindow(id: targetSceneID)
        }
    }
}

private struct MenuPresentationSnapshot: Equatable {
    let currentActivitySummary: String
    let currentActivityIconName: String
    let pendingActivityLabel: String
    let failureCount: Int
    let failureCountLabel: String
    let settingsMenuTitle: String
    let logsMenuTitle: String

    init(appModel: AppModel, shellModel: MacUtilityShellModel) {
        currentActivitySummary = appModel.currentActivitySummary
        currentActivityIconName = appModel.currentActivityIconName
        pendingActivityLabel = appModel.pendingActivityLabel
        failureCount = appModel.failureCount
        failureCountLabel = appModel.failureCountLabel
        settingsMenuTitle = shellModel.settingsMenuTitle
        logsMenuTitle = shellModel.logsMenuTitle
    }
}
#endif
