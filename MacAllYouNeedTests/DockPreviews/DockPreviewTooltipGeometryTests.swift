import XCTest
@testable import MacAllYouNeed

final class DockPreviewTooltipGeometryTests: XCTestCase {
    func testOverlayRectSitsAboveIcon() {
        let icon = CGRect(x: 100, y: 200, width: 64, height: 64)
        let overlay = DockPreviewTooltipGeometry.overlayRect(iconRect: icon)
        XCTAssertEqual(overlay.maxY, icon.minY, accuracy: 0.5)
        XCTAssertGreaterThan(overlay.width, icon.width)
    }
}
