import Foundation
import GRDB

public final class VoiceAppProfileStore: @unchecked Sendable {
    private let db: Database

    public init(database: Database) {
        db = database
    }

    @discardableResult
    public func upsert(
        bundleID: String,
        displayName: String,
        config: VoiceAppProfileConfig
    ) throws -> VoiceAppProfile {
        let bundleID = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bundleID.isEmpty else { throw VoiceAppProfileStoreError.emptyBundleID }

        let json = try Self.encode(config)
        let id = try db.queue.write { conn -> String in
            if let row = try Row.fetchOne(
                conn,
                sql: "SELECT id FROM app_profiles WHERE bundle_id = ? LIMIT 1",
                arguments: [bundleID]
            ) {
                let id: String = row["id"]
                try conn.execute(sql: """
                    UPDATE app_profiles
                    SET display_name = ?, json = ?, updated_at = ?
                    WHERE id = ?
                """, arguments: [
                    displayName,
                    json,
                    Self.millis(Date()),
                    id
                ])
                return id
            }

            let id = UUID().uuidString
            let now = Self.millis(Date())
            try conn.execute(sql: """
                INSERT INTO app_profiles (
                    id, bundle_id, display_name, json, created_at, updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?)
            """, arguments: [
                id,
                bundleID,
                displayName,
                json,
                now,
                now
            ])
            return id
        }

        return try fetch(id: id) ?? VoiceAppProfile(
            id: id,
            bundleID: bundleID,
            displayName: displayName,
            config: config,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    public func fetch(bundleID: String) throws -> VoiceAppProfile? {
        try db.queue.read { conn in
            try Row.fetchOne(conn, sql: """
                SELECT id, bundle_id, display_name, json, created_at, updated_at
                FROM app_profiles
                WHERE bundle_id = ?
            """, arguments: [bundleID]).map(Self.profile(from:))
        }
    }

    public func list() throws -> [VoiceAppProfile] {
        try db.queue.read { conn in
            try Row.fetchAll(conn, sql: """
                SELECT id, bundle_id, display_name, json, created_at, updated_at
                FROM app_profiles
                ORDER BY display_name COLLATE NOCASE ASC, bundle_id ASC
            """).map(Self.profile(from:))
        }
    }

    public func delete(id: String) throws {
        try db.queue.write { conn in
            try conn.execute(sql: "DELETE FROM app_profiles WHERE id = ?", arguments: [id])
        }
    }

    private func fetch(id: String) throws -> VoiceAppProfile? {
        try db.queue.read { conn in
            try Row.fetchOne(conn, sql: """
                SELECT id, bundle_id, display_name, json, created_at, updated_at
                FROM app_profiles
                WHERE id = ?
            """, arguments: [id]).map(Self.profile(from:))
        }
    }

    private static func profile(from row: Row) throws -> VoiceAppProfile {
        let config = try decode(row["json"])
        return VoiceAppProfile(
            id: row["id"],
            bundleID: row["bundle_id"],
            displayName: row["display_name"],
            config: config,
            createdAt: date(milliseconds: row["created_at"] as Int64),
            updatedAt: date(milliseconds: row["updated_at"] as Int64)
        )
    }

    private static func encode(_ config: VoiceAppProfileConfig) throws -> String {
        let data = try JSONEncoder().encode(config)
        guard let json = String(data: data, encoding: .utf8) else {
            throw VoiceAppProfileStoreError.invalidJSON
        }
        return json
    }

    private static func decode(_ json: String) throws -> VoiceAppProfileConfig {
        let data = Data(json.utf8)
        let decoder = JSONDecoder()
        return try decoder.decode(VoiceAppProfileConfig.self, from: data)
    }

    private static func millis(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    private static func date(milliseconds: Int64) -> Date {
        Date(timeIntervalSince1970: Double(milliseconds) / 1000)
    }
}

public enum VoiceAppProfileStoreError: Error, Equatable {
    case emptyBundleID
    case invalidJSON
}
