import XCTest
@testable import MacAllYouNeed

final class DockPreviewWindowMatcherTests: XCTestCase {
    func testMatchesByFrameProximity() {
        let ax = [DockPreviewWindowMatcher.AXWindowInfo(
            title: "Safari", isMinimized: false,
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            windowID: nil
        )]
        let sc = [DockPreviewWindowMatcher.SCWindowInfo(
            windowID: 42, frame: CGRect(x: 0, y: 0, width: 800, height: 600), pid: 100, title: "Safari"
        )]
        let result = DockPreviewWindowMatcher.merge(ax: ax, sc: sc, pid: 100)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].title, "Safari")
        XCTAssertEqual(result[0].id, 42)
    }

    func testDeduplicatesOverlappingFrames() {
        let entries = [
            DockPreviewWindowEntry(
                id: 1, pid: 100, title: "Weiqiang Wang (DM) - Uber",
                frame: CGRect(x: 0, y: 0, width: 800, height: 600),
                thumbnail: nil, isMinimized: false, isOnScreen: true
            ),
            DockPreviewWindowEntry(
                id: 2, pid: 100, title: "Window",
                frame: CGRect(x: 10, y: 10, width: 780, height: 580),
                thumbnail: nil, isMinimized: false, isOnScreen: true
            ),
        ]
        let deduped = DockPreviewWindowMatcher.deduplicate(entries)
        XCTAssertEqual(deduped.count, 1)
        XCTAssertTrue(deduped[0].title.contains("Weiqiang"))
    }

    func testIncludesAXWindowWithIDMissedByScreenCapture() {
        let ax = [
            DockPreviewWindowMatcher.AXWindowInfo(
                title: "Omni - Google Chrome",
                isMinimized: false,
                frame: CGRect(x: 100, y: 100, width: 1200, height: 800),
                windowID: 99
            ),
            DockPreviewWindowMatcher.AXWindowInfo(
                title: "GitHub - Google Chrome",
                isMinimized: false,
                frame: CGRect(x: 1600, y: 100, width: 1200, height: 800),
                windowID: 100
            ),
        ]
        let sc = [
            DockPreviewWindowMatcher.SCWindowInfo(
                windowID: 99,
                frame: CGRect(x: 100, y: 100, width: 1200, height: 800),
                pid: 300,
                title: "Omni"
            ),
        ]
        let result = DockPreviewWindowMatcher.merge(ax: ax, sc: sc, pid: 300)
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.contains { $0.id == 100 })
    }

    func testMinimizedWindowIncluded() {
        let ax = [DockPreviewWindowMatcher.AXWindowInfo(
            title: "Terminal", isMinimized: true,
            frame: CGRect(x: 500, y: 500, width: 10, height: 10),
            windowID: nil
        )]
        let result = DockPreviewWindowMatcher.merge(ax: ax, sc: [], pid: 200)
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0].isMinimized)
    }
}
