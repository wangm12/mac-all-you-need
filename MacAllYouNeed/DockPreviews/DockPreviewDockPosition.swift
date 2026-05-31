import AppKit
import Foundation

enum DockPreviewDockPosition {
    typealias DockEdge = DockPreviewPanelGeometry.DockEdge

    static func currentEdge() -> DockEdge {
        guard let screen = NSScreen.main else { return .bottom }
        return currentEdge(for: screen)
    }

    /// Whether the cursor is in the dock band (used to dismiss stale previews when AX selection lags).
    static func isMouseInDockRegion(padding: CGFloat = 4) -> Bool {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else {
            return false
        }
        let edge = currentEdge(for: screen)
        let visible = screen.visibleFrame
        switch edge {
        case .bottom:
            return mouse.y <= visible.minY + padding
        case .left:
            return mouse.x <= visible.minX + padding
        case .right:
            return mouse.x >= visible.maxX - padding
        }
    }

    static func currentEdge(for screen: NSScreen) -> DockEdge {
        let frame = screen.visibleFrame
        let dockFrame = screen.frame
        let bottomInset = dockFrame.height - frame.maxY
        let leftInset = frame.minX - dockFrame.minX
        let rightInset = dockFrame.maxX - frame.maxX
        if leftInset > 40 { return .left }
        if rightInset > 40 { return .right }
        if bottomInset > 20 { return .bottom }
        return .bottom
    }

    static func isDockVisible() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return true }
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[CFString: Any]] else {
            return true
        }
        for info in list {
            guard (info[kCGWindowOwnerPID] as? Int32) == app.processIdentifier,
                  let layer = info[kCGWindowLayer] as? Int,
                  layer == 0,
                  let bounds = info[kCGWindowBounds] as? [String: CGFloat],
                  let width = bounds["Width"],
                  let height = bounds["Height"],
                  let screen = NSScreen.main
            else { continue }
            if width >= screen.frame.width * 0.95, height >= screen.frame.height * 0.95 {
                return false
            }
        }
        return true
    }
}
