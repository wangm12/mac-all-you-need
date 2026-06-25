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

    func testSnapshotSummaryTracksCountAndLatestModified() throws {
        let id = try store.insert(DownloadRecord(
            url: "https://example.com/v.mp4",
            title: "Example",
            destinationPath: "/tmp/v.mp4",
            state: .queued
        ))
        let initial = try store.snapshotSummary()
        XCTAssertEqual(initial.count, 1)
        XCTAssertNotNil(initial.modifiedMax)

        try store.updateState(id: id, to: .running)
        let updated = try store.snapshotSummary()
        XCTAssertEqual(updated.count, 1)
        XCTAssertNotNil(updated.modifiedMax)
        XCTAssertEqual(try store.fetch(id: id).state, .running)
    }

    func testDeleteRemovesRecordAndUpdatesSnapshotSummary() throws {
        let id = try store.insert(DownloadRecord(
            url: "https://example.com/v.mp4",
            title: "Example",
            destinationPath: "/tmp/v.mp4",
            state: .queued
        ))

        XCTAssertEqual(try store.snapshotSummary().count, 1)
        try store.delete(id: id)
        XCTAssertEqual(try store.snapshotSummary().count, 0)
        XCTAssertThrowsError(try store.fetch(id: id))
    }

    func testDeleteManyRemovesAllRecords() throws {
        let first = try store.insert(DownloadRecord(
            url: "https://example.com/1.mp4",
            title: "First",
            destinationPath: "/tmp/1.mp4",
            state: .queued
        ))
        let second = try store.insert(DownloadRecord(
            url: "https://example.com/2.mp4",
            title: "Second",
            destinationPath: "/tmp/2.mp4",
            state: .running
        ))

        try store.delete(ids: [first, second])

        XCTAssertEqual(try store.snapshotSummary().count, 0)
        XCTAssertThrowsError(try store.fetch(id: first))
        XCTAssertThrowsError(try store.fetch(id: second))
    }

    func testRecordsInCollectionReturnsOnlyMatchingRows() throws {
        var first = DownloadRecord(
            url: "https://example.com/1.mp4",
            title: "First",
            destinationPath: "/tmp/1.mp4",
            state: .queued
        )
        first.collectionID = "collection-a"
        let firstID = try store.insert(first)

        var second = DownloadRecord(
            url: "https://example.com/2.mp4",
            title: "Second",
            destinationPath: "/tmp/2.mp4",
            state: .running
        )
        second.collectionID = "collection-b"
        _ = try store.insert(second)

        let records = try store.records(inCollection: "collection-a")

        XCTAssertEqual(records.map(\.id), [firstID])
        XCTAssertEqual(records.first?.collectionID, "collection-a")
    }

    func testCountInCollectionUsesCollectionFilter() throws {
        var first = DownloadRecord(
            url: "https://example.com/1.mp4",
            title: "First",
            destinationPath: "/tmp/1.mp4",
            state: .queued
        )
        first.collectionID = "collection-a"
        _ = try store.insert(first)

        var second = DownloadRecord(
            url: "https://example.com/2.mp4",
            title: "Second",
            destinationPath: "/tmp/2.mp4",
            state: .running
        )
        second.collectionID = "collection-b"
        _ = try store.insert(second)

        XCTAssertEqual(try store.count(inCollection: "collection-a"), 1)
        XCTAssertEqual(try store.count(inCollection: "collection-b"), 1)
        XCTAssertEqual(try store.count(inCollection: "missing"), 0)
    }
}
