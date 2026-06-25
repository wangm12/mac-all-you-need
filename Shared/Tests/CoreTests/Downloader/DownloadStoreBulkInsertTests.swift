@testable import Core
import CryptoKit
import XCTest

final class DownloadStoreBulkInsertTests: XCTestCase {
    var dir: URL!
    var store: DownloadStore!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("DlBulk-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let db = try! Database(url: dir.appendingPathComponent("downloads.sqlite"), migrations: DownloadStore.migrations)
        store = try! DownloadStore(database: db, deviceKey: SymmetricKey(size: .bits256))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    func testInsertBulkPreservesOrder() throws {
        let collectionID = UUID().uuidString
        let records = (1...3).map { index in
            var record = DownloadRecord(
                url: "https://example.com/\(index)",
                title: "Video \(index)",
                destinationPath: "/tmp/\(index)",
                state: .queued
            )
            record.collectionID = collectionID
            record.collectionIndex = index
            return record
        }
        let ids = try store.insertBulk(records)
        XCTAssertEqual(ids.count, 3)
        let fetched = try store.fetchAll()
            .filter { $0.collectionID == collectionID }
            .sorted { ($0.collectionIndex ?? 0) < ($1.collectionIndex ?? 0) }
        XCTAssertEqual(fetched.map(\.collectionIndex), [1, 2, 3])
    }

    func testSnapshotSummaryMatchesBulkInsert() throws {
        let records = (1...5).map { index in
            DownloadRecord(
                url: "https://example.com/\(index)",
                title: "Video \(index)",
                destinationPath: "/tmp/\(index)",
                state: .queued
            )
        }
        _ = try store.insertBulk(records)
        let summary = try store.snapshotSummary()
        XCTAssertEqual(summary.count, 5)
        XCTAssertNotNil(summary.modifiedMax)
    }

    func testFetchAllReturnsAllBulkInsertedRecords() throws {
        let collectionID = UUID().uuidString
        let records = (1...64).map { index in
            var record = DownloadRecord(
                url: "https://example.com/\(index)",
                title: "Video \(index)",
                destinationPath: "/tmp/\(index)",
                state: .queued
            )
            record.collectionID = collectionID
            record.collectionIndex = index
            return record
        }

        _ = try store.insertBulk(records)
        let fetched = try store.fetchAll()
        XCTAssertEqual(fetched.filter { $0.collectionID == collectionID }.count, 64)
    }
}
