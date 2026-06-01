import XCTest
@testable import MacAllYouNeed

@MainActor
final class DockPreviewStateCoordinatorTests: XCTestCase {
    func testMergeWindowsUpdatesInPlaceAndRemovesStale() {
        let coordinator = DockPreviewStateCoordinator()
        let w1 = DockPreviewWindowEntry(
            id: 1, pid: 100, title: "A", frame: .zero, thumbnail: nil,
            isMinimized: false, isOnScreen: true
        )
        let w2 = DockPreviewWindowEntry(
            id: 2, pid: 100, title: "B", frame: .zero, thumbnail: nil,
            isMinimized: false, isOnScreen: true
        )
        _ = coordinator.setWindows([w1, w2], preserveSelection: false)

        let w1Updated = DockPreviewWindowEntry(
            id: 1, pid: 100, title: "A2", frame: .zero, thumbnail: nil,
            isMinimized: false, isOnScreen: true
        )
        let w3 = DockPreviewWindowEntry(
            id: 3, pid: 100, title: "C", frame: .zero, thumbnail: nil,
            isMinimized: false, isOnScreen: true
        )
        XCTAssertTrue(coordinator.mergeWindows([w1Updated, w3]))
        XCTAssertEqual(coordinator.windows.map(\.id), [1, 3])
        XCTAssertEqual(coordinator.windows.first?.title, "A2")
    }
}
