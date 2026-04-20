import Foundation

enum AppRuntimeMode {
    case standard
    case hostedTests

    static func from(processInfo: ProcessInfo) -> AppRuntimeMode {
        let environment = processInfo.environment
        let hostedTestKeys = [
            "XCTestConfigurationFilePath",
            "XCTestBundlePath",
            "XCInjectBundle",
            "XCInjectBundleInto",
        ]

        return hostedTestKeys.contains(where: { environment[$0] != nil }) ? .hostedTests : .standard
    }
}
