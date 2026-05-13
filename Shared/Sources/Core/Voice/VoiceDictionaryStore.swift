import Foundation
import GRDB

public final class VoiceDictionaryStore: @unchecked Sendable {
    private let db: Database

    public init(database: Database) {
        db = database
    }

    @discardableResult
    public func upsert(phrase: String, replacement: String) throws -> VoiceDictionaryEntry {
        let phrase = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacement = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phrase.isEmpty else { throw VoiceDictionaryStoreError.emptyPhrase }

        let id = try db.queue.write { conn -> String in
            if let row = try Row.fetchOne(
                conn,
                sql: "SELECT id FROM voice_dictionary WHERE phrase = ? ORDER BY updated_at DESC LIMIT 1",
                arguments: [phrase]
            ) {
                let id: String = row["id"]
                try conn.execute(sql: """
                    UPDATE voice_dictionary
                    SET replacement = ?, updated_at = ?
                    WHERE id = ?
                """, arguments: [
                    replacement,
                    Self.millis(Date()),
                    id
                ])
                return id
            }

            let id = UUID().uuidString
            let now = Self.millis(Date())
            try conn.execute(sql: """
                INSERT INTO voice_dictionary (
                    id, phrase, replacement, created_at, updated_at
                )
                VALUES (?, ?, ?, ?, ?)
            """, arguments: [
                id,
                phrase,
                replacement,
                now,
                now
            ])
            return id
        }

        return try fetch(id: id) ?? VoiceDictionaryEntry(
            id: id,
            phrase: phrase,
            replacement: replacement,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    public func list() throws -> [VoiceDictionaryEntry] {
        try db.queue.read { conn in
            try Row.fetchAll(conn, sql: """
                SELECT id, phrase, replacement, created_at, updated_at
                FROM voice_dictionary
                ORDER BY updated_at DESC, phrase ASC
            """).map(Self.entry(from:))
        }
    }

    public func delete(id: String) throws {
        try db.queue.write { conn in
            try conn.execute(sql: "DELETE FROM voice_dictionary WHERE id = ?", arguments: [id])
        }
    }

    private func fetch(id: String) throws -> VoiceDictionaryEntry? {
        try db.queue.read { conn in
            try Row.fetchOne(conn, sql: """
                SELECT id, phrase, replacement, created_at, updated_at
                FROM voice_dictionary
                WHERE id = ?
            """, arguments: [id]).map(Self.entry(from:))
        }
    }

    private static func entry(from row: Row) -> VoiceDictionaryEntry {
        VoiceDictionaryEntry(
            id: row["id"],
            phrase: row["phrase"],
            replacement: row["replacement"],
            createdAt: date(milliseconds: row["created_at"] as Int64),
            updatedAt: date(milliseconds: row["updated_at"] as Int64)
        )
    }

    private static func millis(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    private static func date(milliseconds: Int64) -> Date {
        Date(timeIntervalSince1970: Double(milliseconds) / 1000)
    }
}

public enum VoiceDictionaryStoreError: Error, Equatable {
    case emptyPhrase
}
