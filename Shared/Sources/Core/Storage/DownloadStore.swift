import CryptoKit
import Foundation
import GRDB

public final class DownloadStore {
    public struct SnapshotSummary: Equatable, Sendable {
        public let count: Int
        public let modifiedMax: Int?

        public init(count: Int, modifiedMax: Int?) {
            self.count = count
            self.modifiedMax = modifiedMax
        }
    }

    private let db: Database
    private let key: SymmetricKey
    private let log = Logging.logger(for: "downloads", category: "store")

    public init(database: Database, deviceKey: SymmetricKey) throws {
        db = database
        key = deviceKey
        try backfillCollectionIDsIfNeeded()
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
        },
        Migration(identifier: "002-downloads-collection-id") { conn in
            try conn.execute(sql: """
                ALTER TABLE downloads ADD COLUMN collection_id TEXT;
            """)
            try conn.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_downloads_collection_id ON downloads(collection_id);
            """)
        }
    ]

    private func backfillCollectionIDsIfNeeded() throws {
        try db.queue.write { conn in
            let columns = try Row.fetchAll(conn, sql: "PRAGMA table_info(downloads)")
            let hasCollectionColumn = columns.contains { row in
                (row["name"] as String?) == "collection_id"
            }
            guard hasCollectionColumn else { return }
            let missingRows = try Row.fetchAll(
                conn,
                sql: "SELECT id, envelope FROM downloads WHERE collection_id IS NULL"
            )
            guard !missingRows.isEmpty else { return }
            for row in missingRows {
                guard let idRaw = row["id"] as String? else { continue }
                let env = Envelope(combined: row["envelope"])
                let plaintext = try Cipher.open(env, with: key)
                let record = try JSONDecoder().decode(DownloadRecord.self, from: plaintext)
                try conn.execute(
                    sql: "UPDATE downloads SET collection_id = ? WHERE id = ?",
                    arguments: [record.collectionID, idRaw]
                )
            }
        }
    }

    @discardableResult
    public func insertBulk(_ records: [DownloadRecord]) throws -> [RecordID] {
        guard !records.isEmpty else { return [] }
        guard records.count <= PlaylistEntryLister.maxBulkItems else {
            throw PlaylistListError.tooManyItems(count: records.count)
        }

        var ids: [RecordID] = []
        let baseCreated = Date()
        try db.queue.write { conn in
            for (offset, var record) in records.enumerated() {
                record.created = baseCreated.addingTimeInterval(Double(offset) * 0.001)
                record.modified = record.created
                let payload = try JSONEncoder().encode(record)
                let env = try Cipher.seal(payload, with: key)
                try conn.execute(sql: """
                    INSERT INTO downloads (id, state, created, modified, collection_id, device_id, lamport, envelope) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [
                    record.id.rawValue, record.state.rawValue,
                    Int(record.created.timeIntervalSince1970 * 1000),
                    Int(record.modified.timeIntervalSince1970 * 1000),
                    record.collectionID,
                    record.deviceID?.rawValue,
                    Int(record.lamport),
                    env.combined
                ])
                ids.append(record.id)
            }
        }
        return ids
    }

    public func fetchAll() throws -> [DownloadRecord] {
        try db.queue.read { conn in
            let rows = try Row.fetchAll(conn, sql: "SELECT envelope FROM downloads ORDER BY modified DESC")
            return try rows.compactMap { row in
                let env = Envelope(combined: row["envelope"])
                let plaintext = try Cipher.open(env, with: key)
                return try JSONDecoder().decode(DownloadRecord.self, from: plaintext)
            }
        }
    }

    public func snapshotSummary() throws -> SnapshotSummary {
        try db.queue.read { conn in
            let row = try Row.fetchOne(
                conn,
                sql: "SELECT COUNT(*) AS count, MAX(modified) AS modifiedMax FROM downloads"
            )
            let count = row?["count"] as Int? ?? 0
            let modifiedMax = row?["modifiedMax"] as Int?
            return SnapshotSummary(count: count, modifiedMax: modifiedMax)
        }
    }

    public func records(inCollection collectionID: String) throws -> [DownloadRecord] {
        try db.queue.read { conn in
            let rows = try Row.fetchAll(
                conn,
                sql: "SELECT envelope FROM downloads WHERE collection_id = ? ORDER BY modified DESC",
                arguments: [collectionID]
            )
            return try rows.compactMap { row in
                let env = Envelope(combined: row["envelope"])
                let plaintext = try Cipher.open(env, with: key)
                return try JSONDecoder().decode(DownloadRecord.self, from: plaintext)
            }
        }
    }

    public func count(inCollection collectionID: String) throws -> Int {
        try db.queue.read { conn in
            let row = try Row.fetchOne(
                conn,
                sql: "SELECT COUNT(*) AS count FROM downloads WHERE collection_id = ?",
                arguments: [collectionID]
            )
            return row?["count"] as Int? ?? 0
        }
    }

    @discardableResult
    public func insert(_ record: DownloadRecord) throws -> RecordID {
        let payload = try JSONEncoder().encode(record)
        let env = try Cipher.seal(payload, with: key)
        try db.queue.write { conn in
            try conn.execute(sql: """
                INSERT INTO downloads (id, state, created, modified, collection_id, device_id, lamport, envelope) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                record.id.rawValue, record.state.rawValue,
                Int(record.created.timeIntervalSince1970 * 1000),
                Int(record.modified.timeIntervalSince1970 * 1000),
                record.collectionID,
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

    public func delete(ids: [RecordID]) throws {
        guard !ids.isEmpty else { return }
        try db.queue.write { conn in
            let rawIDs = ids.map(\.rawValue)
            try conn.execute(
                sql: "DELETE FROM downloads WHERE id IN (\(rawIDs.map { _ in "?" }.joined(separator: ",")))",
                arguments: StatementArguments(rawIDs)
            )
        }
    }

    public func update(_ record: DownloadRecord) throws {
        let env = try Cipher.seal(JSONEncoder().encode(record), with: key)
        try db.queue.write { conn in
            try conn.execute(
                sql: "UPDATE downloads SET state = ?, modified = ?, collection_id = ?, device_id = ?, lamport = ?, envelope = ? WHERE id = ?",
                arguments: [
                    record.state.rawValue,
                    Int(record.modified.timeIntervalSince1970 * 1000),
                    record.collectionID,
                    record.deviceID?.rawValue,
                    Int(record.lamport),
                    env.combined,
                    record.id.rawValue
                ]
            )
        }
    }
}
