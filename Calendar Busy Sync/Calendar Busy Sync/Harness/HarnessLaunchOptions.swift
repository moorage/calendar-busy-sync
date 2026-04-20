import CoreGraphics
import Foundation
#if os(iOS)
import UIKit
#endif

enum HarnessPlatformTarget: String, Codable {
    case macos
    case ios
}

enum HarnessDeviceClass: String, Codable {
    case mac
    case iphone
    case ipad
}

enum AppStoreScreenshotMode: String, Codable {
    case overview
    case mirrors
    case logs
}

struct HarnessLaunchOptions {
    let scenarioRoot: URL?
    let scenarioName: String?
    let windowSize: CGSize?
    let dumpVisibleStateURL: URL?
    let dumpPerfStateURL: URL?
    let screenshotPathURL: URL?
    let commandDirectoryURL: URL?
    let uiTestMode: Bool
    let appStoreScreenshotMode: AppStoreScreenshotMode?
    let appStoreScreenshotOutputURL: URL?
    let platformTarget: HarnessPlatformTarget
    let deviceClass: HarnessDeviceClass

    init(
        scenarioRoot: URL? = nil,
        scenarioName: String? = nil,
        windowSize: CGSize? = nil,
        dumpVisibleStateURL: URL? = nil,
        dumpPerfStateURL: URL? = nil,
        screenshotPathURL: URL? = nil,
        commandDirectoryURL: URL? = nil,
        uiTestMode: Bool = false,
        appStoreScreenshotMode: AppStoreScreenshotMode? = nil,
        appStoreScreenshotOutputURL: URL? = nil,
        platformTarget: HarnessPlatformTarget,
        deviceClass: HarnessDeviceClass
    ) {
        self.scenarioRoot = scenarioRoot
        self.scenarioName = scenarioName
        self.windowSize = windowSize
        self.dumpVisibleStateURL = dumpVisibleStateURL
        self.dumpPerfStateURL = dumpPerfStateURL
        self.screenshotPathURL = screenshotPathURL
        self.commandDirectoryURL = commandDirectoryURL
        self.uiTestMode = uiTestMode
        self.appStoreScreenshotMode = appStoreScreenshotMode
        self.appStoreScreenshotOutputURL = appStoreScreenshotOutputURL
        self.platformTarget = platformTarget
        self.deviceClass = deviceClass
    }

    static func fromProcess(arguments: [String] = ProcessInfo.processInfo.arguments) -> HarnessLaunchOptions {
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
                return nil
            }
            return arguments[index + 1]
        }

        func resolveURL(after flag: String) -> URL? {
            guard let raw = value(after: flag) else { return nil }
            return resolvedURL(from: raw)
        }

        let windowSize = value(after: "--window-size").flatMap { raw -> CGSize? in
            let parts = raw.split(separator: "x").compactMap { Double($0) }
            guard parts.count == 2 else { return nil }
            return CGSize(width: parts[0], height: parts[1])
        }

        let platformTarget = HarnessPlatformTarget(rawValue: value(after: "--platform-target") ?? "") ?? defaultPlatformTarget()
        let deviceClass = HarnessDeviceClass(rawValue: value(after: "--device-class") ?? "") ?? defaultDeviceClass(for: platformTarget)

        return HarnessLaunchOptions(
            scenarioRoot: resolveURL(after: "--scenario-root"),
            scenarioName: value(after: "--scenario"),
            windowSize: windowSize,
            dumpVisibleStateURL: resolveURL(after: "--dump-visible-state"),
            dumpPerfStateURL: resolveURL(after: "--dump-perf-state"),
            screenshotPathURL: resolveURL(after: "--screenshot-path"),
            commandDirectoryURL: resolveURL(after: "--harness-command-dir"),
            uiTestMode: arguments.contains("--ui-test-mode"),
            appStoreScreenshotMode: AppStoreScreenshotMode(rawValue: value(after: "--app-store-screenshot") ?? ""),
            appStoreScreenshotOutputURL: resolveURL(after: "--app-store-screenshot-output"),
            platformTarget: platformTarget,
            deviceClass: deviceClass
        )
    }

    private static func resolvedURL(from raw: String) -> URL {
        if let absoluteURL = URL(string: raw), let scheme = absoluteURL.scheme, !scheme.isEmpty {
            return absoluteURL
        }

        let candidate = URL(fileURLWithPath: raw)
        if candidate.path.hasPrefix("/") {
            return candidate
        }

        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(raw)
    }

    private static func defaultPlatformTarget() -> HarnessPlatformTarget {
        #if os(macOS)
        return .macos
        #else
        return .ios
        #endif
    }

    private static func defaultDeviceClass(for platformTarget: HarnessPlatformTarget) -> HarnessDeviceClass {
        switch platformTarget {
        case .macos:
            return .mac
        case .ios:
            #if os(iOS)
            return UIDevice.current.userInterfaceIdiom == .pad ? .ipad : .iphone
            #else
            return .iphone
            #endif
        }
    }
}
