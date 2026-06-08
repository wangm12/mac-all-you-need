import Core
import XCTest

final class FolderHistoryMatcherTests: XCTestCase {
    private func row(path: String, visits: Int = 1, pinned: Bool = false) -> FolderHistoryRow {
        FolderHistoryRow(
            id: Int64(path.hashValue),
            path: path,
            visitedAt: Date(),
            visitCount: visits,
            isPinned: pinned
        )
    }

    func testEmptyQueryReturnsAllRows() {
        let rows = [row(path: "/Users/me/A"), row(path: "/Users/me/B")]
        XCTAssertEqual(FolderHistoryMatcher.ranked(rows: rows, query: "").count, 2)
        XCTAssertEqual(FolderHistoryMatcher.ranked(rows: rows, query: "   ").count, 2)
    }

    func testTokenFilterAndVisitSort() {
        let rows = [
            row(path: "/Users/me/work/inbox", visits: 2),
            row(path: "/Users/me/mail/inbox", visits: 5),
        ]
        let ranked = FolderHistoryMatcher.ranked(rows: rows, query: "in")
        XCTAssertEqual(ranked.map(\.path), ["/Users/me/mail/inbox", "/Users/me/work/inbox"])
    }

    func testPinnedSortsAboveUnpinned() {
        let rows = [
            row(path: "/Users/me/a", visits: 10),
            row(path: "/Users/me/b", visits: 1, pinned: true),
        ]
        let ranked = FolderHistoryMatcher.ranked(rows: rows, query: "me")
        XCTAssertEqual(ranked.first?.path, "/Users/me/b")
    }
}
