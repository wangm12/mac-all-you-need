import CoreGraphics
@testable import MacAllYouNeed
import XCTest

final class RadialPuckDampingTests: XCTestCase {
    func testDampConvergesWithoutOvershoot() {
        var value: CGFloat = 0
        let target: CGFloat = 1
        for _ in 0 ..< 120 {
            value = RadialPuckDamping.damp(current: value, target: target, lambda: 14, dt: 1.0 / 60.0)
        }
        XCTAssertGreaterThan(value, 0.99)
        XCTAssertLessThanOrEqual(value, 1.0)
    }

    func testLargeDtDoesNotOvershoot() {
        let value = RadialPuckDamping.damp(current: 0, target: 1, lambda: 14, dt: 1)
        XCTAssertLessThanOrEqual(value, 1)
    }

    func testShortestAngleWrapsForward() {
        let from: CGFloat = 350 * CGFloat.pi / 180
        let to: CGFloat = 10 * CGFloat.pi / 180
        let delta = RadialPuckDamping.shortestAngleDelta(from: from, to: to)
        XCTAssertGreaterThan(delta, 0)
        XCTAssertLessThan(delta, CGFloat.pi)
    }

    func testShortestAngleAvoidsLongArcNearWrap() {
        let from: CGFloat = 3.0
        let to: CGFloat = 0.1
        let delta = RadialPuckDamping.shortestAngleDelta(from: from, to: to)
        XCTAssertGreaterThan(delta, 0)
        XCTAssertLessThan(delta, .pi / 2)
    }

    func testDeterministicSequence() {
        let dt: CGFloat = 1.0 / 60.0
        func run() -> CGFloat {
            var value: CGFloat = 0
            for _ in 0 ..< 30 {
                value = RadialPuckDamping.damp(current: value, target: 1, lambda: 12, dt: dt)
            }
            return value
        }
        XCTAssertEqual(run(), run())
    }
}
