import AppKit
import SwiftUI

/// Highlights the selected switcher window at its on-screen frame (Tangrid-style).
@MainActor
final class DockSwitcherOriginalPositionOverlay {
    static let shared = DockSwitcherOriginalPositionOverlay()

    private var panel: NSPanel?
    private var hostingView: NSHostingView<DockSwitcherOriginalPositionBorderView>?

    private init() {}

    func update(frame: CGRect?, reduceMotion: Bool) {
        guard let frame, frame.width > 1, frame.height > 1 else {
            dismiss()
            return
        }
        guard let primaryScreen = NSScreen.main ?? NSScreen.screens.first else {
            dismiss()
            return
        }
        let panel = ensurePanel()
        let appKitFrame = CGRect(
            x: frame.origin.x,
            y: primaryScreen.frame.height - frame.origin.y - frame.height,
            width: frame.width,
            height: frame.height
        )
        if reduceMotion {
            panel.setFrame(appKitFrame, display: true)
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = MAYNMotionBridge.effectiveDuration(.press)
                panel.animator().setFrame(appKitFrame, display: true)
            }
        }
        panel.orderFrontRegardless()
    }

    func dismiss() {
        panel?.orderOut(nil)
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = true
        let root = DockSwitcherOriginalPositionBorderView()
        let hosting = NSHostingView(rootView: root)
        panel.contentView = hosting
        hostingView = hosting
        self.panel = panel
        return panel
    }
}

private struct DockSwitcherOriginalPositionBorderView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .strokeBorder(Color.accentColor, lineWidth: 3)
            .background(Color.clear)
    }
}
