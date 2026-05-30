import XCTest
@testable import Core

final class FolderHistoryDedupTests: XCTestCase {
    func testRecordsWhenNoHistory() {
        XCTAssertTrue(FolderHistoryDedup.shouldRecord(newPath: "/A", lastPath: nil, lastDate: nil))
    }

    func testSkipsSamePathWithinWindow() {
        let now = Date()
        XCTAssertFalse(FolderHistoryDedup.shouldRecord(
            newPath: "/A", lastPath: "/A", lastDate: now, debounceWindow: 2.0, now: now.addingTimeInterval(1)
        ))
    }

    func testRecordsSamePathAfterWindow() {
        let now = Date()
        XCTAssertTrue(FolderHistoryDedup.shouldRecord(
            newPath: "/A", lastPath: "/A", lastDate: now, debounceWindow: 2.0, now: now.addingTimeInterval(3)
        ))
    }

    func testRecordsDifferentPathImmediately() {
        let now = Date()
        XCTAssertTrue(FolderHistoryDedup.shouldRecord(
            newPath: "/B", lastPath: "/A", lastDate: now, debounceWindow: 999, now: now
        ))
    }
}
