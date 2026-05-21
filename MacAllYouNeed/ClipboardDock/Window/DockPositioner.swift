import AppKit
import Foundation

/// Pure-function panel-frame computation. Takes a screen + desired dock height
/// and returns the target NSRect (full-width, bottom-flush). Also locates the
/// screen currently containing the cursor. No side effects.
enum DockPositioner {
    /// Target frame for the dock panel given a screen and desired dock height.
    /// Uses the screen's full frame (not visibleFrame) so the dock sits flush
    /// against the bottom edge of the display — using visibleFrame would
    /// leave a gap above the macOS Dock.
    static func dockFrame(forScreen screen: NSScreen, height: CGFloat) -> NSRect {
        NSRect(
            x: screen.frame.minX,
            y: screen.frame.minY,
            width: screen.frame.width,
            height: height
        )
    }

    /// Returns the screen whose frame currently contains the cursor, or nil
    /// when no screen matches (e.g. in headless test environments).
    static func screenWithCursor() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
    }
}
