@testable import Core
import GRDB
import XCTest

final class MigrationsTests: XCTestCase {
    func testMigration002AddsFrequencyAndLastAccessed() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Mig-\(UUID()).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        _ = try Database(url: url, migrations: ClipboardStore.migrations)
        let queue = try DatabaseQueue(path: url.path)
        let columns = try queue.read { conn in
            try Row.fetchAll(conn, sql: "PRAGMA table_info(clipboard_records)")
                .compactMap { $0["name"] as String? }
        }
        XCTAssertTrue(columns.contains("frequency"))
        XCTAssertTrue(columns.contains("last_accessed"))
    }

    func testMigration002IsIdempotent() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Mig2-\(UUID()).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try Database(url: url, migrations: ClipboardStore.migrations)
        _ = try Database(url: url, migrations: ClipboardStore.migrations)
    }
}
