import CoreGraphics
@testable import Core
import XCTest

final class WindowWorkspaceAdjusterTests: XCTestCase {
    func testZeroGapReturnsOriginalFrame() {
        let frame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        XCTAssertEqual(WindowWorkspaceAdjuster.adjustedVisibleFrame(frame), frame)
    }

    func testPositiveGapInsetsUniformly() {
        let frame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let adjusted = WindowWorkspaceAdjuster.adjustedVisibleFrame(frame, edgeGap: 8)
        XCTAssertEqual(adjusted, frame.insetBy(dx: 8, dy: 8))
    }
}
