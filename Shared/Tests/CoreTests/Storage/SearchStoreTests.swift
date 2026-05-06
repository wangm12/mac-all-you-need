@testable import Core
import XCTest

final class SearchStoreTests: XCTestCase {
    var dir: URL!
    var store: SearchStore!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("Search-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let db = try! Database(url: dir.appendingPathComponent("search.sqlite"), migrations: SearchStore.migrations)
        store = SearchStore(database: db)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    func testIndexThenSearch() throws {
        let id = RecordID.generate()
        try store.upsert(kind: .clipboardItem, id: id, text: "the quick brown fox jumps over the lazy dog")
        let hits = try store.search(query: "brown fox", limit: 10)
        XCTAssertEqual(hits.first?.id, id)
    }

    func testUpsertReplacesPreviousText() throws {
        let id = RecordID.generate()
        try store.upsert(kind: .clipboardItem, id: id, text: "first version")
        try store.upsert(kind: .clipboardItem, id: id, text: "second version")
        XCTAssertEqual(try store.search(query: "first", limit: 10).count, 0)
        XCTAssertEqual(try store.search(query: "second", limit: 10).count, 1)
    }

    func testRemoveDropsFromIndex() throws {
        let id = RecordID.generate()
        try store.upsert(kind: .clipboardItem, id: id, text: "to remove")
        try store.remove(kind: .clipboardItem, id: id)
        XCTAssertEqual(try store.search(query: "remove", limit: 10).count, 0)
    }

    func testSearchEscapesFTSSyntaxCharacters() throws {
        let id = RecordID.generate()
        try store.upsert(kind: .clipboardItem, id: id, text: "token with colon: and quote")
        let hits = try store.search(query: "colon:", limit: 10)
        XCTAssertEqual(hits.first?.id, id)
    }

    func testSearchSupportsOffset() throws {
        let first = RecordID.generate()
        let second = RecordID.generate()
        try store.upsert(kind: .clipboardItem, id: first, text: "shared unique")
        try store.upsert(kind: .clipboardItem, id: second, text: "shared unique")

        let firstPage = try store.search(query: "shared", limit: 1, offset: 0)
        let secondPage = try store.search(query: "shared", limit: 1, offset: 1)

        XCTAssertEqual(firstPage.count, 1)
        XCTAssertEqual(secondPage.count, 1)
        XCTAssertNotEqual(firstPage.first?.id, secondPage.first?.id)
    }
}
