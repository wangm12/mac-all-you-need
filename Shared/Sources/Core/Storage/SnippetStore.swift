import CryptoKit
import Foundation
import GRDB

public final class SnippetStore {
    private let db: Database
    private let key: SymmetricKey

    public init(database: Database, deviceKey: SymmetricKey) {
        db = database
        key = deviceKey
    }

    public static let migrations: [Migration] = [
        Migration(identifier: "001-snippets") { conn in
            try conn.execute(sql: """
                CREATE TABLE IF NOT EXISTS snippets (
                    id TEXT PRIMARY KEY NOT NULL,
                    trigger TEXT UNIQUE,
                    name TEXT NOT NULL,
                    envelope BLOB NOT NULL,
                    modified REAL NOT NULL,
                    device_id TEXT,
                    lamport INTEGER NOT NULL DEFAULT 0
                );
            """)
        }
    ]

    @discardableResult
    public func create(name: String, body: String, trigger: String? = nil) throws -> Snippet {
        let snippet = Snippet(name: name, body: body, trigger: trigger)
        try persist(snippet)
        return snippet
    }

    public func list() throws -> [Snippet] {
        try db.queue.read { conn in
            try Row.fetchAll(conn, sql: "SELECT envelope FROM snippets ORDER BY modified DESC")
                .compactMap { try? self.decode(row: $0) }
        }
    }

    public func update(id: RecordID, name: String, body: String, trigger: String?) throws {
        var snippet = try fetch(id: id)
        snippet.name = name
        snippet.body = body
        snippet.trigger = trigger
        snippet.modified = Date()
        try updateRow(snippet)
    }

    public func find(trigger: String) throws -> Snippet? {
        try db.queue.read { conn in
            guard let row = try Row.fetchOne(
                conn,
                sql: "SELECT envelope FROM snippets WHERE trigger = ?",
                arguments: [trigger]
            ) else { return nil }
            return try self.decode(row: row)
        }
    }

    public func delete(id: RecordID) throws {
        try db.queue.write { conn in
            try conn.execute(sql: "DELETE FROM snippets WHERE id = ?", arguments: [id.rawValue])
        }
    }

    private func fetch(id: RecordID) throws -> Snippet {
        try db.queue.read { conn in
            guard let row = try Row.fetchOne(
                conn,
                sql: "SELECT envelope FROM snippets WHERE id = ?",
                arguments: [id.rawValue]
            ) else {
                throw NSError(domain: "SnippetStore", code: 404)
            }
            return try self.decode(row: row)
        }
    }

    private func persist(_ snippet: Snippet) throws {
        let env = try Cipher.seal(JSONEncoder().encode(snippet), with: key)
        try db.queue.write { conn in
            try conn.execute(sql: """
                INSERT INTO snippets (id, trigger, name, envelope, modified, device_id, lamport)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                snippet.id.rawValue, snippet.trigger, snippet.name, env.combined,
                snippet.modified.timeIntervalSince1970, snippet.deviceID?.rawValue, snippet.lamport
            ])
        }
    }

    private func updateRow(_ snippet: Snippet) throws {
        let env = try Cipher.seal(JSONEncoder().encode(snippet), with: key)
        try db.queue.write { conn in
            try conn.execute(sql: """
                UPDATE snippets SET trigger = ?, name = ?, envelope = ?, modified = ?, device_id = ?, lamport = ? WHERE id = ?
            """, arguments: [
                snippet.trigger, snippet.name, env.combined,
                snippet.modified.timeIntervalSince1970, snippet.deviceID?.rawValue,
                snippet.lamport, snippet.id.rawValue
            ])
        }
    }

    private func decode(row: Row) throws -> Snippet {
        let env = Envelope(combined: row["envelope"])
        let data = try Cipher.open(env, with: key)
        return try JSONDecoder().decode(Snippet.self, from: data)
    }
}
