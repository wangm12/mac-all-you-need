import AppKit
import SwiftUI

/// Borderless, non-activating NSPanel for the Dock preview card strip.
@MainActor
final class DockPreviewPanel {
    private var panel: NSPanel?

    func show(
        entries: [DockPreviewWindowEntry],
        mode: DockPreviewPermissionGate.Mode,
        at origin: CGPoint,
        onSelect: @escaping (DockPreviewWindowEntry) -> Void
    ) {
        dismiss()
        let view = DockPreviewPanelView(entries: entries, mode: mode, onSelect: onSelect)
        let hostSize = CGSize(width: min(CGFloat(entries.count) * 184 + 24, 800), height: 152)
        let p = NSPanel(
            contentRect: NSRect(origin: origin, size: hostSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.contentView = NSHostingView(rootView: view)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.level = .floating
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.orderFrontRegardless()
        panel = p
    }

    func dismiss() {
        panel?.close()
        panel = nil
    }
}
