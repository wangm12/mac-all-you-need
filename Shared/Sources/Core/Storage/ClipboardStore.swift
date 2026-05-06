import CryptoKit
import Foundation
import GRDB

public final class ClipboardStore {
    private let db: Database
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
        }
    ]

    @discardableResult
    public func append(_ record: ClipboardRecord, sourceAppBundleID: String? = nil) throws -> ClipboardItemMeta {
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
                INSERT INTO clipboard_records (id, created, modified, device_id, lamport, kind, preview, source_app, envelope)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                id.rawValue,
                Int(now.timeIntervalSince1970 * 1000),
                Int(now.timeIntervalSince1970 * 1000),
                deviceID.rawValue,
                Int(insertedLamport),
                RecordKind.clipboardItem.rawValue,
                preview,
                sourceAppBundleID,
                envelope.combined
            ])
        }
        return ClipboardItemMeta(
            id: id, created: now, modified: now, deviceID: deviceID, lamport: insertedLamport,
            kind: .clipboardItem, preview: preview, sourceAppBundleID: sourceAppBundleID
        )
    }

    public func list(limit: Int, offset: Int = 0) throws -> [ClipboardItemMeta] {
        try db.queue.read { conn in
            try Row.fetchAll(conn, sql: """
                SELECT id, created, modified, device_id, lamport, kind, preview, source_app
                FROM clipboard_records ORDER BY modified DESC LIMIT ? OFFSET ?
            """, arguments: [limit, max(0, offset)]).map(Self.metaRow)
        }
    }

    public func metas(for ids: [RecordID]) throws -> [ClipboardItemMeta] {
        guard !ids.isEmpty else { return [] }
        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
        let rows = try db.queue.read { conn in
            try Row.fetchAll(conn, sql: """
                SELECT id, created, modified, device_id, lamport, kind, preview, source_app
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

    private static func preview(for record: ClipboardRecord) -> String {
        switch record {
        case let .text(s): String(s.prefix(120))
        case .rtf: "(rich text)"
        case let .html(s): "(html) \(s.prefix(80))"
        case let .image(_, w, h): "(image \(w)×\(h))"
        case let .files(urls): "(\(urls.count) file\(urls.count == 1 ? "" : "s"))"
        }
    }

    private static func metaRow(_ row: Row) -> ClipboardItemMeta {
        ClipboardItemMeta(
            id: RecordID(rawValue: row["id"])!,
            created: Date(timeIntervalSince1970: Double(row["created"] as Int64) / 1000),
            modified: Date(timeIntervalSince1970: Double(row["modified"] as Int64) / 1000),
            deviceID: DeviceID(rawValue: row["device_id"])!,
            lamport: UInt64(row["lamport"] as Int64),
            kind: RecordKind(rawValue: row["kind"]) ?? .clipboardItem,
            preview: row["preview"],
            sourceAppBundleID: row["source_app"]
        )
    }
}
