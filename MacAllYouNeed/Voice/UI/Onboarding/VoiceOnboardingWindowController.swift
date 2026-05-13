import AppKit
import SwiftUI

@MainActor
final class VoiceOnboardingWindowController {
    private weak var controller: AppController?
    private var window: NSWindow?

    init(controller: AppController) {
        self.controller = controller
    }

    func show() {
        guard let controller else { return }
        if window == nil {
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 600),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            win.title = "Voice Setup"
            win.center()
            win.isReleasedWhenClosed = false
            window = win
        }
        window?.contentView = NSHostingView(rootView: VoiceOnboardingWizardView(controller: controller))
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.close()
    }
}
