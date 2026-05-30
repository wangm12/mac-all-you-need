import XCTest
@testable import Core

final class FolderHistoryRetentionTests: XCTestCase {
    func testNoEvictionUnderLimit() {
        let rows: [(id: Int64, isPinned: Bool)] = [(1, false), (2, false)]
        XCTAssertEqual(FolderHistoryRetention.evictIDs(rows: rows, maxCount: 5), [])
    }

    func testEvictsOldestUnpinned() {
        // Sorted newest-first; oldest unpinned (id 1) should be evicted.
        let rows: [(id: Int64, isPinned: Bool)] = [(3, false), (2, false), (1, false)]
        XCTAssertEqual(FolderHistoryRetention.evictIDs(rows: rows, maxCount: 2), [1])
    }

    func testPinnedExemptFromEviction() {
        let rows: [(id: Int64, isPinned: Bool)] = [(3, false), (2, true), (1, false)]
        // Only 2 unpinned exist; maxCount 1 evicts the oldest unpinned (id 1).
        XCTAssertEqual(FolderHistoryRetention.evictIDs(rows: rows, maxCount: 1), [1])
    }

    func testPinnedNeverCountedAgainstLimit() {
        let rows: [(id: Int64, isPinned: Bool)] = [(3, true), (2, true), (1, false)]
        XCTAssertEqual(FolderHistoryRetention.evictIDs(rows: rows, maxCount: 0), [1])
    }
}
