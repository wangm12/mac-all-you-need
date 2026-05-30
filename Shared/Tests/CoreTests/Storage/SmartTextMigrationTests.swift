@testable import Core
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
}
