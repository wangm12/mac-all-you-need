import XCTest
@testable import MacAllYouNeed

final class DockPreviewAXHelpersTests: XCTestCase {
    func testFocusedWindowIDReturnsNilWithoutCandidates() {
        XCTAssertNil(DockAXHelpers.focusedWindowID(for: 1, among: []))
    }
}

@MainActor
final class DockPreviewStateCoordinatorFilterTests: XCTestCase {
    func testSelectNextInFilteredRespectsSearch() {
        let coordinator = DockPreviewStateCoordinator()
        let entries = (1 ... 3).map { id in
            DockPreviewWindowEntry(
                id: CGWindowID(id),
                pid: 100,
                title: "Window \(id)",
                frame: .zero,
                thumbnail: nil,
                isMinimized: false,
                isOnScreen: true
            )
        }
        coordinator.mode = .windowSwitcher
        _ = coordinator.setWindows(entries, preserveSelection: false)
        coordinator.searchQuery = "Window 2"
        coordinator.selectNextInFiltered(delta: 1)
        XCTAssertEqual(coordinator.selectedIndex, 1)
        XCTAssertEqual(coordinator.windows[coordinator.selectedIndex].title, "Window 2")
    }

    func testClampSelectionToFilteredSearch() {
        let coordinator = DockPreviewStateCoordinator()
        let entries = [
            DockPreviewWindowEntry(
                id: 1, pid: 1, title: "Alpha", frame: .zero, thumbnail: nil,
                isMinimized: false, isOnScreen: true
            ),
            DockPreviewWindowEntry(
                id: 2, pid: 1, title: "Beta", frame: .zero, thumbnail: nil,
                isMinimized: false, isOnScreen: true
            ),
        ]
        _ = coordinator.setWindows(entries, preserveSelection: false)
        coordinator.selectedIndex = 1
        coordinator.searchQuery = "Alpha"
        coordinator.clampSelectionToFilteredSearch()
        XCTAssertEqual(coordinator.selectedIndex, 0)
    }
}

final class DockPreviewEmbedRoutingTests: XCTestCase {
    func testMusicRoutesToMediaWidget() {
        let widgets = DockWidgetSettings(
            enableMediaWidget: true,
            enableCalendarWidget: true,
            enableFolderWidget: false,
            folderShowHiddenFiles: false
        )
        XCTAssertEqual(
            DockPreviewEmbedRouting.embeddedContent(bundleIdentifier: "com.apple.Music", widgets: widgets),
            .media
        )
    }

    func testCalendarRoutesToCalendarWidget() {
        let widgets = DockWidgetSettings.default
        XCTAssertEqual(
            DockPreviewEmbedRouting.embeddedContent(bundleIdentifier: "com.apple.iCal", widgets: widgets),
            .calendar
        )
    }
}
