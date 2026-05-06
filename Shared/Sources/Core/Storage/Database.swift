import Foundation
import GRDB

public final class Database {
    public let queue: DatabaseQueue
    private let log = Logging.logger(for: "storage", category: "database")

    public init(url: URL, migrations: [Migration]) throws {
        var config = Configuration()
        config.prepareDatabase { conn in
            try conn.execute(sql: "PRAGMA journal_mode = WAL")
            try conn.execute(sql: "PRAGMA synchronous = NORMAL")
            try conn.execute(sql: "PRAGMA foreign_keys = ON")
            try conn.execute(sql: "PRAGMA busy_timeout = 5000")
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        queue = try DatabaseQueue(path: url.path, configuration: config)

        var migrator = DatabaseMigrator()
        for m in migrations {
            migrator.registerMigration(m.identifier, migrate: m.migrate)
        }
        try migrator.migrate(queue)
        log.info("Opened database at \(url.path, privacy: .public) with \(migrations.count) migrations")
    }
}
