import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var state: ScenarioState?
    @Published private(set) var lastErrorMessage: String?

    let launchOptions: HarnessLaunchOptions

    private let loader: ScenarioLoader
    private let fileManager: FileManager
    private let launchDate: Date
    private var hasPrepared = false

    init(
        launchOptions: HarnessLaunchOptions,
        fileManager: FileManager = .default,
        launchDate: Date = Date()
    ) {
        self.launchOptions = launchOptions
        self.loader = ScenarioLoader()
        self.fileManager = fileManager
        self.launchDate = launchDate
    }

    func prepareIfNeeded() async {
        guard !hasPrepared else { return }
        hasPrepared = true

        let scenarioLoadStart = Date()

        do {
            let loadedState = try loader.load(using: launchOptions)
            state = loadedState
            let readyDate = Date()
            try HarnessArtifactWriter.writeArtifacts(
                state: loadedState,
                launchOptions: launchOptions,
                launchDate: launchDate,
                scenarioLoadStartedAt: scenarioLoadStart,
                readyDate: readyDate,
                fileManager: fileManager
            )
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }
}
