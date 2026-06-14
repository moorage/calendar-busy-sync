import SwiftUI
#if os(iOS)
import BackgroundTasks
#endif
#if os(macOS)
import AppKit
import Darwin
#endif

@main
struct Calendar_Busy_SyncApp: App {
    @Environment(\.scenePhase) private var scenePhase
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
        #if os(macOS)
        Task { @MainActor in
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

            if resolvedLaunchOptions.bookingDryRunOnLaunch {
                let didWriteDraft = await appModel.runBookingDryRunForHarness()
                Darwin.exit(didWriteDraft ? 0 : 2)
            }

            await appModel.prepareIfNeeded()
        }
        if resolvedLaunchOptions.uiTestMode {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000)
                MacUITestSettingsWindowController.show(appModel: appModel)
            }
        }
        #endif
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
            macSettingsWindowContent
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

    private var macSettingsWindowContent: some View {
        settingsRootView
            .background(
                MacWindowVisibilityObserver(sceneID: AppSceneIDs.settings) { isVisible in
                    macShellModel.setWindowOpen(isVisible, for: AppSceneIDs.settings)
                }
            )
    }

    #endif

    @SceneBuilder
    private var mobileScenes: some Scene {
        WindowGroup {
            settingsRootView
        }
        #if os(iOS)
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .active:
                model.handleIOSSceneDidBecomeActive()
            case .background:
                model.handleIOSSceneDidEnterBackground()
            case .inactive:
                break
            @unknown default:
                break
            }
        }
        .backgroundTask(.appRefresh(IOSBackgroundRefreshConstants.taskIdentifier)) {
            await model.handleIOSBackgroundRefreshTask()
        }
        #endif

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

#if os(macOS)
@MainActor
private enum MacUITestSettingsWindowController {
    private static var window: NSWindow?

    static func show(appModel: AppModel) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let hostingController = NSHostingController(
            rootView: ContentView(model: appModel)
                .task {
                    await appModel.prepareIfNeeded()
                }
        )
        let settingsWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1020, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        settingsWindow.identifier = NSUserInterfaceItemIdentifier(AppSceneIDs.settings)
        settingsWindow.title = "Calendar Busy Sync"
        settingsWindow.contentViewController = hostingController
        settingsWindow.center()
        settingsWindow.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        window = settingsWindow
    }
}
#endif
