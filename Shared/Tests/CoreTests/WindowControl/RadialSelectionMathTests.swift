import Core
import CoreGraphics
import XCTest

final class RadialSelectionMathTests: XCTestCase {
    func testNoMovementIsNone() {
        XCTAssertEqual(RadialSelectionMath.selection(from: .zero), .none)
    }

    func testSmallMovementIsNone() {
        XCTAssertEqual(RadialSelectionMath.selection(from: CGPoint(x: 5, y: 5)), .none)
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
        let sel = RadialSelectionMath.selection(from: CGPoint(x: 35, y: 0), activationDistance: 10)
        XCTAssertEqual(sel, .center)
    }

    func testAllSegmentsReachable() {
        let angles = stride(from: 0.0, to: 2 * Double.pi, by: 2 * Double.pi / 8)
        let selections = Set(angles.map { a in
            RadialSelectionMath.selection(from: CGPoint(x: sin(a) * 100, y: -cos(a) * 100))
        })
        XCTAssertEqual(selections.count, 8)
    }
}
