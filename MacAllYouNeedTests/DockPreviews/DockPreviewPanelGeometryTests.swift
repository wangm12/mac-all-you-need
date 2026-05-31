import XCTest
@testable import MacAllYouNeed

final class DockPreviewPanelGeometryTests: XCTestCase {
    func testPlacementPointMatchesDockDoorBottomIcon() {
        let screen = NSScreen.main!
        let screenHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        // AX frame: icon near bottom of primary display (top-left origin).
        let axIcon = CGRect(x: 500, y: screenHeight - 80, width: 48, height: 48)
        let origin = DockPreviewPanelGeometry.panelOrigin(
            axIconRect: axIcon,
            panelSize: CGSize(width: 200, height: 100),
            screen: screen,
            dockEdge: .bottom,
            bufferFromDock: -20
        )
        let flipped = DockPreviewDockCoordinates.flippedIconRect(axRect: axIcon, screen: screen)
        XCTAssertEqual(origin.x, flipped.midX - 100, accuracy: 1)
        XCTAssertEqual(origin.y, flipped.minY - 20, accuracy: 1)
    }

    func testFrozenPlacementAnchorPreservesAXRect() {
        let tile = CGRect(x: 200, y: 920, width: 48, height: 52)
        let frozen = DockPreviewPanelGeometry.frozenPlacementAnchor(axRect: tile)
        XCTAssertEqual(frozen, tile)
    }

    func testCocoaIconRectAlignsWithFlippedPlacement() {
        let screen = NSScreen.main!
        let screenHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let axIcon = CGRect(x: 300, y: screenHeight - 64, width: 40, height: 40)
        let cocoa = DockPreviewDockCoordinates.cocoaIconRect(axRect: axIcon, screen: screen)
        let flipped = DockPreviewDockCoordinates.flippedIconRect(axRect: axIcon, screen: screen)
        XCTAssertEqual(cocoa.maxY, flipped.minY, accuracy: 0.1)
        XCTAssertEqual(cocoa.minY, flipped.minY - flipped.height, accuracy: 0.1)
    }

    func testPanelClampedToScreenFrame() {
        let screen = NSScreen.main!
        let screenHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let axIcon = CGRect(x: 10, y: screenHeight - 60, width: 48, height: 48)
        let origin = DockPreviewPanelGeometry.panelOrigin(
            axIconRect: axIcon,
            panelSize: CGSize(width: 300, height: 100),
            screen: screen,
            dockEdge: .bottom,
            bufferFromDock: 0
        )
        XCTAssertGreaterThanOrEqual(origin.x, screen.frame.minX)
        XCTAssertGreaterThanOrEqual(origin.y, screen.frame.minY)
    }
}
