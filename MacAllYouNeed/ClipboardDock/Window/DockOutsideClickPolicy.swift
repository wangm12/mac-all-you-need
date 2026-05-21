import AppKit
import Foundation

/// Pure-function policy that decides whether a mouse click outside the dock
/// panel should dismiss the dock. Kept side-effect free so it can be unit
/// tested without an NSWindow.
enum DockOutsideClickPolicy {
    static func shouldHide(
        panelFrame: NSRect,
        clickLocationOnScreen: NSPoint,
        ignoreOutsideClicksUntil: Date,
        now: Date
    ) -> Bool {
        guard now >= ignoreOutsideClicksUntil else { return false }
        return !panelFrame.contains(clickLocationOnScreen)
    }

    static func screenLocation(for event: NSEvent) -> NSPoint {
        guard let eventWindow = event.window else {
            return NSEvent.mouseLocation
        }
        return eventWindow.convertPoint(toScreen: event.locationInWindow)
    }
}
