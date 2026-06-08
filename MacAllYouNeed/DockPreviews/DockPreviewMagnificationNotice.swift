import AppKit
import Core
import Foundation

/// One-time prompt to permanently disable macOS Dock magnification for aligned previews.
@MainActor
enum DockPreviewMagnificationNotice {
    private static let seenKey = "dockPreview.hasSeenMagnificationHint"

    static func presentIfNeeded() {
        let defaults = AppGroupSettings.defaults
        guard !defaults.bool(forKey: seenKey) else { return }
        guard DockPreviewDockMagnification.isEnabled() else { return }

        let alert = NSAlert()
        alert.messageText = "Turn off Dock magnification for previews"
        alert.informativeText = """
        Dock magnification animates icon size while you hover, which makes preview panels drift.

        Mac All You Need will turn magnification off in your macOS Dock settings so previews stay aligned. You can re-enable it anytime in Desktop & Dock.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Turn Off Magnification")
        alert.addButton(withTitle: "Open Desktop & Dock")
        alert.addButton(withTitle: "Keep Magnification")

        let response = alert.runModal()
        defaults.set(true, forKey: seenKey)

        switch response {
        case .alertFirstButtonReturn:
            DockPreviewDockMagnification.setEnabled(false)
        case .alertSecondButtonReturn:
            DockPreviewDockMagnification.openSystemSettings()
        default:
            break
        }
    }
}
