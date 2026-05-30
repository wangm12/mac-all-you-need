import Foundation
import GRDB

/// GRDB-backed store for Finder folder visit history.
///
/// Folder paths are stored as **plaintext**: a list of folders the user has opened
/// in Finder is not sensitive content (the folder contents are never read), and
/// plaintext storage keeps the FinderSync extension's read path simple. This is an
/// intentional deviation from the encrypted `ClipboardStore` / `DownloadStore`.
public final class FolderHistoryStore {
    private let db: Database
    private let log = Logging.logger(for: "folder-history", category: "store")

    public static let migrations: [Migration] = [
        Migration(identifier: "001-folder-history") { conn in
            try conn.execute(sql: """
                CREATE TABLE IF NOT EXISTS folder_history (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    path TEXT NOT NULL UNIQUE,
                    visited_at REAL NOT NULL,
                    visit_count INTEGER NOT NULL DEFAULT 1,
                    is_pinned INTEGER NOT NULL DEFAULT 0,
                    icon_data BLOB
                );
                CREATE INDEX IF NOT EXISTS idx_folder_history_visited_at
                    ON folder_history(visited_at DESC);
            """)
        },
    ]

    /// Opens (or creates) a folder-history database at `url`.
    public init(url: URL) throws {
        db = try Database(url: url, migrations: Self.migrations)
    }

    /// Insert a new visit or update the existing row's visit time + count.
    @discardableResult
    public func upsert(path: String, now: Date = Date()) throws -> FolderHistoryRow {
        try db.queue.write { conn in
            let visited = now.timeIntervalSince1970
            if let existing = try Row.fetchOne(
                conn,
                sql: "SELECT id, visit_count, is_pinned, icon_data FROM folder_history WHERE path = ?",
                arguments: [path]
            ) {
                let id: Int64 = existing["id"]
                let count: Int = existing["visit_count"]
                let pinned: Bool = (existing["is_pinned"] as Int) != 0
                let icon: Data? = existing["icon_data"]
                try conn.execute(
                    sql: "UPDATE folder_history SET visited_at = ?, visit_count = ? WHERE id = ?",
                    arguments: [visited, count + 1, id]
                )
                return FolderHistoryRow(
                    id: id, path: path, visitedAt: now,
                    visitCount: count + 1, isPinned: pinned, iconData: icon
                )
            } else {
                try conn.execute(
                    sql: "INSERT INTO folder_history (path, visited_at, visit_count, is_pinned) VALUES (?, ?, 1, 0)",
                    arguments: [path, visited]
                )
                let id = conn.lastInsertedRowID
                return FolderHistoryRow(id: id, path: path, visitedAt: now, visitCount: 1, isPinned: false)
            }
        }
    }

    /// Returns rows sorted pinned-first, then by most-recent visit.
    public func list(limit: Int) throws -> [FolderHistoryRow] {
        try db.queue.read { conn in
            let rows = try Row.fetchAll(
                conn,
                sql: """
                    SELECT id, path, visited_at, visit_count, is_pinned, icon_data
                    FROM folder_history
                    ORDER BY is_pinned DESC, visited_at DESC
                    LIMIT ?
                """,
                arguments: [limit]
            )
            return rows.map(Self.makeRow)
        }
    }

    public func pin(id: Int64, pinned: Bool) throws {
        try db.queue.write { conn in
            try conn.execute(
                sql: "UPDATE folder_history SET is_pinned = ? WHERE id = ?",
                arguments: [pinned ? 1 : 0, id]
            )
        }
    }

    public func setIcon(id: Int64, iconData: Data?) throws {
        try db.queue.write { conn in
            try conn.execute(
                sql: "UPDATE folder_history SET icon_data = ? WHERE id = ?",
                arguments: [iconData, id]
            )
        }
    }

    public func remove(id: Int64) throws {
        try db.queue.write { conn in
            try conn.execute(sql: "DELETE FROM folder_history WHERE id = ?", arguments: [id])
        }
    }

    /// Evicts the oldest unpinned rows so that at most `maxCount` unpinned rows remain.
    public func evictStale(maxCount: Int) throws {
        try db.queue.write { conn in
            let rows = try Row.fetchAll(
                conn,
                sql: "SELECT id, is_pinned FROM folder_history ORDER BY visited_at DESC"
            )
            let tuples: [(id: Int64, isPinned: Bool)] = rows.map {
                (id: $0["id"], isPinned: ($0["is_pinned"] as Int) != 0)
            }
            let evict = FolderHistoryRetention.evictIDs(rows: tuples, maxCount: maxCount)
            guard !evict.isEmpty else { return }
            let placeholders = evict.map { _ in "?" }.joined(separator: ",")
            try conn.execute(
                sql: "DELETE FROM folder_history WHERE id IN (\(placeholders))",
                arguments: StatementArguments(evict)
            )
        }
    }

    public func clear() throws {
        try db.queue.write { conn in
            try conn.execute(sql: "DELETE FROM folder_history")
        }
    }

    private static func makeRow(_ row: Row) -> FolderHistoryRow {
        FolderHistoryRow(
            id: row["id"],
            path: row["path"],
            visitedAt: Date(timeIntervalSince1970: row["visited_at"]),
            visitCount: row["visit_count"],
            isPinned: (row["is_pinned"] as Int) != 0,
            iconData: row["icon_data"]
        )
    }
}
