@testable import Core
import CryptoKit
import XCTest

final class RetentionPolicyTests: XCTestCase {
    var dir: URL!
    var clip: ClipboardStore!
    var pinboards: PinboardStore!
    var blobs: BlobStore!
    var search: SearchStore!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Ret-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let key = SymmetricKey(size: .bits256)
        let cdb = try! Database(url: dir.appendingPathComponent("c.sqlite"), migrations: ClipboardStore.migrations)
        clip = try! ClipboardStore(database: cdb, deviceKey: key, deviceID: DeviceID.generate())
        let pdb = try! Database(url: dir.appendingPathComponent("p.sqlite"), migrations: PinboardStore.migrations)
        pinboards = PinboardStore(database: pdb, deviceKey: key)
        blobs = BlobStore(rootURL: dir.appendingPathComponent("blobs"), key: key)
        let sdb = try! Database(url: dir.appendingPathComponent("s.sqlite"), migrations: SearchStore.migrations)
        search = SearchStore(database: sdb)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    func testEvictsOldestNonPinnedWhenOverMaxItems() throws {
        var ids: [RecordID] = []
        for _ in 0..<5 {
            ids.append(try clip.append(.text("x")).id)
            Thread.sleep(forTimeInterval: 0.002)
        }
        let policy = RetentionPolicy(maxItems: 3, maxAgeSeconds: nil, maxImageBytes: nil)
        let protected = try PinboardStore.protectedIDs(from: pinboards)
        try policy.enforceItemCap(store: clip, blobs: blobs, search: search, protectedIDs: protected)
        let surviving = try clip.list(limit: 10).map(\.id)
        XCTAssertEqual(surviving.count, 3)
        XCTAssertEqual(Set(surviving), Set(ids.suffix(3)))
    }

    func testProtectedItemsDoNotCountAgainstCap() throws {
        var pinnedIDs: [RecordID] = []
        for _ in 0..<2 {
            pinnedIDs.append(try clip.append(.text("p")).id)
            Thread.sleep(forTimeInterval: 0.002)
        }
        var casualIDs: [RecordID] = []
        for _ in 0..<5 {
            casualIDs.append(try clip.append(.text("c")).id)
            Thread.sleep(forTimeInterval: 0.002)
        }

        var pinboard = try pinboards.create(name: "__pinned__")
        pinboard.itemIDs = pinnedIDs
        try pinboards.update(pinboard)

        let policy = RetentionPolicy(maxItems: 3, maxAgeSeconds: nil, maxImageBytes: nil)
        let protected = try PinboardStore.protectedIDs(from: pinboards)
        try policy.enforceItemCap(store: clip, blobs: blobs, search: search, protectedIDs: protected)

        let surviving = Set(try clip.list(limit: 10).map(\.id))
        XCTAssertTrue(pinnedIDs.allSatisfy { surviving.contains($0) })
        let nonProtectedSurvivors = surviving.subtracting(pinnedIDs)
        XCTAssertEqual(nonProtectedSurvivors.count, 3)
        XCTAssertEqual(nonProtectedSurvivors, Set(casualIDs.suffix(3)))
    }

    func testImageEvictionAlsoDeletesBlob() throws {
        let blobID = try blobs.write(Data(repeating: 1, count: 1_000))
        let imageMeta = try clip.append(.image(blobID: blobID, width: 32, height: 32))
        let policy = RetentionPolicy(maxItems: 0, maxAgeSeconds: nil, maxImageBytes: nil)
        try policy.enforceItemCap(store: clip, blobs: blobs, search: search, protectedIDs: [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: blobs.encryptedURL(id: blobID).path))
        XCTAssertNil(try clip.list(limit: 10).first { $0.id == imageMeta.id })
    }

    func testMaxAgeEvictsOnlyOlderThanCutoff() throws {
        let old = try clip.append(.text("old"))
        Thread.sleep(forTimeInterval: 0.02)
        let fresh = try clip.append(.text("fresh"))
        let now = Date()
        let policy = RetentionPolicy(maxItems: nil, maxAgeSeconds: 0.01, maxImageBytes: nil)
        try policy.enforceMaxAge(store: clip, blobs: blobs, search: search, protectedIDs: [], now: now)

        let ids = Set(try clip.list(limit: 10).map(\.id))
        XCTAssertFalse(ids.contains(old.id))
        XCTAssertTrue(ids.contains(fresh.id))
    }

    func testImageCapEvictsOldestImageUntilUnderCap() throws {
        let firstBlob = try blobs.write(Data(repeating: 0xAA, count: 1_200))
        let first = try clip.append(.image(blobID: firstBlob, width: 10, height: 10))
        Thread.sleep(forTimeInterval: 0.01)
        let secondBlob = try blobs.write(Data(repeating: 0xBB, count: 1_200))
        let second = try clip.append(.image(blobID: secondBlob, width: 10, height: 10))

        let policy = RetentionPolicy(maxItems: nil, maxAgeSeconds: nil, maxImageBytes: 1_600)
        try policy.enforceImageCap(store: clip, blobs: blobs, search: search, protectedIDs: [])

        let ids = Set(try clip.list(limit: 10).map(\.id))
        XCTAssertFalse(ids.contains(first.id))
        XCTAssertTrue(ids.contains(second.id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: blobs.encryptedURL(id: firstBlob).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: blobs.encryptedURL(id: secondBlob).path))
    }

    func testRetentionRemovesFTSIndexEntriesForEvictedRecords() throws {
        let stale = try clip.append(.text("alpha bravo"))
        try search.upsert(kind: .clipboardItem, id: stale.id, text: "alpha bravo")
        Thread.sleep(forTimeInterval: 0.005)
        let kept = try clip.append(.text("charlie delta"))
        try search.upsert(kind: .clipboardItem, id: kept.id, text: "charlie delta")

        XCTAssertEqual(try search.search(query: "alpha", limit: 5).count, 1)

        let policy = RetentionPolicy(maxItems: 1, maxAgeSeconds: nil, maxImageBytes: nil)
        try policy.enforceItemCap(store: clip, blobs: blobs, search: search, protectedIDs: [])

        XCTAssertNil(try clip.list(limit: 10).first { $0.id == stale.id })
        XCTAssertEqual(try search.search(query: "alpha", limit: 5).count, 0,
                       "FTS index must drop the row for an evicted record")
        XCTAssertEqual(try search.search(query: "charlie", limit: 5).first?.id, kept.id)
    }

    func testMaxAgeRemovesFTSIndexEntries() throws {
        let old = try clip.append(.text("hello"))
        try search.upsert(kind: .clipboardItem, id: old.id, text: "hello")
        Thread.sleep(forTimeInterval: 0.02)
        let fresh = try clip.append(.text("world"))
        try search.upsert(kind: .clipboardItem, id: fresh.id, text: "world")

        let policy = RetentionPolicy(maxItems: nil, maxAgeSeconds: 0.01, maxImageBytes: nil)
        try policy.enforceMaxAge(store: clip, blobs: blobs, search: search, protectedIDs: [], now: Date())

        XCTAssertEqual(try search.search(query: "hello", limit: 5).count, 0)
        XCTAssertEqual(try search.search(query: "world", limit: 5).first?.id, fresh.id)
    }

    func testImageCapRemovesFTSIndexEntries() throws {
        let firstBlob = try blobs.write(Data(repeating: 0xAA, count: 1_200))
        let first = try clip.append(.image(blobID: firstBlob, width: 10, height: 10))
        try search.upsert(kind: .clipboardItem, id: first.id, text: "ocr first text")
        Thread.sleep(forTimeInterval: 0.01)
        let secondBlob = try blobs.write(Data(repeating: 0xBB, count: 1_200))
        let second = try clip.append(.image(blobID: secondBlob, width: 10, height: 10))
        try search.upsert(kind: .clipboardItem, id: second.id, text: "ocr second text")

        let policy = RetentionPolicy(maxItems: nil, maxAgeSeconds: nil, maxImageBytes: 1_600)
        try policy.enforceImageCap(store: clip, blobs: blobs, search: search, protectedIDs: [])

        XCTAssertEqual(try search.search(query: "first", limit: 5).count, 0)
        XCTAssertEqual(try search.search(query: "second", limit: 5).first?.id, second.id)
    }
}
