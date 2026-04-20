#if os(macOS)
import AppKit
import Foundation

protocol MacApplicationControlling {
    func activate(ignoringOtherApps: Bool)
    func setDockVisible(_ isVisible: Bool)
    func bringWindowToFront(sceneID: String)
}

final class MacApplicationController: MacApplicationControlling {
    func activate(ignoringOtherApps: Bool) {
        NSApplication.shared.activate(ignoringOtherApps: ignoringOtherApps)
    }

    func setDockVisible(_ isVisible: Bool) {
        let targetPolicy: NSApplication.ActivationPolicy = isVisible ? .regular : .accessory
        guard NSApplication.shared.activationPolicy() != targetPolicy else {
            return
        }

        NSApplication.shared.setActivationPolicy(targetPolicy)
    }

    func bringWindowToFront(sceneID: String) {
        guard let window = NSApplication.shared.windows.first(where: { $0.identifier?.rawValue == sceneID }) else {
            return
        }

        if window.isMiniaturized {
            window.deminiaturize(nil)
        }

        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
#endif
