@testable import Core
import CryptoKit
import XCTest

final class CoreIntegrationTests: XCTestCase {
    var dir: URL!
    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("Int-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    func testCaptureTextThenSearchThenLoad() throws {
        let key = SymmetricKey(size: .bits256)
        let device = DeviceID.generate()

        let clipDB = try Database(url: dir.appendingPathComponent("c.sqlite"), migrations: ClipboardStore.migrations)
        let clip = try ClipboardStore(database: clipDB, deviceKey: key, deviceID: device)

        let searchDB = try Database(url: dir.appendingPathComponent("s.sqlite"), migrations: SearchStore.migrations)
        let search = SearchStore(database: searchDB)

        let meta = try clip.append(ClipboardRecord.text("the quick brown fox"))
        try search.upsert(kind: .clipboardItem, id: meta.id, text: "the quick brown fox")

        let hits = try search.search(query: "brown", limit: 10)
        XCTAssertEqual(hits.count, 1)
        let body = try clip.body(for: hits[0].id)
        XCTAssertEqual(body, .text("the quick brown fox"))
    }

    func testBlobAttachedToImageRecord() throws {
        let key = SymmetricKey(size: .bits256)
        let blobs = BlobStore(rootURL: dir.appendingPathComponent("blobs"), key: key)
        let device = DeviceID.generate()
        let clipDB = try Database(url: dir.appendingPathComponent("c.sqlite"), migrations: ClipboardStore.migrations)
        let clip = try ClipboardStore(database: clipDB, deviceKey: key, deviceID: device)

        let pixels = Data(repeating: 0xCC, count: 64 * 64)
        let blobID = try blobs.write(pixels)
        let meta = try clip.append(.image(blobID: blobID, width: 64, height: 64))
        let body = try clip.body(for: meta.id)
        guard case let .image(loadedID, w, h) = body else {
            XCTFail("Expected image record"); return
        }
        XCTAssertEqual(loadedID, blobID)
        XCTAssertEqual([w, h], [64, 64])
        XCTAssertEqual(try blobs.read(id: loadedID), pixels)
    }
}
