import SwiftUI

@main
struct Calendar_Busy_SyncApp: App {
    private let launchOptions: HarnessLaunchOptions
    @StateObject private var model: AppModel

    init() {
        let resolvedLaunchOptions = HarnessLaunchOptions.fromProcess()
        launchOptions = resolvedLaunchOptions
        _model = StateObject(wrappedValue: AppModel(launchOptions: resolvedLaunchOptions))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .task {
                    await model.prepareIfNeeded()
                }
                .onOpenURL { url in
                    model.handleIncomingURL(url)
                }
        }
    }
}
