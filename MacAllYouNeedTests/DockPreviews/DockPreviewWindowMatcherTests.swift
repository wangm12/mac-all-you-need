import XCTest
@testable import MacAllYouNeed

final class DockPreviewWindowMatcherTests: XCTestCase {
    func testMatchesByFrameProximity() {
        let ax = [DockPreviewWindowMatcher.AXWindowInfo(
            title: "Safari", isMinimized: false,
            frame: CGRect(x: 0, y: 0, width: 800, height: 600)
        )]
        let sc = [DockPreviewWindowMatcher.SCWindowInfo(
            windowID: 42, frame: CGRect(x: 0, y: 0, width: 800, height: 600), pid: 100
        )]
        let result = DockPreviewWindowMatcher.merge(ax: ax, sc: sc, pid: 100)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].title, "Safari")
        XCTAssertEqual(result[0].id, 42)
    }

    func testMinimizedWindowIncluded() {
        let ax = [DockPreviewWindowMatcher.AXWindowInfo(
            title: "Terminal", isMinimized: true,
            frame: CGRect(x: 500, y: 500, width: 10, height: 10)
        )]
        let result = DockPreviewWindowMatcher.merge(ax: ax, sc: [], pid: 200)
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0].isMinimized)
    }
}
