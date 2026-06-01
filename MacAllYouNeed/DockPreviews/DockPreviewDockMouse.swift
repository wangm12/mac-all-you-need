import AppKit
import Foundation

enum DockPreviewDockMouse {
    /// Whether the cursor is over a dock icon rect reported by AX (global screen coords).
    static func isOverDockIcon(axRect: CGRect, padding: CGFloat = 12) -> Bool {
        guard axRect.width > 1, axRect.height > 1 else { return false }
        let screen = DockPreviewDockCoordinates.screen(containingAXPoint: axRect.origin)
        let hit = DockPreviewDockCoordinates.cocoaIconRect(axRect: axRect, screen: screen)
            .insetBy(dx: -padding, dy: -padding)
        return hit.contains(NSEvent.mouseLocation)
    }

    /// Narrow vertical bridge between dock icon and preview panel (Cocoa coords).
    static func isInDockToPanelBridge(
        mouse: CGPoint = NSEvent.mouseLocation,
        axIconRect: CGRect,
        panelFrame: CGRect,
        bridgeWidth: CGFloat = 32
    ) -> Bool {
        guard axIconRect.width > 0, panelFrame.width > 0 else { return false }
        let screen = DockPreviewDockCoordinates.screen(containingAXPoint: axIconRect.origin)
        let icon = DockPreviewDockCoordinates.cocoaIconRect(axRect: axIconRect, screen: screen)
        guard icon.maxY < panelFrame.minY else { return false }
        let width = min(max(icon.width + 8, bridgeWidth), panelFrame.width + 24)
        let bridge = CGRect(
            x: icon.midX - width / 2,
            y: icon.maxY,
            width: width,
            height: panelFrame.minY - icon.maxY
        )
        return bridge.contains(mouse)
    }

    /// Cursor is on the preview panel, folder panel, or the icon→panel bridge (DockDoor window frame check).
    static func isPointerOnPreviewSurface(
        panelFrame: CGRect?,
        folderFrame: CGRect?,
        axIconRect: CGRect
    ) -> Bool {
        let mouse = NSEvent.mouseLocation

        if let panelFrame, panelFrame.width > 1, panelFrame.height > 1 {
            let padded = panelFrame.insetBy(dx: -4, dy: -4)
            if padded.contains(mouse) { return true }
            if isInDockToPanelBridge(mouse: mouse, axIconRect: axIconRect, panelFrame: panelFrame) {
                return true
            }
        }
        if let folderFrame, folderFrame.width > 1, folderFrame.height > 1 {
            if folderFrame.insetBy(dx: -4, dy: -4).contains(mouse) { return true }
        }
        return false
    }

    /// Whether the preview should stay visible (DockDoor: panel contains mouse OR same dock item still selected under cursor).
    static func shouldKeepPreviewOpen(
        axIconRect: CGRect,
        activeDockItemToken: UInt?,
        hoveredDockItemToken: UInt?,
        panelFrame: CGRect?,
        folderFrame: CGRect?
    ) -> Bool {
        if isPointerOnPreviewSurface(
            panelFrame: panelFrame,
            folderFrame: folderFrame,
            axIconRect: axIconRect
        ) {
            return true
        }
        // AX selection can lag while moving between dock icons; keep the panel up if the cursor is still on the dock strip.
        if panelFrame != nil,
           DockPreviewDockPosition.isMouseInDockRegion(padding: 28),
           activeDockItemToken != nil {
            if activeDockItemToken == hoveredDockItemToken {
                return isOverDockIcon(axRect: axIconRect, padding: 12)
            }
            return true
        }
        guard let activeDockItemToken, activeDockItemToken == hoveredDockItemToken else {
            return false
        }
        return isOverDockIcon(axRect: axIconRect, padding: 12)
    }
}
