import AppKit
import FeatureCore
import SwiftUI

@MainActor
final class OnboardingWindowController {
    private weak var controller: AppController?
    private var window: NSWindow?
    private var standaloneWindow: NSWindow?

    init(controller: AppController) {
        self.controller = controller
    }

    func show() {
        guard let controller, controller.onboarding != .completed else { return }
        if window == nil {
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 920, height: 640),
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

    func showStandaloneWizard(for featureID: FeatureID) {
        guard let controller else { return }
        standaloneWindow?.close()
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 580),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let displayName = controller.runtime.registry.descriptor(for: featureID)?.displayName ?? "Feature"
        win.title = "\(displayName) Setup"
        win.center()
        win.isReleasedWhenClosed = false
        win.contentView = NSHostingView(
            rootView: StandaloneFeatureOnboardingView(controller: controller, featureID: featureID) { [weak self] in
                self?.standaloneWindow?.close()
                self?.standaloneWindow = nil
            }
        )
        standaloneWindow = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeStandaloneWizard() {
        standaloneWindow?.close()
        standaloneWindow = nil
    }
}
