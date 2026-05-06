@testable import Core
import CryptoKit
import XCTest

final class DownloadStoreTests: XCTestCase {
    var dir: URL!
    var store: DownloadStore!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("Dl-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let db = try! Database(url: dir.appendingPathComponent("downloads.sqlite"), migrations: DownloadStore.migrations)
        store = try! DownloadStore(database: db, deviceKey: SymmetricKey(size: .bits256))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    func testInsertAndFetch() throws {
        let id = try store.insert(DownloadRecord(
            url: "https://example.com/v.mp4",
            title: "Example",
            destinationPath: "/tmp/v.mp4",
            state: .queued
        ))
        let r = try store.fetch(id: id)
        XCTAssertEqual(r.url, "https://example.com/v.mp4")
        XCTAssertEqual(r.state, .queued)
    }

    func testUpdateState() throws {
        let id = try store.insert(DownloadRecord(url: "u", title: "t", destinationPath: "/tmp/x", state: .queued))
        try store.updateState(id: id, to: .running)
        XCTAssertEqual(try store.fetch(id: id).state, .running)
    }

    func testListByState() throws {
        _ = try store.insert(DownloadRecord(url: "a", title: "a", destinationPath: "/a", state: .running))
        _ = try store.insert(DownloadRecord(url: "b", title: "b", destinationPath: "/b", state: .queued))
        XCTAssertEqual(try store.list(state: .running).count, 1)
    }
}
