import SwiftUI

@main
struct Calendar_Busy_SyncApp: App {
    private let launchOptions: HarnessLaunchOptions
    private let runtimeMode: AppRuntimeMode
    @StateObject private var model: AppModel
    #if os(macOS)
    @StateObject private var macShellModel: MacUtilityShellModel
    #endif

    init() {
        let resolvedRuntimeMode = AppRuntimeMode.from(processInfo: .processInfo)
        let resolvedLaunchOptions = HarnessLaunchOptions.fromProcess()
        let appModel = AppModel(launchOptions: resolvedLaunchOptions)
        runtimeMode = resolvedRuntimeMode
        launchOptions = resolvedLaunchOptions
        _model = StateObject(wrappedValue: appModel)
        #if os(macOS)
        _macShellModel = StateObject(wrappedValue: MacUtilityShellModel())
        #endif
        Task { @MainActor in
            await appModel.prepareIfNeeded()
        }
    }

    var body: some Scene {
        #if os(macOS)
        macOSScenes
        #else
        mobileScenes
        #endif
    }

    #if os(macOS)
    @SceneBuilder
    private var macOSScenes: some Scene {
        MenuBarExtra {
            MacMenuBarContent(appModel: model, shellModel: macShellModel)
        } label: {
            Image(systemName: macShellModel.menuBarIconName)
        }

        WindowGroup("Calendar Busy Sync", id: AppSceneIDs.settings) {
            settingsRootView
                .background(
                    MacWindowVisibilityObserver { isVisible in
                        macShellModel.setWindowOpen(isVisible, for: AppSceneIDs.settings)
                    }
                )
                .background(
                    MacInitialWindowSuppressor(
                        shouldSuppress: runtimeMode == .standard && macShellModel.shouldSuppressInitialSettingsWindow(
                            uiTestMode: launchOptions.uiTestMode
                        )
                    )
                )
        }

        WindowGroup("Audit Trail", id: AppSceneIDs.auditTrail) {
            auditTrailRootView
                .background(
                    MacWindowVisibilityObserver { isVisible in
                        macShellModel.setWindowOpen(isVisible, for: AppSceneIDs.auditTrail)
                    }
                )
        }
    }
    #endif

    @SceneBuilder
    private var mobileScenes: some Scene {
        WindowGroup {
            settingsRootView
        }

        WindowGroup("Audit Trail", id: AppSceneIDs.auditTrail) {
            auditTrailRootView
        }
    }

    private var settingsRootView: some View {
        ContentView(model: model)
            .task {
                await model.prepareIfNeeded()
            }
            .onOpenURL { url in
                model.handleIncomingURL(url)
                #if os(macOS)
                macShellModel.activateApp()
                #endif
            }
    }

    private var auditTrailRootView: some View {
        AuditTrailView(model: model)
    }
}
