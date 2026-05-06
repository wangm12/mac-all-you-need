import CryptoKit
import Foundation
import GRDB

public final class DownloadStore {
    private let db: Database
    private let key: SymmetricKey
    private let log = Logging.logger(for: "downloads", category: "store")

    public init(database: Database, deviceKey: SymmetricKey) throws {
        db = database
        key = deviceKey
    }

    public static let migrations: [Migration] = [
        Migration(identifier: "001-downloads") { conn in
            try conn.execute(sql: """
                CREATE TABLE IF NOT EXISTS downloads (
                    id TEXT PRIMARY KEY NOT NULL,
                    state TEXT NOT NULL,
                    created INTEGER NOT NULL,
                    modified INTEGER NOT NULL,
                    device_id TEXT,
                    lamport INTEGER NOT NULL DEFAULT 0,
                    envelope BLOB NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_downloads_state ON downloads(state);
            """)
        }
    ]

    @discardableResult
    public func insert(_ record: DownloadRecord) throws -> RecordID {
        let payload = try JSONEncoder().encode(record)
        let env = try Cipher.seal(payload, with: key)
        try db.queue.write { conn in
            try conn.execute(sql: """
                INSERT INTO downloads (id, state, created, modified, device_id, lamport, envelope) VALUES (?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                record.id.rawValue, record.state.rawValue,
                Int(record.created.timeIntervalSince1970 * 1000),
                Int(record.modified.timeIntervalSince1970 * 1000),
                record.deviceID?.rawValue,
                Int(record.lamport),
                env.combined
            ])
        }
        return record.id
    }

    public func fetch(id: RecordID) throws -> DownloadRecord {
        try db.queue.read { conn in
            guard let row = try Row.fetchOne(
                conn,
                sql: "SELECT envelope FROM downloads WHERE id = ?",
                arguments: [id.rawValue]
            ) else {
                throw NSError(domain: "DownloadStore", code: 404)
            }
            let env = Envelope(combined: row["envelope"])
            let plaintext = try Cipher.open(env, with: key)
            return try JSONDecoder().decode(DownloadRecord.self, from: plaintext)
        }
    }

    public func updateState(id: RecordID, to state: DownloadState) throws {
        var record = try fetch(id: id)
        record.state = state
        record.modified = Date()
        let env = try Cipher.seal(JSONEncoder().encode(record), with: key)
        try db.queue.write { conn in
            try conn.execute(
                sql: "UPDATE downloads SET state = ?, modified = ?, device_id = ?, lamport = ?, envelope = ? WHERE id = ?",
                arguments: [
                    state.rawValue,
                    Int(record.modified.timeIntervalSince1970 * 1000),
                    record.deviceID?.rawValue,
                    Int(record.lamport),
                    env.combined,
                    id.rawValue
                ]
            )
        }
    }

    public func list(state: DownloadState? = nil) throws -> [RecordID] {
        try db.queue.read { conn in
            let rows: [Row] = if let state {
                try Row.fetchAll(
                    conn,
                    sql: "SELECT id FROM downloads WHERE state = ? ORDER BY modified DESC",
                    arguments: [state.rawValue]
                )
            } else {
                try Row.fetchAll(conn, sql: "SELECT id FROM downloads ORDER BY modified DESC")
            }
            return rows.compactMap { RecordID(rawValue: $0["id"]) }
        }
    }

    public func updateProgress(id: RecordID, bytesDownloaded: Int64, bytesTotal: Int64?) throws {
        var record = try fetch(id: id)
        record.bytesDownloaded = bytesDownloaded
        record.bytesTotal = bytesTotal
        record.modified = Date()
        let env = try Cipher.seal(JSONEncoder().encode(record), with: key)
        try db.queue.write { conn in
            try conn.execute(
                sql: "UPDATE downloads SET modified = ?, envelope = ? WHERE id = ?",
                arguments: [Int(record.modified.timeIntervalSince1970 * 1000), env.combined, id.rawValue]
            )
        }
    }

    public func delete(id: RecordID) throws {
        try db.queue.write { conn in
            try conn.execute(sql: "DELETE FROM downloads WHERE id = ?", arguments: [id.rawValue])
        }
    }
}
