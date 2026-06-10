import Core
import XCTest

final class BSPAutoFlowSpikeTests: XCTestCase {
    func testSplitTwoWindowsVertical() {
        let frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let (left, right) = BSPAutoFlowSpike.splitTwoWindows(in: frame, orientation: .vertical)
        XCTAssertEqual(left.width, 600, accuracy: 0.5)
        XCTAssertEqual(right.width, 600, accuracy: 0.5)
        XCTAssertEqual(left.maxX, right.minX, accuracy: 0.5)
    }
}
