@testable import Core
import CryptoKit
import XCTest

final class RetentionPolicyTests: XCTestCase {
    var dir: URL!
    var clip: ClipboardStore!
    var pinboards: PinboardStore!
    var blobs: BlobStore!

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
        try policy.enforceItemCap(store: clip, blobs: blobs, protectedIDs: protected)
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
        try policy.enforceItemCap(store: clip, blobs: blobs, protectedIDs: protected)

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
        try policy.enforceItemCap(store: clip, blobs: blobs, protectedIDs: [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: blobs.encryptedURL(id: blobID).path))
        XCTAssertNil(try clip.list(limit: 10).first { $0.id == imageMeta.id })
    }

    func testMaxAgeEvictsOnlyOlderThanCutoff() throws {
        let old = try clip.append(.text("old"))
        Thread.sleep(forTimeInterval: 0.02)
        let fresh = try clip.append(.text("fresh"))
        let now = Date()
        let policy = RetentionPolicy(maxItems: nil, maxAgeSeconds: 0.01, maxImageBytes: nil)
        try policy.enforceMaxAge(store: clip, blobs: blobs, protectedIDs: [], now: now)

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
        try policy.enforceImageCap(store: clip, blobs: blobs, protectedIDs: [])

        let ids = Set(try clip.list(limit: 10).map(\.id))
        XCTAssertFalse(ids.contains(first.id))
        XCTAssertTrue(ids.contains(second.id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: blobs.encryptedURL(id: firstBlob).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: blobs.encryptedURL(id: secondBlob).path))
    }
}
