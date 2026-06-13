import AppKit
import ApplicationServices
import Foundation
import Platform

/// Computes which screen and origin to use for the hotkey history panel.
enum FolderHistoryPanelPlacement {
    /// Distance below the top of the screen's visible frame (menu bar / notch aware).
    static let topInsetFromVisibleTop: CGFloat = 72

    /// Screen for the panel: Finder's focused window when Finder is frontmost, else cursor screen.
    static func preferredScreen(
        frontmostBundleID: String? = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
        screens: [NSScreen] = NSScreen.screens,
        mouseLocation: NSPoint = NSEvent.mouseLocation,
        finderWindowFrameProvider: () -> CGRect? = { frontmostFinderWindowFrame() }
    ) -> NSScreen? {
        if frontmostBundleID == "com.apple.finder",
           let frame = finderWindowFrameProvider(),
           let screen = screen(containing: frame, screens: screens) {
            return screen
        }
        return screen(containingPoint: mouseLocation, screens: screens)
            ?? NSScreen.main
            ?? screens.first
    }

    /// Top-center of the visible frame, clamped so the panel stays on-screen.
    static func origin(panelSize: NSSize, visibleFrame: CGRect) -> NSPoint {
        let x = visibleFrame.midX - panelSize.width / 2
        var y = visibleFrame.maxY - panelSize.height - topInsetFromVisibleTop
        y = max(visibleFrame.minY, min(y, visibleFrame.maxY - panelSize.height))
        return NSPoint(x: x, y: y)
    }

    static func origin(panelSize: NSSize, on screen: NSScreen) -> NSPoint {
        origin(panelSize: panelSize, visibleFrame: screen.visibleFrame)
    }

    // MARK: - Screen lookup

    static func screen(containing rect: CGRect, screens: [NSScreen]) -> NSScreen? {
        let appKitCenter = WindowScreenDetector.appKitPoint(
            fromCG: CGPoint(x: rect.midX, y: rect.midY)
        )
        return screen(
            containingPoint: NSPoint(x: appKitCenter.x, y: appKitCenter.y),
            screens: screens
        )
    }

    static func screen(containingPoint point: NSPoint, screens: [NSScreen]) -> NSScreen? {
        screens.first { NSMouseInRect(point, $0.frame, false) }
    }

    // MARK: - Finder AX

    static func frontmostFinderWindowFrame() -> CGRect? {
        guard AXIsProcessTrusted() else { return nil }
        guard let pid = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == "com.apple.finder" })?
            .processIdentifier
        else { return nil }
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let window = value,
              CFGetTypeID(window) == AXUIElementGetTypeID()
        else { return nil }
        let axWindow = window as! AXUIElement
        return axFrame(of: axWindow)
    }

    private static func axFrame(of window: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionRef = positionValue, let sizeRef = sizeValue
        else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionRef as! AXValue, .cgPoint, &position), // swiftlint:disable:this force_cast
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size) // swiftlint:disable:this force_cast
        else { return nil }
        return CGRect(origin: position, size: size)
    }
}
