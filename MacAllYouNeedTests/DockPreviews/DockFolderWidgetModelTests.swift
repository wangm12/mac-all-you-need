import XCTest
@testable import MacAllYouNeed

final class DockFolderWidgetModelTests: XCTestCase {
    func testSortedItemsByNameAscending() {
        let items = [
            DockFolderWidgetItem(
                url: URL(fileURLWithPath: "/tmp/z"),
                name: "z",
                isDirectory: false,
                modifiedDate: .distantPast,
                size: 0,
                localizedKind: ""
            ),
            DockFolderWidgetItem(
                url: URL(fileURLWithPath: "/tmp/a"),
                name: "a",
                isDirectory: false,
                modifiedDate: .distantPast,
                size: 0,
                localizedKind: ""
            ),
        ]
        let sorted = DockFolderWidgetLoader.sortedItems(items, order: .name, reversed: false)
        XCTAssertEqual(sorted.map(\.name), ["a", "z"])
    }

    func testSortedItemsByNameDescending() {
        let items = [
            DockFolderWidgetItem(
                url: URL(fileURLWithPath: "/tmp/a"),
                name: "a",
                isDirectory: false,
                modifiedDate: .distantPast,
                size: 0,
                localizedKind: ""
            ),
            DockFolderWidgetItem(
                url: URL(fileURLWithPath: "/tmp/z"),
                name: "z",
                isDirectory: false,
                modifiedDate: .distantPast,
                size: 0,
                localizedKind: ""
            ),
        ]
        let sorted = DockFolderWidgetLoader.sortedItems(items, order: .name, reversed: true)
        XCTAssertEqual(sorted.map(\.name), ["z", "a"])
    }

    func testBookmarkStoreRoundTrip() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("dock-folder-bookmark-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let bookmark = try temp.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        DockFolderWidgetBookmarkStore.saveBookmark(for: temp.path, data: bookmark)
        let resolved = DockFolderWidgetBookmarkStore.resolvedURL(for: temp.path)
        XCTAssertNotNil(resolved)
    }
}
