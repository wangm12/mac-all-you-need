@testable import Core
import GRDB
import XCTest

final class ClipboardStoreVoiceMigrationTests: XCTestCase {
    func testVoiceMigrationCreatesFuturePlanTablesColumnsAndIndex() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipVoiceMigration-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let db = try Database(
            url: tempDir.appendingPathComponent("clipboard.sqlite"),
            migrations: ClipboardStore.migrations
        )

        try db.queue.read { conn in
            XCTAssertTrue(try conn.tableExists("voice_transcripts"))
            XCTAssertTrue(try conn.tableExists("audio_archives"))
            XCTAssertTrue(try conn.tableExists("voice_dictionary"))

            // Migration 005-personalization drops app_profiles and creates the new tables.
            XCTAssertFalse(try conn.tableExists("app_profiles"))
            XCTAssertTrue(try conn.tableExists("voice_personalization_contexts"))
            XCTAssertTrue(try conn.tableExists("voice_personalization_samples"))

            let columns = try Row.fetchAll(conn, sql: "PRAGMA table_info(clipboard_records)")
                .compactMap { $0["name"] as String? }
            XCTAssertTrue(columns.contains("capture_origin"))
            XCTAssertTrue(columns.contains("voice_transcript_id"))

            let indexes = try Row.fetchAll(conn, sql: "PRAGMA index_list(clipboard_records)")
                .compactMap { $0["name"] as String? }
            XCTAssertTrue(indexes.contains("idx_clipboard_records_capture_origin"))

            let sampleIndexes = try Row.fetchAll(conn, sql: "PRAGMA index_list(voice_personalization_samples)")
                .compactMap { $0["name"] as String? }
            XCTAssertTrue(sampleIndexes.contains("idx_personalization_samples_ctx_obs"))
            XCTAssertTrue(sampleIndexes.contains("idx_personalization_samples_expires"))
            XCTAssertTrue(sampleIndexes.contains("idx_personalization_samples_unsummarized"))
        }
    }
}
