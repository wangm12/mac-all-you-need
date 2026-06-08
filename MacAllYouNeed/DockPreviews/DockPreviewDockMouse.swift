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

    /// True when the incoming hover targets a different running app than the open preview.
    static func isCrossAppDockSwitch(
        displayedPID: pid_t?,
        targetPID: pid_t,
        displayedBundleID: String?,
        targetBundleID: String?
    ) -> Bool {
        if let displayedPID, displayedPID != 0, targetPID != 0, displayedPID != targetPID {
            return true
        }
        if let displayedBundleID, let targetBundleID,
           !displayedBundleID.isEmpty, !targetBundleID.isEmpty,
           displayedBundleID != targetBundleID {
            return true
        }
        return false
    }

    /// Ignore spurious AX dock token churn while the cursor stays on the open preview for the same app.
    static func shouldIgnoreDockHoverChange(
        panelVisible: Bool,
        mouseIsWithinPreview: Bool,
        panelFrame: CGRect?,
        folderFrame: CGRect?,
        currentToken: UInt?,
        newToken: UInt,
        currentPID: pid_t?,
        newPID: pid_t,
        currentBundleID: String?,
        newBundleID: String?
    ) -> Bool {
        guard panelVisible, let currentToken, currentToken != newToken else { return false }
        if isCrossAppDockSwitch(
            displayedPID: currentPID,
            targetPID: newPID,
            displayedBundleID: currentBundleID,
            targetBundleID: newBundleID
        ) {
            return false
        }
        return mouseIsWithinPreview
    }

    /// AX can recycle dock item elements for the same running app; absorb token churn on the dock band.
    static func shouldAbsorbSameAppDockTokenChurn(
        panelVisible: Bool,
        mouseIsWithinPreview: Bool,
        pointerInDockRegion: Bool,
        currentPID: pid_t?,
        newPID: pid_t,
        currentToken: UInt?,
        newToken: UInt
    ) -> Bool {
        guard panelVisible, pointerInDockRegion, !mouseIsWithinPreview else { return false }
        guard let currentPID, let currentToken, currentPID != 0, newPID != 0 else { return false }
        return currentPID == newPID && currentToken != newToken
    }

    /// Whether an instant dock switch may present; target must match live AX hover unless `crossAppSwitch`.
    static func shouldAllowInstantDockSwitch(
        mouseIsWithinPreview: Bool,
        onPreviewSurface: Bool,
        pointerInDockRegion: Bool,
        targetBundleID: String?,
        targetPID: pid_t,
        hoveredBundleID: String?,
        hoveredPID: pid_t,
        displayedPID: pid_t?,
        crossAppSwitch: Bool
    ) -> Bool {
        if crossAppSwitch { return true }
        let targetMatchesHover: Bool
        if targetPID != 0, hoveredPID == targetPID {
            targetMatchesHover = true
        } else if let targetBundleID, let hoveredBundleID,
                  !targetBundleID.isEmpty, !hoveredBundleID.isEmpty {
            targetMatchesHover = targetBundleID == hoveredBundleID
        } else {
            targetMatchesHover = false
        }
        guard targetMatchesHover else { return false }
        if pointerInDockRegion { return true }
        return !mouseIsWithinPreview && !onPreviewSurface
    }
}
