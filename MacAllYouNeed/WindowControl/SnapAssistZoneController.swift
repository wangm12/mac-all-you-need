import AppKit
import Core
import Platform

/// Tangrid-style candidate zones shown while modifier-dragging a window.
@MainActor
enum SnapAssistZoneController {
    private static let hitTester = SnapAssistZoneHitTester(insetFraction: 0.25)

    static func zone(at cgLocation: CGPoint) -> SnapAssistZone? {
        let detector = WindowScreenDetector.current()
        guard let screen = detector.screen(containing: cgLocation) else { return nil }
        return hitTester.zone(at: cgLocation, in: screen.visibleFrame)
    }

    static func previewFrame(for zone: SnapAssistZone, at cgLocation: CGPoint) -> CGRect? {
        let detector = WindowScreenDetector.current()
        guard let screen = detector.screen(containing: cgLocation) else { return nil }
        let cgFrame = hitTester.previewFrame(for: zone, in: screen.visibleFrame)
        return appKitOverlayFrame(for: cgFrame, screenID: screen.id)
    }

    private static func appKitOverlayFrame(for cgFrame: CGRect, screenID: UInt32) -> CGRect {
        guard let screen = NSScreen.screens.first(where: { nsScreen in
            (nsScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == screenID
        }) else { return cgFrame }
        return WindowScreenDetector.convertCGDisplayRectToAppKitCoordinates(
            cgRect: cgFrame,
            appKitScreenFrame: screen.frame,
            cgDisplayBounds: CGDisplayBounds(screenID)
        )
    }

    static func windowAction(for zone: SnapAssistZone) -> WindowAction {
        zone.windowAction
    }
}
