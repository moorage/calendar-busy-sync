#if os(macOS)
import AppKit
import SwiftUI

struct MacInitialWindowSuppressor: NSViewRepresentable {
    let shouldSuppress: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        context.coordinator.shouldSuppress = shouldSuppress
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
        var shouldSuppress = false
        private weak var window: NSWindow?
        private var hasSuppressed = false

        func attach(to window: NSWindow?) {
            self.window = window
            guard shouldSuppress, !hasSuppressed, let window else { return }

            hasSuppressed = true
            DispatchQueue.main.async {
                window.orderOut(nil)
            }
        }
    }
}
#endif
