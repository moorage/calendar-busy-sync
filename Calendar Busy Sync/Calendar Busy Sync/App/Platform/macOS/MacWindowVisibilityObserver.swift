#if os(macOS)
import AppKit
import SwiftUI

struct MacWindowVisibilityObserver: NSViewRepresentable {
    let sceneID: String
    let onVisibilityChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onVisibilityChange: onVisibilityChange)
    }

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        context.coordinator.sceneID = sceneID
        context.coordinator.onVisibilityChange = onVisibilityChange
        context.coordinator.attach(to: nsView.window)
    }

    final class TrackingView: NSView {
        weak var coordinator: Coordinator?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            coordinator?.attach(to: window)
        }
    }

    final class Coordinator {
        var sceneID = ""
        var onVisibilityChange: (Bool) -> Void
        private weak var window: NSWindow?
        private var observers: [NSObjectProtocol] = []

        init(onVisibilityChange: @escaping (Bool) -> Void) {
            self.onVisibilityChange = onVisibilityChange
        }

        deinit {
            observers.forEach(NotificationCenter.default.removeObserver)
        }

        func attach(to window: NSWindow?) {
            guard self.window !== window else { return }

            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            self.window = window

            guard let window else {
                onVisibilityChange(false)
                return
            }

            window.identifier = NSUserInterfaceItemIdentifier(sceneID)
            onVisibilityChange(window.isVisible)

            let center = NotificationCenter.default
            observers.append(
                center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
                    self?.onVisibilityChange(true)
                }
            )
            observers.append(
                center.addObserver(forName: NSWindow.didDeminiaturizeNotification, object: window, queue: .main) { [weak self] _ in
                    self?.onVisibilityChange(true)
                }
            )
            observers.append(
                center.addObserver(forName: NSWindow.didMiniaturizeNotification, object: window, queue: .main) { [weak self] _ in
                    self?.onVisibilityChange(false)
                }
            )
            observers.append(
                center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                    self?.onVisibilityChange(false)
                }
            )
        }
    }
}
#endif
