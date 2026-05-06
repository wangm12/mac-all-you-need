@testable import Core
import GRDB
import XCTest

final class DatabaseTests: XCTestCase {
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DatabaseTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testOpensInWALMode() throws {
        let url = tempDir.appendingPathComponent("test.sqlite")
        let db = try Database(url: url, migrations: [])
        let mode: String = try db.queue.read { try String.fetchOne($0, sql: "PRAGMA journal_mode") ?? "" }
        XCTAssertEqual(mode.lowercased(), "wal")
    }

    func testRunsMigrationsInOrder() throws {
        let url = tempDir.appendingPathComponent("migrate.sqlite")
        let m1 = Migration(identifier: "001-create-foo") { db in
            try db.create(table: "foo") { t in
                t.column("id", .integer).primaryKey()
            }
        }
        let m2 = Migration(identifier: "002-add-bar") { db in
            try db.alter(table: "foo") { t in
                t.add(column: "bar", .text)
            }
        }
        let db = try Database(url: url, migrations: [m1, m2])
        try db.queue.read { conn in
            let cols = try conn.columns(in: "foo").map(\.name).sorted()
            XCTAssertEqual(cols, ["bar", "id"])
        }
    }
}
