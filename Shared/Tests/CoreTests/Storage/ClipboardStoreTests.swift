@testable import Core
import CryptoKit
import XCTest

final class ClipboardStoreTests: XCTestCase {
    var tempDir: URL!
    var store: ClipboardStore!
    var key: SymmetricKey!
    let device = DeviceID.generate()

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipStoreTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let db = try! Database(
            url: tempDir.appendingPathComponent("clipboard.sqlite"),
            migrations: ClipboardStore.migrations
        )
        key = SymmetricKey(size: .bits256)
        store = try! ClipboardStore(database: db, deviceKey: key, deviceID: device)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testAppendThenList() throws {
        let r = try store.append(ClipboardRecord.text("hello"))
        let items = try store.list(limit: 10)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.id, r.id)
    }

    func testListReturnsNewestFirst() throws {
        let a = try store.append(ClipboardRecord.text("a"))
        Thread.sleep(forTimeInterval: 0.002)
        let b = try store.append(ClipboardRecord.text("b"))
        let items = try store.list(limit: 10)
        XCTAssertEqual(items.map(\.id), [b.id, a.id])
    }

    func testListSupportsOffset() throws {
        let a = try store.append(ClipboardRecord.text("a"))
        Thread.sleep(forTimeInterval: 0.002)
        let b = try store.append(ClipboardRecord.text("b"))
        let items = try store.list(limit: 1, offset: 1)
        XCTAssertEqual(items.map(\.id), [a.id])
        XCTAssertNotEqual(items.first?.id, b.id)
    }

    func testMetasForIDsPreservesRequestedOrder() throws {
        let a = try store.append(ClipboardRecord.text("a"))
        let b = try store.append(ClipboardRecord.text("b"))
        let items = try store.metas(for: [a.id, b.id])
        XCTAssertEqual(items.map(\.id), [a.id, b.id])
    }

    func testLamportClockIncrementsByOne() throws {
        let a = try store.append(ClipboardRecord.text("a"))
        let b = try store.append(ClipboardRecord.text("b"))
        XCTAssertEqual(b.lamport, a.lamport + 1)
    }

    func testDecryptedContentMatches() throws {
        _ = try store.append(ClipboardRecord.text("payload"))
        let items = try store.list(limit: 10)
        let body = try store.body(for: items[0].id)
        XCTAssertEqual(body, .text("payload"))
    }

    func testDeleteRemovesItem() throws {
        let r = try store.append(ClipboardRecord.text("x"))
        try store.delete(id: r.id)
        XCTAssertEqual(try store.list(limit: 10).count, 0)
    }

    func testWrongKeyFailsToDecrypt() throws {
        _ = try store.append(ClipboardRecord.text("secret"))
        let items = try store.list(limit: 10)
        let other = try ClipboardStore(
            database: Database(url: tempDir.appendingPathComponent("clipboard.sqlite"), migrations: []),
            deviceKey: SymmetricKey(size: .bits256),
            deviceID: device
        )
        XCTAssertThrowsError(try other.body(for: items[0].id))
    }
}
