import Foundation

enum ScenarioLoaderError: LocalizedError {
    case missingScenarioRoot
    case missingScenarioName
    case missingScenarioFile(URL)

    var errorDescription: String? {
        switch self {
        case .missingScenarioRoot:
            return "Missing --scenario-root launch argument."
        case .missingScenarioName:
            return "Missing --scenario launch argument."
        case let .missingScenarioFile(url):
            return "Scenario file does not exist at \(url.path)."
        }
    }
}

struct ScenarioLoader {
    private let decoder = JSONDecoder()

    func load(rootURL: URL, scenarioName: String) throws -> ScenarioState {
        let scenarioURL = rootURL.appendingPathComponent(scenarioName)
        guard FileManager.default.fileExists(atPath: scenarioURL.path) else {
            throw ScenarioLoaderError.missingScenarioFile(scenarioURL)
        }

        let data = try Data(contentsOf: scenarioURL)
        let scenario = try decoder.decode(BusySyncScenario.self, from: data)
        return ScenarioState.build(from: scenario)
    }

    func load(using launchOptions: HarnessLaunchOptions) throws -> ScenarioState {
        guard let scenarioRoot = launchOptions.scenarioRoot else {
            throw ScenarioLoaderError.missingScenarioRoot
        }
        guard let scenarioName = launchOptions.scenarioName else {
            throw ScenarioLoaderError.missingScenarioName
        }
        return try load(rootURL: scenarioRoot, scenarioName: scenarioName)
    }
}
