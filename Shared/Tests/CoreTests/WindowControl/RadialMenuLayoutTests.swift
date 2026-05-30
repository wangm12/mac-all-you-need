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

    func testCenterActionIsMaximize() {
        XCTAssertEqual(RadialMenuLayout.centerAction, .maximize)
    }
}
