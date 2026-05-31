import AppKit
import SwiftUI

/// Borderless, non-activating NSPanel for the Dock preview card strip.
@MainActor
final class DockPreviewPanel {
    private var panel: NSPanel?

    func show(
        appIcon: NSImage?,
        appName: String,
        entries: [DockPreviewWindowEntry],
        mode: DockPreviewPermissionGate.Mode,
        at cursorLocation: NSPoint,
        onSelect: @escaping (DockPreviewWindowEntry) -> Void
    ) {
        dismiss()

        let cardCount = max(1, min(entries.count, 6))
        let cardW = 240 + DockPreviewLayout.cardPadding * 2
        let panelWidth = CGFloat(cardCount) * (cardW + DockPreviewLayout.itemSpacing)
            - DockPreviewLayout.itemSpacing
            + DockPreviewLayout.outerPadding * 2
        let panelHeight: CGFloat = 240  // header + thumbnail + label + padding

        let screen = NSScreen.screens.first { $0.frame.contains(cursorLocation) } ?? NSScreen.main
        let screenFrame = screen?.visibleFrame ?? .zero
        let dockGap: CGFloat = 20

        var x = cursorLocation.x - panelWidth / 2
        var y = cursorLocation.y + dockGap

        x = max(screenFrame.minX + 8, min(x, screenFrame.maxX - panelWidth - 8))
        y = min(y, screenFrame.maxY - panelHeight - 8)

        let view = DockPreviewPanelView(
            appIcon: appIcon,
            appName: appName,
            entries: entries,
            mode: mode,
            onSelect: onSelect
        )
        let p = NSPanel(
            contentRect: NSRect(x: x, y: y, width: panelWidth, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.contentView = NSHostingView(rootView: view)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.level = .floating
        p.hasShadow = false  // shadow rendered in SwiftUI
        p.hidesOnDeactivate = false
        p.orderFrontRegardless()
        panel = p
    }

    func dismiss() {
        panel?.close()
        panel = nil
    }
}
