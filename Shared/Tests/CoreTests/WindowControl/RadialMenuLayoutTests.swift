import Core
import XCTest

final class RadialMenuLayoutTests: XCTestCase {
    func testRingActionsCountIs8() {
        XCTAssertEqual(RadialMenuLayout.ringActions.count, 8)
    }

    func testAllRingActionsAreDifferent() {
        XCTAssertEqual(Set(RadialMenuLayout.ringActions).count, 8)
    }

    func testRingIndexZeroIsDefined() {
        XCTAssertNotNil(RadialMenuLayout.action(forRingIndex: 0))
    }

    func testRingIndexOutOfRangeIsNil() {
        XCTAssertNil(RadialMenuLayout.action(forRingIndex: 99))
        XCTAssertNil(RadialMenuLayout.action(forRingIndex: -1))
    }

    func testFillScreenActionIsMaximize() {
        XCTAssertEqual(RadialMenuLayout.fillScreenAction, .maximize)
    }

    func testCenterActionIsMaximize() {
        XCTAssertEqual(RadialMenuLayout.centerAction, .maximize)
    }

    func testInMenuShortcutDisplayMapsRingAndCenter() {
        XCTAssertEqual(RadialMenuLayout.inMenuShortcutDisplay(for: .topHalf), "W")
        XCTAssertEqual(RadialMenuLayout.inMenuShortcutDisplay(for: .maximize), "F, M")
    }

    func testClosePillSitsAtTopLeft45Degrees() {
        let layout = RadialMenuMetrics.panelLayout(for: RadialMenuMetrics.menuRadius)
        let pillCenter = CGPoint(
            x: layout.closePillOrigin.x + RadialMenuMetrics.closePillSize.width / 2,
            y: layout.closePillOrigin.y + RadialMenuMetrics.closePillSize.height / 2
        )
        let deltaX = layout.circleCenter.x - pillCenter.x
        let deltaY = layout.circleCenter.y - pillCenter.y
        XCTAssertGreaterThan(deltaX, 0)
        XCTAssertGreaterThan(deltaY, 0)
        XCTAssertEqual(deltaX, deltaY, accuracy: 1)
    }

    func testClosePillOrbitMaintainsGapFromRing() {
        let radius = RadialMenuMetrics.menuRadius
        let layout = RadialMenuMetrics.panelLayout(for: radius)
        let pillCenter = CGPoint(
            x: layout.closePillOrigin.x + RadialMenuMetrics.closePillSize.width / 2,
            y: layout.closePillOrigin.y + RadialMenuMetrics.closePillSize.height / 2
        )
        let centerToPill = hypot(pillCenter.x - layout.circleCenter.x, pillCenter.y - layout.circleCenter.y)
        let expectedOrbit = RadialMenuMetrics.closePillOrbitDistance(for: radius)
        XCTAssertEqual(centerToPill, expectedOrbit, accuracy: 1)
    }

    func testPanelOriginPlacesCircleCenterAtMenuCenterAppKit() {
        let menuCenter = CGPoint(x: 640, y: 512)
        let layout = RadialMenuMetrics.panelLayout(for: RadialMenuMetrics.menuRadius)
        let origin = RadialMenuMetrics.panelOriginAppKit(menuCenter: menuCenter)
        let fromBottom = layout.size.height - layout.circleCenter.y
        XCTAssertEqual(menuCenter.x, origin.x + layout.circleCenter.x, accuracy: 0.5)
        XCTAssertEqual(menuCenter.y, origin.y + fromBottom, accuracy: 0.5)
    }
}
