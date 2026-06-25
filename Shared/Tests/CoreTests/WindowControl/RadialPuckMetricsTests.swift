import Core
import XCTest

final class RadialPuckMetricsTests: XCTestCase {
    func testPanelOriginPlacesCircleCenterAtMenuCenterAppKit() {
        let menuCenter = CGPoint(x: 640, y: 512)
        let origin = RadialPuckMetrics.panelOriginAppKit(menuCenter: menuCenter)
        let center = RadialPuckMetrics.circleCenterInPanel
        let fromBottom = RadialPuckMetrics.panelSize.height - center.y
        XCTAssertEqual(menuCenter.x, origin.x + center.x, accuracy: 0.5)
        XCTAssertEqual(menuCenter.y, origin.y + fromBottom, accuracy: 0.5)
    }

    func testFullScreenHysteresisOrdering() {
        XCTAssertGreaterThan(RadialPuckMetrics.fullScreenEnterDistance, RadialPuckMetrics.fullScreenExitDistance)
        XCTAssertGreaterThan(RadialPuckMetrics.armedEnterDistance, RadialPuckMetrics.armedExitDistance)
    }

    func testActivePuckCenterMapsCanonicalAnglesToQuadrants() {
        let center = RadialPuckMetrics.circleCenterInPanel
        let radius: CGFloat = 55

        let top = RadialPuckMetrics.activePuckCenter(forRingIndex: 0, radius: radius)
        XCTAssertEqual(top.x, center.x, accuracy: 0.01)
        XCTAssertEqual(top.y, center.y - radius, accuracy: 0.01)

        let right = RadialPuckMetrics.activePuckCenter(forRingIndex: 2, radius: radius)
        XCTAssertEqual(right.x, center.x + radius, accuracy: 0.01)
        XCTAssertEqual(right.y, center.y, accuracy: 0.01)

        let bottom = RadialPuckMetrics.activePuckCenter(forRingIndex: 4, radius: radius)
        XCTAssertEqual(bottom.x, center.x, accuracy: 0.01)
        XCTAssertEqual(bottom.y, center.y + radius, accuracy: 0.01)

        let left = RadialPuckMetrics.activePuckCenter(forRingIndex: 6, radius: radius)
        XCTAssertEqual(left.x, center.x - radius, accuracy: 0.01)
        XCTAssertEqual(left.y, center.y, accuracy: 0.01)
    }
}
