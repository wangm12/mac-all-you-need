@testable import Core
import CoreGraphics
import XCTest

final class WindowGeometryCalculatorTests: XCTestCase {
    func testHalvesCornersAndCenter() {
        let calc = WindowGeometryCalculator()
        let frame = CGRect(x: 0, y: 0, width: 1440, height: 900)

        XCTAssertEqual(
            calc.rect(for: .leftHalf, visibleFrame: frame),
            CGRect(x: 0, y: 0, width: 720, height: 900)
        )
        XCTAssertEqual(
            calc.rect(for: .topRight, visibleFrame: frame),
            CGRect(x: 720, y: 0, width: 720, height: 450)
        )
        XCTAssertEqual(
            calc.rect(for: .center, visibleFrame: frame, currentSize: CGSize(width: 800, height: 500))?.origin,
            CGPoint(x: 320, y: 200)
        )
    }

    func testMaximizeAndAlmostMaximize() {
        let calc = WindowGeometryCalculator()
        let frame = CGRect(x: 0, y: 0, width: 1440, height: 900)

        XCTAssertEqual(calc.rect(for: .maximize, visibleFrame: frame), frame)
        XCTAssertEqual(
            calc.rect(for: .almostMaximize, visibleFrame: frame),
            CGRect(x: 72, y: 45, width: 1296, height: 810)
        )
    }

    func testTopAndBottomUseAXScreenCoordinates() {
        let calc = WindowGeometryCalculator()
        let frame = CGRect(x: 100, y: 50, width: 1200, height: 800)

        XCTAssertEqual(
            calc.rect(for: .topHalf, visibleFrame: frame),
            CGRect(x: 100, y: 50, width: 1200, height: 400)
        )
        XCTAssertEqual(
            calc.rect(for: .bottomHalf, visibleFrame: frame),
            CGRect(x: 100, y: 450, width: 1200, height: 400)
        )
        XCTAssertEqual(
            calc.rect(for: .topLeft, visibleFrame: frame),
            CGRect(x: 100, y: 50, width: 600, height: 400)
        )
        XCTAssertEqual(
            calc.rect(for: .bottomRight, visibleFrame: frame),
            CGRect(x: 700, y: 450, width: 600, height: 400)
        )
    }

    func testMovingDisplaysPreservesSizeAndTranslatesPosition() {
        let calc = WindowGeometryCalculator()
        let source = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let target = CGRect(x: 1000, y: 100, width: 2000, height: 1000)
        let current = CGRect(x: 250, y: 200, width: 500, height: 400)

        XCTAssertEqual(
            calc.rectForMovingDisplay(
                currentFrame: current,
                sourceVisibleFrame: source,
                targetVisibleFrame: target
            ),
            CGRect(x: 1250, y: 300, width: 500, height: 400)
        )
    }

    func testMovingDisplaysClampsToTargetVisibleFrame() {
        let calc = WindowGeometryCalculator()
        let source = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let target = CGRect(x: 0, y: 0, width: 400, height: 300)
        let current = CGRect(x: 800, y: 800, width: 500, height: 400)

        XCTAssertEqual(
            calc.rectForMovingDisplay(
                currentFrame: current,
                sourceVisibleFrame: source,
                targetVisibleFrame: target
            ),
            CGRect(x: 0, y: 0, width: 400, height: 300)
        )
    }

    func testSnapZoneMapping() {
        let frame = CGRect(x: 0, y: 0, width: 1440, height: 900)

        XCTAssertEqual(
            WindowSnapZone.zone(for: CGPoint(x: 5, y: 5), in: frame, edgeThreshold: 20, cornerThreshold: 80),
            .topLeft
        )
        XCTAssertEqual(
            WindowSnapZone.zone(for: CGPoint(x: 720, y: 5), in: frame, edgeThreshold: 20, cornerThreshold: 80),
            .top
        )
        XCTAssertEqual(
            WindowSnapZone.zone(for: CGPoint(x: 5, y: 450), in: frame, edgeThreshold: 20, cornerThreshold: 80),
            .left
        )
        XCTAssertEqual(
            WindowSnapZone.zone(for: CGPoint(x: 720, y: 450), in: frame, edgeThreshold: 20, cornerThreshold: 80),
            .inside
        )
        XCTAssertEqual(WindowSnapZone.topRight.action, .topRight)
        XCTAssertEqual(WindowSnapZone.top.action, .maximize)
        XCTAssertNil(WindowSnapZone.inside.action)
    }

    func testSnapZoneMapsClearSideEdgeBandsToTopAndBottomHalves() {
        let frame = CGRect(x: 0, y: 0, width: 1440, height: 900)

        XCTAssertEqual(
            WindowSnapZone.zone(
                for: CGPoint(x: 5, y: 140),
                in: frame,
                edgeThreshold: 20,
                cornerThreshold: 80,
                sideHalfThreshold: 180
            ),
            .topHalf
        )
        XCTAssertEqual(
            WindowSnapZone.zone(
                for: CGPoint(x: 1435, y: 760),
                in: frame,
                edgeThreshold: 20,
                cornerThreshold: 80,
                sideHalfThreshold: 180
            ),
            .bottomHalf
        )
    }

    func testSnapZoneUsesAXScreenCoordinatesWithNonZeroOrigin() {
        let frame = CGRect(x: 100, y: 50, width: 1200, height: 800)

        XCTAssertEqual(
            WindowSnapZone.zone(for: CGPoint(x: 110, y: 60), in: frame, edgeThreshold: 20, cornerThreshold: 80),
            .topLeft
        )
        XCTAssertEqual(
            WindowSnapZone.zone(for: CGPoint(x: 700, y: 60), in: frame, edgeThreshold: 20, cornerThreshold: 80),
            .top
        )
        XCTAssertEqual(
            WindowSnapZone.zone(for: CGPoint(x: 1290, y: 840), in: frame, edgeThreshold: 20, cornerThreshold: 80),
            .bottomRight
        )
        XCTAssertEqual(
            WindowSnapZone.zone(for: CGPoint(x: 700, y: 840), in: frame, edgeThreshold: 20, cornerThreshold: 80),
            .bottom
        )
    }
}
