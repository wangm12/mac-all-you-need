import CryptoKit
import Foundation
import GRDB

private enum ClipboardVoiceMigration {
    static let sql = """
        CREATE TABLE IF NOT EXISTS voice_transcripts (
            id TEXT PRIMARY KEY NOT NULL,
            started_at INTEGER NOT NULL,
            ended_at INTEGER NOT NULL,
            duration_ms INTEGER NOT NULL,
            raw_text TEXT NOT NULL,
            cleaned_text TEXT NOT NULL,
            app_bundle_id TEXT,
            language TEXT NOT NULL,
            model_identifier TEXT NOT NULL,
            audio_path TEXT,
            status TEXT NOT NULL DEFAULT 'success',
            failed_stage TEXT,
            failure_reason TEXT,
            retry_source_transcript_id TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_voice_transcripts_started_at
            ON voice_transcripts(started_at DESC);

        CREATE TABLE IF NOT EXISTS audio_archives (
            id TEXT PRIMARY KEY NOT NULL,
            transcript_id TEXT NOT NULL,
            path TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            expires_at INTEGER,
            FOREIGN KEY(transcript_id) REFERENCES voice_transcripts(id) ON DELETE CASCADE
        );

        CREATE TABLE IF NOT EXISTS voice_dictionary (
            id TEXT PRIMARY KEY NOT NULL,
            phrase TEXT NOT NULL,
            replacement TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
        );

        CREATE TABLE IF NOT EXISTS app_profiles (
            id TEXT PRIMARY KEY NOT NULL,
            bundle_id TEXT NOT NULL UNIQUE,
            display_name TEXT NOT NULL,
            json TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
        );

        ALTER TABLE clipboard_records ADD COLUMN capture_origin TEXT;
        ALTER TABLE clipboard_records ADD COLUMN voice_transcript_id TEXT;
        CREATE INDEX IF NOT EXISTS idx_clipboard_records_capture_origin
            ON clipboard_records(capture_origin);
    """
}

public final class ClipboardStore {
    /// Package-internal so Smart Text enrichment helpers can live in a separate
    /// extension file (`ClipboardStore+SmartText.swift`) without bloating this type.
    let db: Database
    private let key: SymmetricKey
    private let deviceID: DeviceID
    private let log = Logging.logger(for: "storage", category: "clipboard")

    public init(database: Database, deviceKey: SymmetricKey, deviceID: DeviceID) throws {
        db = database
        key = deviceKey
        self.deviceID = deviceID
    }

    public static let migrations: [Migration] = [
        Migration(identifier: "001-clipboard-records") { conn in
            try conn.execute(sql: """
                CREATE TABLE IF NOT EXISTS clipboard_records (
                    id TEXT PRIMARY KEY NOT NULL,
                    created INTEGER NOT NULL,
                    modified INTEGER NOT NULL,
                    device_id TEXT NOT NULL,
                    lamport INTEGER NOT NULL,
                    kind TEXT NOT NULL,
                    preview TEXT NOT NULL,
                    source_app TEXT,
                    envelope BLOB NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_records_modified ON clipboard_records(modified DESC);
                CREATE TABLE IF NOT EXISTS lamport_clock (
                    scope TEXT PRIMARY KEY NOT NULL,
                    value INTEGER NOT NULL
                );
                INSERT OR IGNORE INTO lamport_clock(scope, value) VALUES ('clipboard', 0);
            """)
        },
        Migration(identifier: "002-frequency-tracking") { conn in
            try conn.execute(sql: """
                ALTER TABLE clipboard_records ADD COLUMN frequency INTEGER NOT NULL DEFAULT 0;
                ALTER TABLE clipboard_records ADD COLUMN last_accessed INTEGER;
                CREATE INDEX IF NOT EXISTS idx_records_frequency ON clipboard_records(frequency DESC);
                CREATE INDEX IF NOT EXISTS idx_records_last_accessed ON clipboard_records(last_accessed DESC);
            """)
        },
        Migration(identifier: "003-custom-label") { conn in
            // Optional user-set rename label. NULL when never renamed.
            try conn.execute(sql: """
                ALTER TABLE clipboard_records ADD COLUMN custom_label TEXT;
            """)
        },
        Migration(identifier: "004-voice-schema") { conn in
            try conn.execute(sql: ClipboardVoiceMigration.sql)
        },
        Migration(identifier: "005-personalization") { conn in
            try conn.execute(sql: VoicePersonalizationMigration.sql)
        },
        Migration(identifier: "006-voice-training-examples") { conn in
            try conn.execute(sql: VoiceTrainingExampleMigration.sql)
        },
        Migration(identifier: "007-personalization-pinned-examples") { conn in
            try conn.execute(sql: VoicePersonalizationPinnedMigration.sql)
        },
        Migration(identifier: "008-smart-text") { conn in
            try conn.execute(sql: "ALTER TABLE clipboard_records ADD COLUMN detected_type TEXT;")
            try conn.execute(sql: "ALTER TABLE clipboard_records ADD COLUMN ocr_text TEXT;")
            try conn.execute(sql: "ALTER TABLE clipboard_records ADD COLUMN embedding BLOB;")
            try conn.execute(sql: "CREATE INDEX IF NOT EXISTS idx_records_detected_type ON clipboard_records(detected_type);")
        },
        Migration(identifier: "009-voice-transcript-status") { conn in
            let existing = Set(try Row.fetchAll(conn, sql: "PRAGMA table_info(voice_transcripts)")
                .compactMap { $0["name"] as String? })
            if !existing.contains("status") {
                try conn.execute(sql: "ALTER TABLE voice_transcripts ADD COLUMN status TEXT NOT NULL DEFAULT 'success';")
            }
            if !existing.contains("failed_stage") {
                try conn.execute(sql: "ALTER TABLE voice_transcripts ADD COLUMN failed_stage TEXT;")
            }
            if !existing.contains("failure_reason") {
                try conn.execute(sql: "ALTER TABLE voice_transcripts ADD COLUMN failure_reason TEXT;")
            }
            if !existing.contains("retry_source_transcript_id") {
                try conn.execute(sql: "ALTER TABLE voice_transcripts ADD COLUMN retry_source_transcript_id TEXT;")
            }
        },
        Migration(identifier: "010-voice-dictionary-suggestions") { conn in
            try conn.execute(sql: VoiceDictionarySuggestionMigration.sql)
        }
    ]

    @discardableResult
    public func append(
        _ record: ClipboardRecord,
        sourceAppBundleID: String? = nil,
        detectedTypeJSON: String? = nil
    ) throws -> ClipboardItemMeta {
        let id = RecordID.generate()
        let now = Date()
        let preview = Self.preview(for: record)
        let payload = try JSONEncoder().encode(record)
        let envelope = try Cipher.seal(payload, with: key)

        var insertedLamport: UInt64 = 0
        try db.queue.write { conn in
            let current: Int64 = try Int64.fetchOne(
                conn,
                sql: "SELECT value FROM lamport_clock WHERE scope = 'clipboard'"
            ) ?? 0
            let next = current + 1
            try conn.execute(
                sql: "UPDATE lamport_clock SET value = ? WHERE scope = 'clipboard'",
                arguments: [next]
            )
            insertedLamport = UInt64(next)
            try conn.execute(sql: """
                INSERT INTO clipboard_records
                    (id, created, modified, device_id, lamport, kind, preview, source_app, envelope, detected_type)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                id.rawValue,
                Int(now.timeIntervalSince1970 * 1000),
                Int(now.timeIntervalSince1970 * 1000),
                deviceID.rawValue,
                Int(insertedLamport),
                RecordKind.clipboardItem.rawValue,
                preview,
                sourceAppBundleID,
                envelope.combined,
                detectedTypeJSON
            ])
        }
        return ClipboardItemMeta(
            id: id, created: now, modified: now, deviceID: deviceID, lamport: insertedLamport,
            kind: .clipboardItem,
            preview: preview,
            sourceAppBundleID: sourceAppBundleID,
            frequency: 0,
            lastAccessed: nil,
            detectedTypeJSON: detectedTypeJSON
        )
    }

    // MARK: - Smart Text enrichment
    //
    // Read/write helpers for the migration-008 columns (detected_type, ocr_text,
    // embedding) live in `ClipboardStore+SmartText.swift`.

    public func list(
        limit: Int,
        offset: Int = 0,
        modifiedOnOrAfter: Date? = nil,
        structured: ClipboardHistoryStructuredFilter = ClipboardHistoryStructuredFilter()
    ) throws -> [ClipboardItemMeta] {
        try listRows(
            limit: limit,
            offset: offset,
            modifiedOnOrAfter: modifiedOnOrAfter,
            structured: structured
        )
    }

    /// Binary overload keeps a stable symbol for older call sites (`list(limit:offset:)`).
    public func list(limit: Int, offset: Int) throws -> [ClipboardItemMeta] {
        try listRows(limit: limit, offset: offset, modifiedOnOrAfter: nil)
    }

    private func listRows(
        limit: Int,
        offset: Int,
        modifiedOnOrAfter: Date?,
        structured: ClipboardHistoryStructuredFilter = ClipboardHistoryStructuredFilter()
    ) throws -> [ClipboardItemMeta] {
        let (whereSQL, whereArgs) = Self.structuredWhereSQL(
            structured: structured,
            modifiedOnOrAfter: modifiedOnOrAfter
        )
        let select = """
            SELECT id, created, modified, device_id, lamport, kind, preview, source_app,
                   frequency, last_accessed, custom_label, detected_type, ocr_text, embedding
            FROM clipboard_records\(whereSQL)
            ORDER BY modified DESC, lamport DESC LIMIT ? OFFSET ?
            """
        var args = whereArgs
        args.append(limit)
        args.append(max(0, offset))
        return try db.queue.read { conn in
            try Row.fetchAll(conn, sql: select, arguments: StatementArguments(args)).map(Self.metaRow)
        }
    }

    private static func structuredWhereSQL(
        structured: ClipboardHistoryStructuredFilter,
        modifiedOnOrAfter: Date?
    ) -> (sql: String, arguments: [DatabaseValueConvertible]) {
        var clauses: [String] = []
        var arguments: [DatabaseValueConvertible] = []
        let cutoff = structured.modifiedOnOrAfter ?? modifiedOnOrAfter
        if let cutoff {
            clauses.append("modified >= ?")
            arguments.append(Int(cutoff.timeIntervalSince1970 * 1000))
        }
        if !structured.appIncludes.isEmpty {
            let parts = structured.appIncludes.map { _ in "LOWER(COALESCE(source_app, '')) LIKE ?" }
            clauses.append("(\(parts.joined(separator: " OR ")))")
            for app in structured.appIncludes {
                arguments.append("%\(app.lowercased())%")
            }
        }
        for app in structured.appExcludes {
            clauses.append("(source_app IS NULL OR LOWER(source_app) NOT LIKE ?)")
            arguments.append("%\(app.lowercased())%")
        }
        guard !clauses.isEmpty else { return ("", arguments) }
        return (" WHERE \(clauses.joined(separator: " AND "))", arguments)
    }

    public func metas(for ids: [RecordID]) throws -> [ClipboardItemMeta] {
        guard !ids.isEmpty else { return [] }
        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
        let rows = try db.queue.read { conn in
            try Row.fetchAll(conn, sql: """
                SELECT id, created, modified, device_id, lamport, kind, preview, source_app,
                       frequency, last_accessed, custom_label, detected_type, ocr_text, embedding
                FROM clipboard_records WHERE id IN (\(placeholders))
            """, arguments: StatementArguments(ids.map(\.rawValue)))
        }
        let byID = Dictionary(uniqueKeysWithValues: rows.map { row in
            (row["id"] as String, Self.metaRow(row))
        })
        return ids.compactMap { byID[$0.rawValue] }
    }

    public func body(for id: RecordID) throws -> ClipboardRecord {
        let envelope: Envelope = try db.queue.read { conn in
            guard let row = try Row.fetchOne(
                conn,
                sql: "SELECT envelope FROM clipboard_records WHERE id = ?",
                arguments: [id.rawValue]
            ) else {
                throw NSError(domain: "ClipboardStore", code: 404)
            }
            return Envelope(combined: row["envelope"])
        }
        let plaintext = try Cipher.open(envelope, with: key)
        return try JSONDecoder().decode(ClipboardRecord.self, from: plaintext)
    }

    public func delete(id: RecordID) throws {
        try db.queue.write { conn in
            try conn.execute(sql: "DELETE FROM clipboard_records WHERE id = ?", arguments: [id.rawValue])
        }
    }

    public func bumpFrequency(id: RecordID) throws {
        try db.queue.write { conn in
            try conn.execute(sql: """
                UPDATE clipboard_records
                SET frequency = frequency + 1, last_accessed = ?
                WHERE id = ?
            """, arguments: [Int(Date().timeIntervalSince1970 * 1000), id.rawValue])
        }
    }

    /// Set or clear the user-provided rename label for a record. Pass `nil`
    /// to revert to the auto-generated `preview` for display purposes.
    public func setCustomLabel(id: RecordID, label: String?) throws {
        try db.queue.write { conn in
            try conn.execute(
                sql: "UPDATE clipboard_records SET custom_label = ? WHERE id = ?",
                arguments: [label, id.rawValue]
            )
        }
    }

    public func recentByFrequency(limit: Int, offset: Int = 0, modifiedOnOrAfter: Date? = nil) throws -> [ClipboardItemMeta] {
        try db.queue.read { conn in
            if let modifiedOnOrAfter {
                let ms = Int(modifiedOnOrAfter.timeIntervalSince1970 * 1000)
                return try Row.fetchAll(conn, sql: """
                    SELECT id, created, modified, device_id, lamport, kind, preview, source_app,
                           frequency, last_accessed, custom_label, detected_type, ocr_text, embedding
                    FROM clipboard_records
                    WHERE modified >= ?
                    ORDER BY frequency DESC, modified DESC
                    LIMIT ? OFFSET ?
                    """, arguments: [ms, limit, max(0, offset)]).map(Self.metaRow)
            }
            return try Row.fetchAll(conn, sql: """
                SELECT id, created, modified, device_id, lamport, kind, preview, source_app,
                       frequency, last_accessed, custom_label, detected_type, ocr_text, embedding
                FROM clipboard_records
                ORDER BY frequency DESC, modified DESC
                LIMIT ? OFFSET ?
                """, arguments: [limit, max(0, offset)]).map(Self.metaRow)
        }
    }

    public func recentByLastAccessed(limit: Int, offset: Int = 0, modifiedOnOrAfter: Date? = nil) throws -> [ClipboardItemMeta] {
        try db.queue.read { conn in
            if let modifiedOnOrAfter {
                let ms = Int(modifiedOnOrAfter.timeIntervalSince1970 * 1000)
                return try Row.fetchAll(conn, sql: """
                    SELECT id, created, modified, device_id, lamport, kind, preview, source_app,
                           frequency, last_accessed, custom_label, detected_type, ocr_text, embedding
                    FROM clipboard_records
                    WHERE last_accessed IS NOT NULL AND modified >= ?
                    ORDER BY last_accessed DESC
                    LIMIT ? OFFSET ?
                    """, arguments: [ms, limit, max(0, offset)]).map(Self.metaRow)
            }
            return try Row.fetchAll(conn, sql: """
                SELECT id, created, modified, device_id, lamport, kind, preview, source_app,
                       frequency, last_accessed, custom_label, detected_type, ocr_text, embedding
                FROM clipboard_records
                WHERE last_accessed IS NOT NULL
                ORDER BY last_accessed DESC
                LIMIT ? OFFSET ?
                """, arguments: [limit, max(0, offset)]).map(Self.metaRow)
        }
    }

    private static func preview(for record: ClipboardRecord) -> String {
        switch record {
        case let .text(s): String(s.prefix(120))
        case .rtf: "(rich text)"
        case let .html(s): String(htmlToPlainText(s).prefix(120))
        case let .image(_, w, h): "(image \(w)×\(h))"
        case let .files(urls): "(\(urls.count) file\(urls.count == 1 ? "" : "s"))"
        }
    }

    /// Convert HTML markup to a readable plain-text preview. Browsers (Chrome,
    /// Arc, Safari) attach an HTML rep alongside plain text on most copies; we
    /// keep the markup record for rich-text paste-back fidelity, but the card
    /// preview should show the text the user actually sees, not raw tags like
    /// "(html) <meta charset='utf-8'><span style=...".
    ///
    /// Pure-Foundation implementation (Core can't link AppKit): strip script/
    /// style blocks, drop tags, decode the common named/numeric entities, and
    /// collapse whitespace. Good enough for previews — full fidelity isn't the
    /// goal here, the original HTML is preserved for paste-back.
    private static func htmlToPlainText(_ html: String) -> String {
        var s = html
        // Drop entire <script>/<style> blocks before stripping tags so their
        // contents don't leak into the preview.
        for tag in ["script", "style"] {
            let pattern = "<\(tag)\\b[^>]*>[\\s\\S]*?</\(tag)>"
            s = s.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        // Strip remaining tags.
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        // Decode the entities most common in clipboard HTML.
        let entities: [(String, String)] = [
            ("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&apos;", "'"), ("&#39;", "'"), ("&#34;", "\""),
            ("&hellip;", "…"), ("&mdash;", "—"), ("&ndash;", "–"),
            ("&ldquo;", "\u{201C}"), ("&rdquo;", "\u{201D}"),
            ("&lsquo;", "\u{2018}"), ("&rsquo;", "\u{2019}")
        ]
        for (entity, replacement) in entities {
            s = s.replacingOccurrences(of: entity, with: replacement)
        }
        // Collapse runs of whitespace (incl. newlines) to single spaces.
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func metaRow(_ row: Row) -> ClipboardItemMeta {
        let lastAccessedMs = row["last_accessed"] as Int64?
        return ClipboardItemMeta(
            id: RecordID(rawValue: row["id"])!,
            created: Date(timeIntervalSince1970: Double(row["created"] as Int64) / 1000),
            modified: Date(timeIntervalSince1970: Double(row["modified"] as Int64) / 1000),
            deviceID: DeviceID(rawValue: row["device_id"])!,
            lamport: UInt64(row["lamport"] as Int64),
            kind: RecordKind(rawValue: row["kind"]) ?? .clipboardItem,
            preview: row["preview"],
            sourceAppBundleID: row["source_app"],
            frequency: Int(row["frequency"] as Int64? ?? 0),
            lastAccessed: lastAccessedMs.map { Date(timeIntervalSince1970: Double($0) / 1000) },
            customLabel: row["custom_label"] as String?,
            detectedTypeJSON: row["detected_type"] as String?,
            ocrText: row["ocr_text"] as String?,
            embedding: row["embedding"] as Data?
        )
    }
}
