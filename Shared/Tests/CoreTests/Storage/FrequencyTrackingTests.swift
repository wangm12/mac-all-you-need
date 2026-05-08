@testable import Core
import CryptoKit
import XCTest

final class FrequencyTrackingTests: XCTestCase {
    var store: ClipboardStore!
    var dir: URL!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Freq-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let db = try! Database(url: dir.appendingPathComponent("c.sqlite"), migrations: ClipboardStore.migrations)
        store = try! ClipboardStore(
            database: db,
            deviceKey: SymmetricKey(size: .bits256),
            deviceID: DeviceID.generate()
        )
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    func testBumpFrequencyIncrementsAndSetsLastAccessed() throws {
        let item = try store.append(.text("hi"))
        try store.bumpFrequency(id: item.id)
        try store.bumpFrequency(id: item.id)
        let meta = try XCTUnwrap(try store.list(limit: 10).first)
        XCTAssertEqual(meta.frequency, 2)
        XCTAssertNotNil(meta.lastAccessed)
    }

    func testRecentByFrequencyOrders() throws {
        let a = try store.append(.text("a"))
        let b = try store.append(.text("b"))
        try store.bumpFrequency(id: a.id)
        try store.bumpFrequency(id: a.id)
        try store.bumpFrequency(id: b.id)
        let metas = try store.recentByFrequency(limit: 10)
        XCTAssertEqual(metas.first?.id, a.id)
    }

    func testRecentByLastAccessedOrders() throws {
        let a = try store.append(.text("a"))
        let b = try store.append(.text("b"))
        try store.bumpFrequency(id: a.id)
        Thread.sleep(forTimeInterval: 0.005)
        try store.bumpFrequency(id: b.id)
        let metas = try store.recentByLastAccessed(limit: 10)
        XCTAssertEqual(metas.first?.id, b.id)
    }
}
