import Foundation
import GRDB

public final class VoiceDictionarySuggestionStore: @unchecked Sendable {
    private let db: Database

    public init(database: Database) {
        db = database
    }

    /// Returns true if a non-pending (accepted or dismissed) suggestion exists for this normKey.
    public func existsNonPending(normKey: String) throws -> Bool {
        try db.queue.read { conn in
            let row = try Row.fetchOne(conn, sql: """
                SELECT COUNT(*) AS n FROM voice_dictionary_suggestions
                WHERE norm_key = ? AND status != 'pending'
            """, arguments: [normKey])
            return (row?["n"] as? Int64 ?? 0) > 0
        }
    }

    /// Inserts a new pending candidate or increments occurrences on an existing pending one.
    public func recordCandidate(
        phrase: String,
        replacement: String,
        sampleID: String,
        now: Date
    ) throws {
        let normKey = Self.makeNormKey(phrase: phrase)
        let nowMs = Self.millis(now)
        try db.queue.write { conn in
            if let row = try Row.fetchOne(conn, sql: """
                SELECT id, occurrences FROM voice_dictionary_suggestions
                WHERE norm_key = ? AND status = 'pending'
                LIMIT 1
            """, arguments: [normKey]) {
                let id: String = row["id"]
                let occ: Int64 = row["occurrences"]
                try conn.execute(sql: """
                    UPDATE voice_dictionary_suggestions
                    SET occurrences = ?, updated_at = ?
                    WHERE id = ?
                """, arguments: [occ + 1, nowMs, id])
            } else {
                let id = UUID().uuidString
                try conn.execute(sql: """
                    INSERT INTO voice_dictionary_suggestions
                        (id, phrase, replacement, norm_key, occurrences, status, first_seen_at, updated_at)
                    VALUES (?, ?, ?, ?, 1, 'pending', ?, ?)
                """, arguments: [id, phrase, replacement, normKey, nowMs, nowMs])
            }
        }
    }

    /// Lists all pending suggestions ordered by occurrences descending.
    public func listPending() throws -> [VoiceDictionarySuggestion] {
        try db.queue.read { conn in
            try Row.fetchAll(conn, sql: """
                SELECT id, phrase, replacement, norm_key, occurrences, status, first_seen_at, updated_at
                FROM voice_dictionary_suggestions
                WHERE status = 'pending' AND occurrences >= 3
                ORDER BY occurrences DESC, updated_at DESC
            """).map(Self.suggestion(from:))
        }
    }

    public func markAccepted(id: String) throws {
        try db.queue.write { conn in
            try conn.execute(sql: """
                UPDATE voice_dictionary_suggestions SET status = 'accepted', updated_at = ?
                WHERE id = ?
            """, arguments: [Self.millis(Date()), id])
        }
    }

    public func markDismissed(id: String) throws {
        try db.queue.write { conn in
            try conn.execute(sql: """
                UPDATE voice_dictionary_suggestions SET status = 'dismissed', updated_at = ?
                WHERE id = ?
            """, arguments: [Self.millis(Date()), id])
        }
    }

    public func clearAll() throws {
        try db.queue.write { conn in
            try conn.execute(sql: "DELETE FROM voice_dictionary_suggestions")
        }
    }

    // MARK: - Helpers

    public static func makeNormKey(phrase: String) -> String {
        phrase.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func suggestion(from row: Row) -> VoiceDictionarySuggestion {
        let statusRaw: String = row["status"]
        let status = VoiceDictionarySuggestion.Status(rawValue: statusRaw) ?? .pending
        return VoiceDictionarySuggestion(
            id: row["id"],
            phrase: row["phrase"],
            replacement: row["replacement"],
            normKey: row["norm_key"],
            occurrences: Int(row["occurrences"] as Int64),
            status: status,
            firstSeenAt: date(milliseconds: row["first_seen_at"]),
            updatedAt: date(milliseconds: row["updated_at"])
        )
    }

    private static func millis(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    private static func date(milliseconds: Int64) -> Date {
        Date(timeIntervalSince1970: Double(milliseconds) / 1000)
    }
}
