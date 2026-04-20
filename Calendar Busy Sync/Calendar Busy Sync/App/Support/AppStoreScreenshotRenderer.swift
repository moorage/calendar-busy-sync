#if os(macOS)
import AppKit
import SwiftUI

enum AppStoreScreenshotRenderer {
    @MainActor
    static func render(
        mode: AppStoreScreenshotMode,
        to outputURL: URL,
        size: CGSize = CGSize(width: 1440, height: 900)
    ) throws {
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let rootView = AppStoreScreenshotView(mode: mode)
            .frame(width: size.width, height: size.height)

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.appearance = NSAppearance(named: .aqua)
        hostingView.frame = CGRect(origin: .zero, size: size)
        hostingView.layoutSubtreeIfNeeded()

        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            throw CocoaError(.fileWriteUnknown)
        }

        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }

        try pngData.write(to: outputURL)
    }
}
#endif
