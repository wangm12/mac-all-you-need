@testable import Core
import CoreGraphics
import XCTest

final class WindowSnapIntentTests: XCTestCase {
    private let frame = CGRect(x: 0, y: 0, width: 1440, height: 900)

    func testStartingInEdgeZoneAndMovingSlightlyDoesNotArmSnap() {
        var intent = WindowSnapIntentTracker()

        intent.begin(at: CGPoint(x: 5, y: 450), visibleFrame: frame)
        let zone = intent.update(at: CGPoint(x: 8, y: 452), visibleFrame: frame)

        XCTAssertNil(zone)
        XCTAssertFalse(intent.isArmed)
        XCTAssertNil(intent.commit())
    }

    func testStartingInEdgeZoneRequiresMovingOutThenBackInToArmSnap() {
        var intent = WindowSnapIntentTracker()

        intent.begin(at: CGPoint(x: 5, y: 450), visibleFrame: frame)
        XCTAssertNil(intent.update(at: CGPoint(x: 100, y: 450), visibleFrame: frame))

        let zone = intent.update(at: CGPoint(x: 5, y: 450), visibleFrame: frame)

        XCTAssertEqual(zone, .left)
        XCTAssertEqual(intent.armedAction, .leftHalf)
        XCTAssertEqual(intent.commit(), .leftHalf)
        XCTAssertFalse(intent.isArmed)
    }

    func testStartingInsideArmsExpectedCornerAfterRealMovement() {
        var intent = WindowSnapIntentTracker()

        intent.begin(at: CGPoint(x: 720, y: 450), visibleFrame: frame)
        XCTAssertNil(intent.update(at: CGPoint(x: 700, y: 450), visibleFrame: frame))

        let zone = intent.update(at: CGPoint(x: 5, y: 5), visibleFrame: frame)

        XCTAssertEqual(zone, .topLeft)
        XCTAssertEqual(intent.armedAction, .topLeft)
    }

    func testFullSizeRepositionFromTopZoneDoesNotSnapUntilExplicitReentry() {
        var intent = WindowSnapIntentTracker()

        intent.begin(at: CGPoint(x: 720, y: 5), visibleFrame: frame)
        XCTAssertNil(intent.update(at: CGPoint(x: 730, y: 8), visibleFrame: frame))
        XCTAssertNil(intent.update(at: CGPoint(x: 730, y: 80), visibleFrame: frame))

        let zone = intent.update(at: CGPoint(x: 730, y: 5), visibleFrame: frame)

        XCTAssertEqual(zone, .top)
        XCTAssertEqual(intent.armedAction, .maximize)
    }

    func testCommitRequiresArmedZone() {
        var intent = WindowSnapIntentTracker()

        intent.begin(at: CGPoint(x: 720, y: 450), visibleFrame: frame)
        XCTAssertNil(intent.update(at: CGPoint(x: 700, y: 450), visibleFrame: frame))
        XCTAssertNil(intent.commit())

        XCTAssertNil(intent.update(at: CGPoint(x: 5, y: 450), visibleFrame: frame))
    }
}
