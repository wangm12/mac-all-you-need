import AppKit
import Core
import SwiftUI

@MainActor
final class MainWindowController {
    private weak var controller: AppController?
    private var window: NSWindow?
    private var hostingController: NSHostingController<AnyView>?

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

        PreviewPanel.dismiss()
        ClipboardSystemQuickLookCoordinator.shared.dismiss()
        controller.clipboardDock.hide()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow(controller: AppController) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Mac All You Need"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        if #available(macOS 11.0, *) {
            window.toolbarStyle = .unified
        }
        window.isOpaque = true
        window.backgroundColor = NSColor.windowBackgroundColor
        window.minSize = NSSize(width: 920, height: 640)
        window.center()
        window.isReleasedWhenClosed = false

        let rootView = AnyView(MainWindowRoot(controller: controller).scrollIndicators(.hidden))
        let hostingController = NSHostingController(rootView: rootView)
        self.hostingController = hostingController
        window.contentViewController = hostingController

        return window
    }
}
