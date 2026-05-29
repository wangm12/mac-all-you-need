import Foundation
import GRDB

public enum TypelessHistoryReaderError: Error, Equatable {
    case databaseNotFound(URL)
    case openFailed(URL, message: String)
}

/// Read-only access to Typeless `typeless.db`.
public struct TypelessHistoryReader: Sendable {
    public let databaseURL: URL

    public init(databaseURL: URL) {
        self.databaseURL = databaseURL
    }

    public func loadRecords() throws -> [TypelessHistoryRecord] {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw TypelessHistoryReaderError.databaseNotFound(databaseURL)
        }

        var config = Configuration()
        config.readonly = true
        let queue: DatabaseQueue
        do {
            queue = try DatabaseQueue(path: databaseURL.path, configuration: config)
        } catch {
            throw TypelessHistoryReaderError.openFailed(databaseURL, message: error.localizedDescription)
        }

        return try queue.read { db in
            let legacy = try Self.fetchHistoryTable(db)
            let modern = try Self.fetchHistoryV2Table(db)
            return (legacy + modern).sorted { $0.createdAt > $1.createdAt }
        }
    }

    private static func fetchHistoryTable(_ db: GRDB.Database) throws -> [TypelessHistoryRecord] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT id, refined_text, edited_text, duration, created_at,
                   focused_app_bundle_id, detected_language, languages, audio_local_path
            FROM history
            WHERE status IN ('transcript', 'completed')
              AND refined_text IS NOT NULL
              AND trim(refined_text) != ''
            ORDER BY created_at DESC
        """)
        return rows.compactMap { record(from: $0, source: .history) }
    }

    private static func fetchHistoryV2Table(_ db: GRDB.Database) throws -> [TypelessHistoryRecord] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT id, refined_text, duration, created_at, audio_local_path
            FROM history_v2
            WHERE status = 'completed'
              AND refined_text IS NOT NULL
              AND trim(refined_text) != ''
            ORDER BY created_at DESC
        """)
        return rows.compactMap { row in
            guard let createdAt = parseCreatedAt(stringColumn(row, "created_at")) else { return nil }
            return TypelessHistoryRecord(
                id: row["id"],
                refinedText: row["refined_text"],
                editedText: nil,
                createdAt: createdAt,
                durationSeconds: row["duration"] as Double? ?? 0,
                appBundleID: nil,
                detectedLanguage: nil,
                languagesJSON: nil,
                audioLocalPath: row["audio_local_path"],
                sourceTable: .historyV2
            )
        }
    }

    private static func record(from row: Row, source: TypelessHistorySourceTable) -> TypelessHistoryRecord? {
        guard let createdAt = parseCreatedAt(stringColumn(row, "created_at")) else { return nil }
        return TypelessHistoryRecord(
            id: row["id"],
            refinedText: row["refined_text"],
            editedText: row["edited_text"],
            createdAt: createdAt,
            durationSeconds: row["duration"] as Double? ?? 0,
            appBundleID: row["focused_app_bundle_id"],
            detectedLanguage: row["detected_language"],
            languagesJSON: row["languages"],
            audioLocalPath: row["audio_local_path"],
            sourceTable: source
        )
    }

    static func parseCreatedAt(_ text: String?) -> Date? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let posix = Locale(identifier: "en_US_POSIX")
        let formats = [
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",
            "yyyy-MM-dd HH:mm:ss"
        ]
        let formatter = DateFormatter()
        formatter.locale = posix
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) { return date }
        }

        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: trimmed) { return date }

        let internet = ISO8601DateFormatter()
        internet.formatOptions = [.withInternetDateTime]
        if let date = internet.date(from: trimmed) { return date }

        return nil
    }

    private static func stringColumn(_ row: Row, _ name: String) -> String? {
        guard let value = row[name] as String? else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
