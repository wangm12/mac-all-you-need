import Core
import XCTest
@testable import MacAllYouNeed

final class FolderHistoryPanelPlacementTests: XCTestCase {
    func testOriginTopCenterOnVisibleFrame() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 860)
        let size = NSSize(width: 520, height: 400)
        let origin = FolderHistoryPanelPlacement.origin(panelSize: size, visibleFrame: visible)
        XCTAssertEqual(origin.x, 460, accuracy: 0.5)
        XCTAssertEqual(
            origin.y,
            visible.maxY - size.height - FolderHistoryPanelPlacement.topInsetFromVisibleTop,
            accuracy: 0.5
        )
    }

    func testOriginClampsWhenPanelTallerThanVisibleFrame() {
        let visible = CGRect(x: 0, y: 0, width: 800, height: 200)
        let size = NSSize(width: 520, height: 400)
        let origin = FolderHistoryPanelPlacement.origin(panelSize: size, visibleFrame: visible)
        XCTAssertEqual(origin.y, visible.minY, accuracy: 0.5)
    }

    func testPreferredScreenFallsBackToCursorScreen() throws {
        let screens = NSScreen.screens
        guard let first = screens.first else {
            throw XCTSkip("No screens available")
        }
        let point = NSPoint(x: first.frame.midX, y: first.frame.midY)
        let screen = FolderHistoryPanelPlacement.preferredScreen(
            frontmostBundleID: "com.apple.Safari",
            screens: screens,
            mouseLocation: point,
            finderWindowFrameProvider: { nil }
        )
        XCTAssertEqual(screen?.frame, first.frame)
    }
}

@MainActor
final class FolderHistorySwitcherModelTests: XCTestCase {
    func testDisplayedRowsCapWhenSearchEmpty() {
        let model = FolderHistorySwitcherModel()
        model.rows = (0 ..< 20).map { i in
            FolderHistoryRow(id: Int64(i), path: "/tmp/folder-\(i)")
        }
        model.searchText = ""
        XCTAssertEqual(model.displayedRows.count, FolderHistoryDisplayLimits.quickPickCount)
    }
}
