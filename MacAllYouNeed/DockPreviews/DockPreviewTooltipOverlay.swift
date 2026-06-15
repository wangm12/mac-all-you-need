import AppKit

/// Opaque strip that hides the native Dock tooltip while a hover preview is open.
@MainActor
final class DockPreviewTooltipOverlay {
    static let shared = DockPreviewTooltipOverlay()

    private var panel: NSPanel?

    private init() {}

    /// `iconRect` is in AX screen space (top-left origin), matching `placementAnchorRect` from the hover observer.
    func show(iconRect axIconRect: CGRect, screen: NSScreen) {
        guard axIconRect != .zero else {
            dismiss()
            return
        }
        let flipped = DockPreviewDockCoordinates.flippedIconRect(axRect: axIconRect, screen: screen)
        let overlay = DockPreviewTooltipGeometry.overlayRect(iconRect: flipped)
        let panel = ensurePanel()
        panel.setFrame(overlay, display: true)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = true
        panel.backgroundColor = NSColor.windowBackgroundColor
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = true
        self.panel = panel
        return panel
    }
}
