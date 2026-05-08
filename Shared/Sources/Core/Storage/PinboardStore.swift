import CryptoKit
import Foundation
import GRDB

public final class PinboardStore {
    private let db: Database
    private let key: SymmetricKey

    public init(database: Database, deviceKey: SymmetricKey) {
        db = database
        key = deviceKey
    }

    public static let migrations: [Migration] = [
        Migration(identifier: "001-pinboards") { conn in
            try conn.execute(sql: """
                CREATE TABLE IF NOT EXISTS pinboards (
                    id TEXT PRIMARY KEY NOT NULL,
                    name TEXT NOT NULL,
                    sort_order INTEGER NOT NULL DEFAULT 0,
                    envelope BLOB NOT NULL,
                    modified REAL NOT NULL,
                    device_id TEXT,
                    lamport INTEGER NOT NULL DEFAULT 0
                );
            """)
        }
    ]

    @discardableResult
    public func create(name: String, color: String? = nil) throws -> Pinboard {
        let pinboard = Pinboard(name: name, color: color)
        try persist(pinboard, order: maxOrder() + 1)
        return pinboard
    }

    public func list() throws -> [Pinboard] {
        try db.queue.read { conn in
            try Row.fetchAll(conn, sql: "SELECT envelope FROM pinboards ORDER BY sort_order ASC")
                .compactMap { try? self.decode(row: $0) }
        }
    }

    public func rename(id: RecordID, to name: String) throws {
        var pinboard = try fetch(id: id)
        pinboard.name = name
        pinboard.modified = Date()
        try update(pinboard)
    }

    public func addItem(_ itemID: RecordID, to pinboardID: RecordID, at index: Int? = nil) throws {
        var pinboard = try fetch(id: pinboardID)
        pinboard.itemIDs.removeAll { $0 == itemID }
        if let index, pinboard.itemIDs.indices.contains(index) {
            pinboard.itemIDs.insert(itemID, at: index)
        } else {
            pinboard.itemIDs.append(itemID)
        }
        pinboard.modified = Date()
        try update(pinboard)
    }

    public func removeItem(_ itemID: RecordID, from pinboardID: RecordID) throws {
        var pinboard = try fetch(id: pinboardID)
        pinboard.itemIDs.removeAll { $0 == itemID }
        pinboard.modified = Date()
        try update(pinboard)
    }

    public func delete(id: RecordID) throws {
        try db.queue.write { conn in
            try conn.execute(sql: "DELETE FROM pinboards WHERE id = ?", arguments: [id.rawValue])
        }
    }

    private func fetch(id: RecordID) throws -> Pinboard {
        try db.queue.read { conn in
            guard let row = try Row.fetchOne(
                conn,
                sql: "SELECT envelope FROM pinboards WHERE id = ?",
                arguments: [id.rawValue]
            ) else {
                throw NSError(domain: "PinboardStore", code: 404)
            }
            return try self.decode(row: row)
        }
    }

    private func persist(_ pinboard: Pinboard, order: Int) throws {
        let env = try Cipher.seal(JSONEncoder().encode(pinboard), with: key)
        try db.queue.write { conn in
            try conn.execute(sql: """
                INSERT INTO pinboards (id, name, sort_order, envelope, modified, device_id, lamport)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                pinboard.id.rawValue, pinboard.name, order, env.combined,
                pinboard.modified.timeIntervalSince1970, pinboard.deviceID?.rawValue, pinboard.lamport
            ])
        }
    }

    public func update(_ pinboard: Pinboard) throws {
        let env = try Cipher.seal(JSONEncoder().encode(pinboard), with: key)
        try db.queue.write { conn in
            try conn.execute(sql: """
                UPDATE pinboards SET name = ?, envelope = ?, modified = ?, device_id = ?, lamport = ? WHERE id = ?
            """, arguments: [
                pinboard.name, env.combined, pinboard.modified.timeIntervalSince1970,
                pinboard.deviceID?.rawValue, pinboard.lamport, pinboard.id.rawValue
            ])
        }
    }

    private func decode(row: Row) throws -> Pinboard {
        let env = Envelope(combined: row["envelope"])
        let data = try Cipher.open(env, with: key)
        return try JSONDecoder().decode(Pinboard.self, from: data)
    }

    private func maxOrder() throws -> Int {
        try db.queue.read { conn in
            try (Int.fetchOne(conn, sql: "SELECT MAX(sort_order) FROM pinboards") ?? 0)
        }
    }
}
