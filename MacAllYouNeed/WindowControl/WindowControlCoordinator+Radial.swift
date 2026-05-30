import AppKit
import ApplicationServices
import Core
import Platform

// Radial-menu integration for the window control coordinator. Extracted to keep
// `WindowControlCoordinator` focused on the keyboard/drag layout pipeline.
extension WindowControlCoordinator {
    /// Handles radial trigger phases from the event tap. Locations arrive in CG
    /// display coordinates (top-left origin); panels need AppKit coordinates.
    func handleRadialPhase(_ phase: WindowControlEventTap.RadialPhase) {
        switch phase {
        case let .open(center):
            let appKitCenter = Self.appKitPoint(fromCG: center)
            radialMenuCoordinator.open(at: center)
            radialMenuViewModel.update(from: radialMenuCoordinator)
            radialPreviewViewModel.update(from: radialMenuCoordinator)
            radialMenuController.show(at: appKitCenter)
            if let screen = Self.screen(containingAppKit: appKitCenter) {
                radialPreviewController.show(on: screen)
            }
        case let .update(cursor):
            radialMenuCoordinator.update(cursorAt: cursor)
            radialMenuViewModel.update(from: radialMenuCoordinator)
            radialPreviewViewModel.update(from: radialMenuCoordinator)
        case .commit:
            radialMenuCoordinator.commit()
            radialMenuViewModel.update(from: radialMenuCoordinator)
            radialMenuController.dismiss()
            radialPreviewController.dismiss()
            radialMenuCoordinator.reset()
        case .cancel:
            radialMenuCoordinator.cancel()
            radialMenuController.dismiss()
            radialPreviewController.dismiss()
            radialMenuCoordinator.reset()
        }
    }

    private static func appKitPoint(fromCG point: CGPoint) -> NSPoint {
        guard let primaryHeight = NSScreen.screens.first?.frame.maxY else {
            return NSPoint(x: point.x, y: point.y)
        }
        // CGEvent locations use a top-left origin on the primary display; flip Y.
        let globalHeight = NSScreen.screens.map(\.frame.maxY).max() ?? primaryHeight
        return NSPoint(x: point.x, y: globalHeight - point.y)
    }

    private static func screen(containingAppKit point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
    }
}

extension WindowControlCoordinator: RadialActionPerforming {
    // `perform(action:)` is already defined on the coordinator and satisfies it.
}

extension WindowControlCoordinator: ProposedFrameResolving {
    func proposedFrame(for action: WindowAction) -> CGRect? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let axWindow = value
        else {
            return nil
        }
        let element = WindowAccessibilityElement(axWindow as! AXUIElement)
        guard element.isSupportedForWindowControl else { return nil }
        return radialFrameMover.proposedFrame(for: action, element: element)
    }
}
