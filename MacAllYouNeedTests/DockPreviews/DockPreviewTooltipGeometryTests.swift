import XCTest
@testable import MacAllYouNeed

final class DockPreviewTooltipGeometryTests: XCTestCase {
    func testOverlayRectSitsAboveIcon() {
        let icon = CGRect(x: 100, y: 200, width: 64, height: 64)
        let overlay = DockPreviewTooltipGeometry.overlayRect(iconRect: icon)
        XCTAssertEqual(overlay.maxY, icon.minY, accuracy: 0.5)
        XCTAssertGreaterThan(overlay.width, icon.width)
    }

    /// Bottom-docked icon AX rect must map to a strip just above the dock, not the top of the screen.
    func testTooltipOverlayMapsBottomDockIconNearScreenBottom() {
        guard let screen = NSScreen.main else { return }
        let axIcon = CGRect(x: screen.frame.midX - 32, y: screen.frame.height - 80, width: 64, height: 64)
        let flipped = DockPreviewDockCoordinates.flippedIconRect(axRect: axIcon, screen: screen)
        let overlay = DockPreviewTooltipGeometry.overlayRect(iconRect: flipped)

        XCTAssertLessThan(overlay.midY, screen.frame.midY, "Tooltip cover should sit in the lower half of the screen")
        XCTAssertGreaterThan(overlay.maxY, screen.frame.minY + 40, "Tooltip cover should stay above the dock")
    }
}
