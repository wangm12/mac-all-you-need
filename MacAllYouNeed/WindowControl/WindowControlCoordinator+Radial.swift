import AppKit
import ApplicationServices
import Core
import Platform

// Radial-menu integration for the window control coordinator. Extracted to keep
// `WindowControlCoordinator` focused on the keyboard/drag layout pipeline.
extension WindowControlCoordinator {
    /// Opens the radial menu at the current cursor location (invoked from a hotkey).
    func openRadialMenu() {
        guard settings.radialMenuEnabled else { return }
        let cursor = NSEvent.mouseLocation
        // Convert AppKit point (bottom-left origin) to CG display coordinates (top-left origin).
        let cgCursor: CGPoint
        if let globalHeight = NSScreen.screens.map(\.frame.maxY).max() {
            cgCursor = CGPoint(x: cursor.x, y: globalHeight - cursor.y)
        } else {
            cgCursor = CGPoint(x: cursor.x, y: cursor.y)
        }
        handleRadialPhase(.open(center: cgCursor))
        (tap as? WindowControlEventTap)?.radialActive = true
    }

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
            installRadialEscMonitor()
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
            removeRadialEscMonitor()
        case .cancel:
            radialMenuCoordinator.cancel()
            radialMenuController.dismiss()
            radialPreviewController.dismiss()
            radialMenuCoordinator.reset()
            removeRadialEscMonitor()
        }
    }

    // MARK: Esc monitor

    private static let escKeyCode: UInt16 = 53

    func installRadialEscMonitor() {
        removeRadialEscMonitor()
        // Use both global (other apps focused) and local (MAYN focused) monitors
        // so Esc always cancels the radial menu regardless of which app has focus.
        let handler: (NSEvent) -> NSEvent? = { [weak self] event in
            guard event.keyCode == Self.escKeyCode else { return event }
            Task { @MainActor [weak self] in
                (self?.tap as? WindowControlEventTap)?.radialActive = false
                self?.handleRadialPhase(.cancel)
            }
            return nil // consume the Esc
        }
        let globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            _ = handler(event)
        }
        let localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: handler)
        radialEscMonitor = [globalMonitor as Any, localMonitor as Any].compactMap { $0 }
    }

    func removeRadialEscMonitor() {
        if let monitors = radialEscMonitor as? [Any] {
            monitors.forEach { NSEvent.removeMonitor($0) }
        } else if let monitor = radialEscMonitor {
            NSEvent.removeMonitor(monitor)
        }
        radialEscMonitor = nil
    }

    private static func appKitPoint(fromCG point: CGPoint) -> NSPoint {
        guard let primaryHeight = NSScreen.screens.first?.frame.maxY else {
            return NSPoint(x: point.x, y: point.y)
        }
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
