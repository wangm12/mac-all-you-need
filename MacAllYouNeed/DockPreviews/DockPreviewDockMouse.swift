import AppKit
import Foundation

@MainActor
enum DockPreviewDockMouse {
    /// Inset panel frame used for hover/dismiss hit testing (DockDoor `HoverContainerPadding.container`).
    static func previewWindowHitFrame(_ panelFrame: CGRect) -> CGRect {
        panelFrame.insetBy(
            dx: DockPreviewHoverPadding.container,
            dy: DockPreviewHoverPadding.container
        )
    }

    /// Cursor is inside the preview panel bounds (DockDoor `windowFrame.contains`).
    static func isPointerInsidePreviewWindow(panelFrame: CGRect?) -> Bool {
        guard let panelFrame, panelFrame.width > 1, panelFrame.height > 1 else { return false }
        return previewWindowHitFrame(panelFrame).contains(NSEvent.mouseLocation)
    }

    /// Cursor is on the preview panel or folder panel.
    static func isPointerOnPreviewSurface(
        panelFrame: CGRect?,
        folderFrame: CGRect?
    ) -> Bool {
        if isPointerInsidePreviewWindow(panelFrame: panelFrame) { return true }
        if let folderFrame, folderFrame.width > 1, folderFrame.height > 1 {
            return previewWindowHitFrame(folderFrame).contains(NSEvent.mouseLocation)
        }
        return false
    }

    /// Whether the preview should stay visible — only while the cursor is inside the preview window.
    static func shouldKeepPreviewOpen(
        mouseIsWithinPreview: Bool,
        panelFrame: CGRect?,
        folderFrame: CGRect?
    ) -> Bool {
        if mouseIsWithinPreview { return true }
        return isPointerOnPreviewSurface(panelFrame: panelFrame, folderFrame: folderFrame)
    }
}
