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
            let menuCenterCG = radialMenuCenterCG(cursorCG: center)
            let appKitCenter = Self.appKitPoint(fromCG: menuCenterCG)
            let screenBounds = WindowScreenDetector.current().screen(containing: menuCenterCG)?.frame
            radialMenuCoordinator.open(at: menuCenterCG, screenBounds: screenBounds)
            refreshRadialOverlays(appKitMenuCenter: appKitCenter)
            installRadialEscMonitor()
        case let .update(cursor):
            if settings.radialCursorSelectionEnabled {
                radialMenuCoordinator.update(cursorAt: cursor)
            } else if let center = radialMenuCoordinatorOpenCenter(),
                      RadialSelectionMath.closeZoneContains(cursor: cursor, menuCenter: center) {
                radialMenuCoordinator.selectClose()
            } else {
                radialMenuCoordinator.clearSelection()
            }
            refreshRadialOverlays(appKitMenuCenter: radialMenuAppKitCenter())
        case let .selectAction(action):
            radialMenuCoordinator.select(action: action)
            refreshRadialOverlays(appKitMenuCenter: radialMenuAppKitCenter())
        case .commit:
            switch radialMenuCoordinator.selection {
            case .cancel, .none:
                radialMenuCoordinator.cancel()
            default:
                radialMenuCoordinator.commit()
            }
            dismissRadialUI()
            radialMenuCoordinator.reset()
            (tap as? WindowControlEventTap)?.radialActive = false
        case .cancel:
            radialMenuCoordinator.cancel()
            dismissRadialUI()
            radialMenuCoordinator.reset()
            removeRadialEscMonitor()
        }
    }

    private func radialMenuCenterCG(cursorCG: CGPoint) -> CGPoint {
        guard settings.radialLockToCenter else { return cursorCG }
        let appKitCursor = Self.appKitPoint(fromCG: cursorCG)
        guard let screen = Self.screen(containingAppKit: appKitCursor) else { return cursorCG }
        let appKitCenter = NSPoint(x: screen.frame.midX, y: screen.frame.midY)
        return Self.cgPoint(fromAppKit: appKitCenter)
    }

    private func radialMenuAppKitCenter() -> NSPoint {
        guard let center = radialMenuCoordinatorOpenCenter() else {
            return Self.appKitPoint(fromCG: .zero)
        }
        return Self.appKitPoint(fromCG: center)
    }

    private func radialMenuCoordinatorOpenCenter() -> CGPoint? {
        guard case let .open(center) = radialMenuCoordinator.state else { return nil }
        return center
    }

    private func refreshRadialOverlays(appKitMenuCenter: NSPoint) {
        radialMenuViewModel.update(from: radialMenuCoordinator, hasTargetWindow: radialTargetWindow() != nil)
        radialMenuController.show(at: appKitMenuCenter)
        refreshRadialLayoutPreview(appKitAnchor: appKitMenuCenter)
        refreshRadialTargetHighlight()
    }

    /// Gray proposed-frame overlay (snap-style) for the armed ring/center action.
    private func refreshRadialLayoutPreview(appKitAnchor: NSPoint) {
        radialPreviewViewModel.update(from: radialMenuCoordinator, host: self)
        guard radialMenuCoordinator.proposedFrame != nil else {
            radialPreviewController.dismiss()
            return
        }
        let screenPoint: NSPoint
        if let frame = radialPreviewViewModel.proposedFrame {
            screenPoint = NSPoint(x: frame.midX, y: frame.midY)
        } else {
            screenPoint = appKitAnchor
        }
        guard let screen = Self.screen(containingAppKit: screenPoint) else {
            radialPreviewController.dismiss()
            return
        }
        radialPreviewController.show(on: screen)
    }

    private func dismissRadialUI() {
        radialMenuController.dismiss()
        radialPreviewController.dismiss()
        radialTargetHighlightController.dismiss()
        removeRadialEscMonitor()
    }

    private func refreshRadialTargetHighlight() {
        guard settings.radialTargetHighlightEnabled,
              let frame = radialTargetWindowAppKitFrame()
        else {
            radialTargetHighlightController.dismiss()
            return
        }
        radialTargetHighlightController.show(
            frame: frame,
            color: settings.radialTargetHighlightColor.swiftUIColor
        )
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

    static func appKitPoint(fromCG point: CGPoint) -> NSPoint {
        guard let primaryHeight = NSScreen.screens.first?.frame.maxY else {
            return NSPoint(x: point.x, y: point.y)
        }
        let globalHeight = NSScreen.screens.map(\.frame.maxY).max() ?? primaryHeight
        return NSPoint(x: point.x, y: globalHeight - point.y)
    }

    static func cgPoint(fromAppKit point: NSPoint) -> CGPoint {
        guard let globalHeight = NSScreen.screens.map(\.frame.maxY).max() else {
            return CGPoint(x: point.x, y: point.y)
        }
        return CGPoint(x: point.x, y: globalHeight - point.y)
    }

    func appKitOverlayFrame(for cgFrame: CGRect) -> CGRect? {
        guard let screen = WindowScreenDetector.current().screen(containing: cgFrame) else {
            return nil
        }
        guard let nsScreen = NSScreen.screens.first(where: { nsScreen in
            (nsScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
                .uint32Value == screen.id
        }) else {
            return nil
        }
        return WindowScreenDetector.convertCGDisplayRectToAppKitCoordinates(
            cgRect: cgFrame,
            appKitScreenFrame: nsScreen.frame,
            cgDisplayBounds: CGDisplayBounds(screen.id)
        )
    }

    private static func screen(containingAppKit point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
    }

    /// Focused window for radial preview, highlight, and commit (single source of truth).
    func radialTargetWindow() -> WindowAccessibilityElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let bundleID = app.bundleIdentifier ?? ""
        if settings.ignoredBundleIDs.contains(bundleID) { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let axWindow = value
        else {
            return nil
        }
        let element = WindowAccessibilityElement(axWindow as! AXUIElement)
        guard element.isSupportedForWindowControl else { return nil }
        return element
    }

    func radialTargetWindowAppKitFrame() -> CGRect? {
        guard let element = radialTargetWindow() else { return nil }
        let cgFrame = element.frame
        guard !cgFrame.isNull, !cgFrame.isEmpty else { return nil }
        return appKitOverlayFrame(for: cgFrame)
    }
}

extension WindowControlCoordinator: RadialActionPerforming {
    // `perform(action:)` is already defined on the coordinator and satisfies it.
}

extension WindowControlCoordinator: ProposedFrameResolving {
    func proposedFrame(for action: WindowAction) -> CGRect? {
        guard let element = radialTargetWindow() else { return nil }
        return radialFrameMover.proposedFrame(for: action, element: element)
    }
}
