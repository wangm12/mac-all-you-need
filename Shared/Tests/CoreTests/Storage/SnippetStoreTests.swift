@testable import Core
import CryptoKit
import XCTest

final class SnippetStoreTests: XCTestCase {
    var dir: URL!
    var store: SnippetStore!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("Snip-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let db = try! Database(url: dir.appendingPathComponent("snippets.sqlite"), migrations: SnippetStore.migrations)
        store = SnippetStore(database: db, deviceKey: SymmetricKey(size: .bits256))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    func testInsertAndListRoundTripEncryptedBody() throws {
        try store.create(name: "Sig", body: "Mingjie Wang", trigger: ";sig")
        let list = try store.list()
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list.first?.body, "Mingjie Wang")
    }

    func testDuplicateTriggerThrows() throws {
        try store.create(name: "A", body: "aaa", trigger: ";dup")
        XCTAssertThrowsError(try store.create(name: "B", body: "bbb", trigger: ";dup"))
    }

    func testNilTriggerAllowedForMultiple() throws {
        try store.create(name: "No Trigger 1", body: "body1", trigger: nil)
        try store.create(name: "No Trigger 2", body: "body2", trigger: nil)
        XCTAssertEqual(try store.list().count, 2)
    }

    func testFindByTriggerReturnsMatchingBody() throws {
        try store.create(name: "Email", body: "hi@example.com", trigger: ";email")
        let found = try store.find(trigger: ";email")
        XCTAssertEqual(found?.body, "hi@example.com")
    }

    func testDeleteRemovesRow() throws {
        let s = try store.create(name: "Temp", body: "x")
        try store.delete(id: s.id)
        XCTAssertTrue(try store.list().isEmpty)
    }
}
