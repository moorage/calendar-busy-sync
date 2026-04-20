import SwiftUI
#if os(macOS)
import Darwin
#endif

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
        _macShellModel = StateObject(
            wrappedValue: MacUtilityShellModel(
                managesDockVisibility: resolvedRuntimeMode == .standard
            )
        )
        #endif
        Task { @MainActor in
            #if os(macOS)
            if let screenshotMode = resolvedLaunchOptions.appStoreScreenshotMode,
               let outputURL = resolvedLaunchOptions.appStoreScreenshotOutputURL {
                do {
                    try AppStoreScreenshotRenderer.render(mode: screenshotMode, to: outputURL)
                    Darwin.exit(0)
                } catch {
                    FileHandle.standardError.write(Data("App Store screenshot render failed: \(error)\n".utf8))
                    Darwin.exit(1)
                }
            }
            #endif

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

        Window("Calendar Busy Sync", id: AppSceneIDs.settings) {
            settingsRootView
                .background(
                    MacWindowVisibilityObserver(sceneID: AppSceneIDs.settings) { isVisible in
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

        Window("Audit Trail", id: AppSceneIDs.auditTrail) {
            auditTrailRootView
                .background(
                    MacWindowVisibilityObserver(sceneID: AppSceneIDs.auditTrail) { isVisible in
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
        Group {
            if let screenshotMode = launchOptions.appStoreScreenshotMode {
                AppStoreScreenshotView(mode: screenshotMode)
            } else {
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
        }
    }

    private var auditTrailRootView: some View {
        Group {
            if let screenshotMode = launchOptions.appStoreScreenshotMode {
                AppStoreScreenshotView(mode: screenshotMode)
            } else {
                AuditTrailView(model: model)
            }
        }
    }
}
