import AppKit
import Core
import SwiftUI

@MainActor
final class MainWindowController {
    private weak var controller: AppController?
    private var window: NSWindow?

    init(controller: AppController) {
        self.controller = controller
    }

    func show(destination: MainAppDestination? = nil) {
        if let destination {
            MainAppDestination.persist(destination, to: AppGroupSettings.defaults)
        }
        guard let controller else { return }

        let window = window ?? makeWindow(controller: controller)
        self.window = window
        if window.contentView == nil {
            window.contentView = NSHostingView(rootView: MainWindowRoot(controller: controller))
        }

        PreviewPanel.dismiss()
        controller.clipboardDock.hide()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow(controller: AppController) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Mac All You Need"
        window.minSize = NSSize(width: 820, height: 560)
        window.center()
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: MainWindowRoot(controller: controller))
        return window
    }
}
