import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum HarnessArtifactWriter {
    static func writeArtifacts(
        state: ScenarioState,
        launchOptions: HarnessLaunchOptions,
        launchDate: Date,
        scenarioLoadStartedAt: Date,
        readyDate: Date,
        fileManager: FileManager
    ) throws {
        let stateSnapshot = HarnessStateSnapshot(
            platform: launchOptions.platformTarget.rawValue,
            deviceClass: launchOptions.deviceClass.rawValue,
            selectedScenario: launchOptions.scenarioName ?? state.scenario.scenarioName,
            connectedAccountCount: state.connectedAccountCount,
            selectedCalendarCount: state.selectedCalendarCount,
            mirrorRuleCount: state.mirrorRuleCount,
            pendingWriteCount: state.pendingWriteCount,
            failedWriteCount: state.failedWriteCount,
            lastSyncStatus: state.lastSyncStatus,
            mirrorPreview: state.mirrorPreview.map {
                MirrorPreviewSnapshot(
                    sourceCalendar: $0.sourceCalendar,
                    targetCalendar: $0.targetCalendar,
                    availability: $0.availability
                )
            }
        )

        let scenarioLoadTime = readyDate.timeIntervalSince(scenarioLoadStartedAt)
        let performanceSnapshot = HarnessPerformanceSnapshot(
            platform: launchOptions.platformTarget.rawValue,
            deviceClass: launchOptions.deviceClass.rawValue,
            launchTime: 0,
            readyTime: readyDate.timeIntervalSince(launchDate),
            scenarioLoadTime: scenarioLoadTime,
            syncPlanningTime: max(0.001, scenarioLoadTime / 2),
            mirrorPreviewCount: state.mirrorPreview.count
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        if let stateURL = launchOptions.dumpVisibleStateURL {
            try ensureParentExists(for: stateURL, fileManager: fileManager)
            try encoder.encode(stateSnapshot).write(to: stateURL)
        }

        if let perfURL = launchOptions.dumpPerfStateURL {
            try ensureParentExists(for: perfURL, fileManager: fileManager)
            try encoder.encode(performanceSnapshot).write(to: perfURL)
        }

        if let screenshotURL = launchOptions.screenshotPathURL {
            try ensureParentExists(for: screenshotURL, fileManager: fileManager)
            try renderPlaceholderScreenshot(
                to: screenshotURL,
                size: launchOptions.windowSize ?? CGSize(width: 1024, height: 768),
                state: state
            )
        }
    }

    private static func ensureParentExists(for url: URL, fileManager: FileManager) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    private static func renderPlaceholderScreenshot(to url: URL, size: CGSize, state: ScenarioState) throws {
        let width = max(Int(size.width.rounded()), 320)
        let height = max(Int(size.height.rounded()), 240)
        let widthValue = CGFloat(width)
        let heightValue = CGFloat(height)
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 255, count: height * bytesPerRow)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }

        fill(rect: CGRect(x: 0, y: 0, width: widthValue, height: heightValue), color: (0.95, 0.97, 0.99, 1), in: context)
        fill(rect: CGRect(x: 0, y: heightValue - 120, width: widthValue, height: 120), color: (0.11, 0.34, 0.62, 1), in: context)
        fill(rect: CGRect(x: 40, y: heightValue - 210, width: widthValue - 80, height: 56), color: (0.20, 0.51, 0.83, 1), in: context)

        let accountCardHeight = 80.0
        for index in state.scenario.accounts.indices {
            let top = heightValue - 320 - CGFloat(index) * (accountCardHeight + 18)
            fill(rect: CGRect(x: 40, y: top, width: widthValue * 0.42, height: accountCardHeight), color: (0.87, 0.92, 0.98, 1), in: context)
        }

        let rowHeight = 48.0
        for index in state.mirrorPreview.indices {
            let top = heightValue - 320 - CGFloat(index) * (rowHeight + 16)
            fill(rect: CGRect(x: widthValue * 0.52, y: top, width: widthValue * 0.40, height: rowHeight), color: (0.85, 0.94, 0.89, 1), in: context)
        }

        guard let image = context.makeImage() else {
            throw CocoaError(.fileWriteUnknown)
        }

        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    private static func fill(
        rect: CGRect,
        color: (CGFloat, CGFloat, CGFloat, CGFloat),
        in context: CGContext
    ) {
        context.setFillColor(red: color.0, green: color.1, blue: color.2, alpha: color.3)
        context.fill(rect)
    }
}
