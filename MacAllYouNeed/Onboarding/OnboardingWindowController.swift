import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController {
    private weak var controller: AppController?
    private var window: NSWindow?

    init(controller: AppController) {
        self.controller = controller
    }

    func show() {
        guard let controller, controller.onboarding != .completed else { return }
        if window == nil {
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 540, height: 420),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            win.title = "Mac All You Need Setup"
            win.center()
            win.isReleasedWhenClosed = false
            win.contentView = NSHostingView(rootView: OnboardingWizardView(controller: controller))
            self.window = win
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
