@testable import Core
import CryptoKit
import XCTest

final class PinboardStoreTests: XCTestCase {
    var dir: URL!
    var store: PinboardStore!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("Pin-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let db = try! Database(url: dir.appendingPathComponent("pinboards.sqlite"), migrations: PinboardStore.migrations)
        store = PinboardStore(database: db, deviceKey: SymmetricKey(size: .bits256))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    func testCreatePreservesName() throws {
        let p = try store.create(name: "Work")
        XCTAssertEqual(p.name, "Work")
    }

    func testListReturnsSortOrder() throws {
        try store.create(name: "First")
        try store.create(name: "Second")
        let list = try store.list()
        XCTAssertEqual(list.map(\.name), ["First", "Second"])
    }

    func testAddItemInsertsAtIndex() throws {
        let p = try store.create(name: "Board")
        let id1 = RecordID.generate()
        let id2 = RecordID.generate()
        try store.addItem(id1, to: p.id)
        try store.addItem(id2, to: p.id, at: 0)
        let updated = try XCTUnwrap(try store.list().first)
        XCTAssertEqual(updated.itemIDs.first, id2)
    }

    func testRemoveItemOnlyRemovesThatID() throws {
        let p = try store.create(name: "Board")
        let id1 = RecordID.generate()
        let id2 = RecordID.generate()
        try store.addItem(id1, to: p.id)
        try store.addItem(id2, to: p.id)
        try store.removeItem(id1, from: p.id)
        let updated = try XCTUnwrap(try store.list().first)
        XCTAssertFalse(updated.itemIDs.contains(id1))
        XCTAssertTrue(updated.itemIDs.contains(id2))
    }

    func testRenameUpdatesModified() throws {
        let p = try store.create(name: "Old")
        let before = p.modified
        Thread.sleep(forTimeInterval: 0.01)
        try store.rename(id: p.id, to: "New")
        let updated = try XCTUnwrap(try store.list().first)
        XCTAssertEqual(updated.name, "New")
        XCTAssertGreaterThan(updated.modified, before)
    }

    func testDeleteRemovesRow() throws {
        let p = try store.create(name: "ToDelete")
        try store.delete(id: p.id)
        XCTAssertTrue(try store.list().isEmpty)
    }

    func testMutateAppliesChangeAndStampsModified() throws {
        var p = try store.create(name: "Pin")
        let before = p.modified
        Thread.sleep(forTimeInterval: 0.005)
        let id1 = RecordID.generate()
        p = try store.mutate(id: p.id) { $0.itemIDs.append(id1) }
        XCTAssertEqual(p.itemIDs, [id1])
        XCTAssertGreaterThan(p.modified, before)
        let reread = try store.list().first { $0.id == p.id }
        XCTAssertEqual(reread?.itemIDs, [id1])
    }

    func testMutateConcurrentAppendsAreSerializedNotLost() throws {
        let p = try store.create(name: "Race")
        let count = 100
        let queue = DispatchQueue(label: "PinboardStoreTests.race", attributes: .concurrent)
        let group = DispatchGroup()
        for index in 0..<count {
            group.enter()
            queue.async {
                let id = RecordID.generate()
                _ = try? self.store.mutate(id: p.id) { board in
                    // append a unique-per-iteration value so a lost update is detectable
                    board.itemIDs.append(id)
                    _ = index
                }
                group.leave()
            }
        }
        group.wait()
        let final = try store.list().first { $0.id == p.id }!
        XCTAssertEqual(final.itemIDs.count, count,
                       "Atomic mutate must preserve every concurrent append; got \(final.itemIDs.count) of \(count)")
    }
}
