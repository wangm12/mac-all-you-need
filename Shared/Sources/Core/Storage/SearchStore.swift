import Foundation
import GRDB

public struct SearchHit: Equatable {
    public let kind: RecordKind
    public let id: RecordID
    public let snippet: String
}

public final class SearchStore {
    private let db: Database
    private let log = Logging.logger(for: "search", category: "fts")

    public init(database: Database) {
        db = database
    }

    public static let migrations: [Migration] = [
        Migration(identifier: "001-fts5-index") { conn in
            try conn.execute(sql: """
                CREATE VIRTUAL TABLE IF NOT EXISTS search_index USING fts5(
                    kind UNINDEXED,
                    record_id UNINDEXED,
                    content,
                    tokenize = 'porter unicode61'
                );
                CREATE TABLE IF NOT EXISTS search_keys (
                    kind TEXT NOT NULL,
                    record_id TEXT NOT NULL,
                    rowid INTEGER NOT NULL,
                    PRIMARY KEY (kind, record_id)
                );
            """)
        }
    ]

    public func upsert(kind: RecordKind, id: RecordID, text: String) throws {
        try db.queue.write { conn in
            if let existing = try Row.fetchOne(
                conn,
                sql: "SELECT rowid FROM search_keys WHERE kind = ? AND record_id = ?",
                arguments: [kind.rawValue, id.rawValue]
            ) {
                let rowid: Int64 = existing["rowid"]
                try conn.execute(sql: "DELETE FROM search_index WHERE rowid = ?", arguments: [rowid])
                try conn.execute(sql: "DELETE FROM search_keys WHERE rowid = ?", arguments: [rowid])
            }
            try conn.execute(
                sql: "INSERT INTO search_index(kind, record_id, content) VALUES (?, ?, ?)",
                arguments: [kind.rawValue, id.rawValue, text]
            )
            let rowid = conn.lastInsertedRowID
            try conn.execute(
                sql: "INSERT INTO search_keys(kind, record_id, rowid) VALUES (?, ?, ?)",
                arguments: [kind.rawValue, id.rawValue, rowid]
            )
        }
    }

    public func remove(kind: RecordKind, id: RecordID) throws {
        try db.queue.write { conn in
            guard let existing = try Row.fetchOne(
                conn,
                sql: "SELECT rowid FROM search_keys WHERE kind = ? AND record_id = ?",
                arguments: [kind.rawValue, id.rawValue]
            ) else { return }
            let rowid: Int64 = existing["rowid"]
            try conn.execute(sql: "DELETE FROM search_index WHERE rowid = ?", arguments: [rowid])
            try conn.execute(sql: "DELETE FROM search_keys WHERE rowid = ?", arguments: [rowid])
        }
    }

    public func search(query: String, limit: Int) throws -> [SearchHit] {
        let ftsQuery = Self.ftsQuery(for: query)
        guard !ftsQuery.isEmpty else { return [] }
        return try db.queue.read { conn in
            try Row.fetchAll(conn, sql: """
                SELECT kind, record_id, snippet(search_index, 2, '<', '>', '…', 12) AS snip
                FROM search_index WHERE search_index MATCH ? ORDER BY rank LIMIT ?
            """, arguments: [ftsQuery, limit]).compactMap { row in
                guard let kind = RecordKind(rawValue: row["kind"]),
                      let id = RecordID(rawValue: row["record_id"]) else { return nil }
                return SearchHit(kind: kind, id: id, snippet: row["snip"])
            }
        }
    }

    private static func ftsQuery(for raw: String) -> String {
        raw.split(whereSeparator: \.isWhitespace)
            .map { token in
                let escaped = token.replacingOccurrences(of: "\"", with: "\"\"")
                return "\"\(escaped)\""
            }
            .joined(separator: " ")
    }
}
