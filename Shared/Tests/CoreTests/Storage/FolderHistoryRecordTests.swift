import XCTest
@testable import Core

final class FolderHistoryRecordTests: XCTestCase {
    func testDisplayNameIsLastComponent() {
        let row = FolderHistoryRow(path: "/Users/me/Documents/Projects")
        XCTAssertEqual(row.displayName, "Projects")
    }

    func testDefaultValues() {
        let row = FolderHistoryRow(path: "/Users/me")
        XCTAssertEqual(row.visitCount, 1)
        XCTAssertFalse(row.isPinned)
        XCTAssertNil(row.iconData)
    }

    func testCodableRoundTrip() throws {
        let row = FolderHistoryRow(id: 7, path: "/Users/me/A", visitCount: 3, isPinned: true)
        let data = try JSONEncoder().encode(row)
        let decoded = try JSONDecoder().decode(FolderHistoryRow.self, from: data)
        XCTAssertEqual(decoded, row)
    }
}
