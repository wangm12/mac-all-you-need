import XCTest
@testable import MacAllYouNeed

final class DockPreviewPanelGeometryTests: XCTestCase {
    func testQuartzToCocoaFlip() {
        let quartz = CGRect(x: 100, y: 200, width: 300, height: 400)
        let cocoa = DockPreviewPanelGeometry.cocoaRect(fromQuartz: quartz, screenHeight: 1080)
        XCTAssertEqual(cocoa.origin.y, 1080 - 200 - 400, accuracy: 0.1)
    }

    func testPanelOriginBottomDock() {
        let icon = CGRect(x: 500, y: 0, width: 64, height: 64)
        let origin = DockPreviewPanelGeometry.panelOrigin(
            iconRect: icon,
            panelSize: CGSize(width: 200, height: 100),
            screenBounds: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            dockEdge: .bottom
        )
        XCTAssertEqual(origin.x, 432, accuracy: 1)  // 500 + 32 - 100
        XCTAssertEqual(origin.y, 72, accuracy: 1)   // 64 + 8
    }

    func testPanelClampedToScreen() {
        let icon = CGRect(x: 10, y: 0, width: 64, height: 64)
        let origin = DockPreviewPanelGeometry.panelOrigin(
            iconRect: icon,
            panelSize: CGSize(width: 300, height: 100),
            screenBounds: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            dockEdge: .bottom
        )
        XCTAssertGreaterThanOrEqual(origin.x, 0)
    }
}
