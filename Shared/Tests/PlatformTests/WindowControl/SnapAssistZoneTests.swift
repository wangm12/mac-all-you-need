import Core
import CoreGraphics
import XCTest

final class SnapAssistZoneTests: XCTestCase {
    func testCenterZoneInsideInset() {
        let frame = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let tester = SnapAssistZoneHitTester(insetFraction: 0.25)
        let center = CGPoint(x: 500, y: 400)
        XCTAssertEqual(tester.zone(at: center, in: frame), .center)
    }

    func testLeftHalfZoneOnWestBand() {
        let frame = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let tester = SnapAssistZoneHitTester(insetFraction: 0.25)
        let point = CGPoint(x: 50, y: 400)
        XCTAssertEqual(tester.zone(at: point, in: frame), .leftHalf)
    }
}
