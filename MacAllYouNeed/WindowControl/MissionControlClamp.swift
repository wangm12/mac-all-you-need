import AppKit
import CoreGraphics
import Platform

/// Prevents modifier-drag from triggering Mission Control. When the cursor
/// crosses into the top edge of any screen mid-drag, we rewrite the event
/// location to one pixel below that edge so the OS's effective cursor
/// position never reaches the hot-corner activation threshold. The window
/// keeps moving — Mission Control doesn't fire.
enum MissionControlClamp {
    static func apply(_ event: CGEvent) {
        guard let screen = WindowScreenDetector.current().screen(containing: event.location) else {
            return
        }
        let cgFrame = CGDisplayBounds(screen.id)
        if event.location.y <= cgFrame.minY {
            event.location = CGPoint(x: event.location.x, y: cgFrame.minY + 1)
        }
    }
}
