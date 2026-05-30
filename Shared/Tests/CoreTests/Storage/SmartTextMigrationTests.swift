@testable import Core
import CryptoKit
import GRDB
import XCTest

final class SmartTextMigrationTests: XCTestCase {
    private func makeDB() throws -> Core.Database {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SmartTextMig-\(UUID().uuidString)", isDirectory: true)
        return try Core.Database(
            url: tempDir.appendingPathComponent("clipboard.sqlite"),
            migrations: ClipboardStore.migrations
        )
    }

    private func makeStore() throws -> ClipboardStore {
        try ClipboardStore(
            database: try makeDB(),
            deviceKey: SymmetricKey(size: .bits256),
            deviceID: DeviceID.generate()
        )
    }

    func testMigration008AddsColumnsAndIndex() throws {
        let db = try makeDB()
        try db.queue.read { conn in
            let columns = try Row.fetchAll(conn, sql: "PRAGMA table_info(clipboard_records)")
                .compactMap { $0["name"] as String? }
            XCTAssertTrue(columns.contains("detected_type"))
            XCTAssertTrue(columns.contains("ocr_text"))
            XCTAssertTrue(columns.contains("embedding"))

            let indexes = try Row.fetchAll(conn, sql: "PRAGMA index_list(clipboard_records)")
                .compactMap { $0["name"] as String? }
            XCTAssertTrue(indexes.contains("idx_records_detected_type"))
        }
    }

    func testAppendPersistsDetectedTypeJSON() throws {
        let store = try makeStore()
        let json = try Detection(type: .email).encodedJSON()
        let meta = try store.append(.text("user@example.com"), detectedTypeJSON: json)
        XCTAssertEqual(meta.detectedTypeJSON, json)
        let fetched = try XCTUnwrap(store.meta(for: meta.id))
        XCTAssertEqual(fetched.detectedTypeJSON, json)
    }

    func testSetterRoundTrips() throws {
        let store = try makeStore()
        let meta = try store.append(.text("hello"))
        try store.setDetectedType(id: meta.id, json: "{\"type\":\"plain\"}")
        try store.setOCRText(id: meta.id, text: "scanned text")
        let blob = ClipEmbeddingService.encode([1, 2, 3])
        try store.setEmbedding(id: meta.id, blob: blob)

        let fetched = try XCTUnwrap(store.meta(for: meta.id))
        XCTAssertEqual(fetched.detectedTypeJSON, "{\"type\":\"plain\"}")
        XCTAssertEqual(fetched.ocrText, "scanned text")
        XCTAssertEqual(fetched.embedding, blob)
        XCTAssertEqual(ClipEmbeddingService.decode(fetched.embedding ?? Data()), [1, 2, 3])
    }

    func testIdsMissingEmbedding() throws {
        let store = try makeStore()
        let a = try store.append(.text("a"))
        let b = try store.append(.text("b"))
        try store.setEmbedding(id: a.id, blob: ClipEmbeddingService.encode([1]))

        let missing = try store.idsMissingEmbedding(limit: 10)
        XCTAssertTrue(missing.contains(b.id))
        XCTAssertFalse(missing.contains(a.id))
    }

    func testIdsMissingOCROnlyImages() throws {
        let store = try makeStore()
        _ = try store.append(.text("plain text"))
        let img = try store.append(.image(blobID: "blob1", width: 10, height: 10))

        let missing = try store.idsMissingOCR(limit: 10)
        XCTAssertEqual(missing, [img.id])
    }
}

