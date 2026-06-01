import Core
import CoreGraphics
import XCTest

final class RadialSelectionMathTests: XCTestCase {
    func testCursorOnCenterIconSelectsMaximize() {
        XCTAssertEqual(RadialSelectionMath.selection(from: .zero), .center)
        XCTAssertEqual(RadialSelectionMath.selection(from: CGPoint(x: 3, y: 4)), .center)
    }

    func testBetweenCenterAndRingRequiresActivationDistance() {
        // Outside the center button but inside the old "dead" band: still not a ring until
        // the cursor moves past activationDistance (and past centerBandRadius).
        let delta = CGPoint(x: 20, y: 15) // ~25pt, within center band
        XCTAssertEqual(RadialSelectionMath.selection(from: delta), .center)
        let outsideCenter = CGPoint(x: 0, y: -40) // 40pt, past center band, past activation
        XCTAssertEqual(RadialSelectionMath.selection(from: outsideCenter), .ring(0))
    }

    func testTopDirectionIsRing0() {
        let sel = RadialSelectionMath.selection(from: CGPoint(x: 0, y: -100))
        XCTAssertEqual(sel, .ring(0))
    }

    func testRightDirectionIsRing2() {
        let sel = RadialSelectionMath.selection(from: CGPoint(x: 100, y: 0))
        XCTAssertEqual(sel, .ring(2))
    }

    func testCenterBandIsCenter() {
        let sel = RadialSelectionMath.selection(from: CGPoint(x: 0, y: -20))
        XCTAssertEqual(sel, .center)
    }

    func testCenterBandMatchesVisualButtonNotDiameter() {
        XCTAssertEqual(
            RadialSelectionMath.centerBandRadius,
            RadialMenuMetrics.centerSelectionRadius
        )
        XCTAssertLessThan(RadialMenuMetrics.centerSelectionRadius, RadialMenuMetrics.menuRadius * 0.5)
    }

    func testBeyondCenterBandSelectsRingNotMaximize() {
        let towardTopIcon = CGPoint(x: 0, y: -RadialMenuMetrics.ringIconRadius)
        XCTAssertEqual(RadialSelectionMath.selection(from: towardTopIcon), .ring(0))
    }

    func testCloseZoneSelectsCancel() {
        let center = CGPoint(x: 500, y: 400)
        let cursor = CGPoint(
            x: center.x + RadialMenuMetrics.closePillCenterOffset.x,
            y: center.y + RadialMenuMetrics.closePillCenterOffset.y
        )
        XCTAssertTrue(RadialSelectionMath.closeZoneContains(cursor: cursor, menuCenter: center))
        XCTAssertEqual(
            RadialSelectionMath.selection(from: CGPoint(x: -90, y: -90), cursor: cursor, menuCenter: center),
            .cancel
        )
    }

    func testCloseZoneTakesPriorityOverRing() {
        let center = CGPoint(x: 500, y: 400)
        let cursor = CGPoint(
            x: center.x + RadialMenuMetrics.closePillCenterOffset.x,
            y: center.y + RadialMenuMetrics.closePillCenterOffset.y
        )
        XCTAssertEqual(
            RadialSelectionMath.selection(from: CGPoint(x: 0, y: -100), cursor: cursor, menuCenter: center),
            .cancel
        )
    }

    func testAllSegmentsReachable() {
        let angles = stride(from: 0.0, to: 2 * Double.pi, by: 2 * Double.pi / 8)
        let selections = Set(angles.map { a in
            RadialSelectionMath.selection(from: CGPoint(x: sin(a) * 100, y: -cos(a) * 100))
        })
        XCTAssertEqual(selections.count, 8)
    }
}
