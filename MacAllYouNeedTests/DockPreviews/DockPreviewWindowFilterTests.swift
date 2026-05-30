import XCTest
@testable import MacAllYouNeed

final class DockPreviewWindowFilterTests: XCTestCase {
    func testFiltersOffScreenNonMinimized() {
        let on = DockPreviewWindowEntry(
            id: 1, pid: 100, title: "On", frame: .zero,
            thumbnail: nil, isMinimized: false, isOnScreen: true
        )
        let off = DockPreviewWindowEntry(
            id: 2, pid: 100, title: "Off", frame: .zero,
            thumbnail: nil, isMinimized: false, isOnScreen: false
        )
        let minimized = DockPreviewWindowEntry(
            id: 3, pid: 100, title: "Min", frame: .zero,
            thumbnail: nil, isMinimized: true, isOnScreen: false
        )
        let result = DockPreviewWindowFilter.filter([on, off, minimized])
        XCTAssertEqual(result.count, 2)
        XCTAssertFalse(result.contains { $0.id == 2 })
    }
}
