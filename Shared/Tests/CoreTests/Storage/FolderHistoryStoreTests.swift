import XCTest
@testable import Core

final class FolderHistoryStoreTests: XCTestCase {
    func testUpsertCreatesAndUpdates() throws {
        let store = try FolderHistoryStore(url: temporaryURL())
        _ = try store.upsert(path: "/Users/me/Documents")
        _ = try store.upsert(path: "/Users/me/Documents") // second visit
        let rows = try store.list(limit: 10)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.visitCount, 2)
    }

    func testListSortsByVisitedAtDescending() throws {
        let store = try FolderHistoryStore(url: temporaryURL())
        _ = try store.upsert(path: "/Users/me/A")
        Thread.sleep(forTimeInterval: 0.01)
        _ = try store.upsert(path: "/Users/me/B")
        let rows = try store.list(limit: 10)
        XCTAssertEqual(rows.first?.path, "/Users/me/B")
    }

    func testPinnedRowsAppearFirst() throws {
        let store = try FolderHistoryStore(url: temporaryURL())
        let a = try store.upsert(path: "/Users/me/A")
        Thread.sleep(forTimeInterval: 0.01)
        _ = try store.upsert(path: "/Users/me/B")
        try store.pin(id: a.id, pinned: true)
        let rows = try store.list(limit: 10)
        XCTAssertEqual(rows.first?.path, "/Users/me/A")
    }

    func testEviction() throws {
        let store = try FolderHistoryStore(url: temporaryURL())
        for i in 0 ..< 5 {
            _ = try store.upsert(path: "/Users/me/Folder\(i)")
            Thread.sleep(forTimeInterval: 0.01)
        }
        try store.evictStale(maxCount: 3)
        XCTAssertEqual(try store.list(limit: 100).count, 3)
    }

    func testRemove() throws {
        let store = try FolderHistoryStore(url: temporaryURL())
        let a = try store.upsert(path: "/Users/me/A")
        try store.remove(id: a.id)
        XCTAssertEqual(try store.list(limit: 10).count, 0)
    }

    func testSetIcon() throws {
        let store = try FolderHistoryStore(url: temporaryURL())
        let a = try store.upsert(path: "/Users/me/A")
        let icon = Data([1, 2, 3])
        try store.setIcon(id: a.id, iconData: icon)
        XCTAssertEqual(try store.list(limit: 10).first?.iconData, icon)
    }

    func testClear() throws {
        let store = try FolderHistoryStore(url: temporaryURL())
        _ = try store.upsert(path: "/Users/me/A")
        try store.clear()
        XCTAssertEqual(try store.list(limit: 10).count, 0)
    }

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("FolderHistTest-\(UUID()).sqlite")
    }
}
