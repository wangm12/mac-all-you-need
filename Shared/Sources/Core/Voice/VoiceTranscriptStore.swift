import Foundation
import GRDB

public final class VoiceTranscriptStore: @unchecked Sendable {
    private let db: Database

    public init(database: Database) {
        db = database
    }

    @discardableResult
    public func save(_ draft: VoiceTranscriptDraft, existingID: String? = nil) throws -> VoiceTranscript {
        let id = existingID ?? UUID().uuidString
        let durationMs = max(0, Int((draft.endedAt.timeIntervalSince(draft.startedAt) * 1000).rounded()))
        try db.queue.write { conn in
            try conn.execute(sql: """
                INSERT INTO voice_transcripts (
                    id, started_at, ended_at, duration_ms, raw_text, cleaned_text,
                    app_bundle_id, language, model_identifier, audio_path
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                id,
                Self.millis(draft.startedAt),
                Self.millis(draft.endedAt),
                durationMs,
                draft.rawText,
                draft.cleanedText,
                draft.appBundleID,
                draft.language.rawValue,
                draft.modelIdentifier,
                draft.audioPath
            ])
        }
        return VoiceTranscript(
            id: id,
            startedAt: draft.startedAt,
            endedAt: draft.endedAt,
            durationMs: durationMs,
            rawText: draft.rawText,
            cleanedText: draft.cleanedText,
            appBundleID: draft.appBundleID,
            language: draft.language,
            modelIdentifier: draft.modelIdentifier,
            audioPath: draft.audioPath
        )
    }

    public func fetch(id: String) throws -> VoiceTranscript? {
        try db.queue.read { conn in
            try Row.fetchOne(conn, sql: """
                SELECT id, started_at, ended_at, duration_ms, raw_text, cleaned_text,
                       app_bundle_id, language, model_identifier, audio_path
                FROM voice_transcripts WHERE id = ?
            """, arguments: [id]).map(Self.transcript(from:))
        }
    }

    public func listRecent(limit: Int = 20) throws -> [VoiceTranscript] {
        let normalizedLimit = max(1, limit)
        return try db.queue.read { conn in
            try Row.fetchAll(conn, sql: """
                SELECT id, started_at, ended_at, duration_ms, raw_text, cleaned_text,
                       app_bundle_id, language, model_identifier, audio_path
                FROM voice_transcripts
                ORDER BY ended_at DESC
                LIMIT ?
            """, arguments: [normalizedLimit]).map(Self.transcript(from:))
        }
    }

    public func delete(ids: [String]) throws {
        let uniqueIDs = Array(Set(ids))
        guard !uniqueIDs.isEmpty else { return }

        try db.queue.write { conn in
            for id in uniqueIDs {
                try conn.execute(sql: "DELETE FROM voice_transcripts WHERE id = ?", arguments: [id])
            }
        }
    }

    @discardableResult
    public func expireByAge(maxAge: TimeInterval, now: Date = Date()) throws -> [VoiceTranscript] {
        let cutoff = Self.millis(now.addingTimeInterval(-maxAge))
        return try db.queue.write { conn in
            let rows = try Row.fetchAll(conn, sql: """
                SELECT id, started_at, ended_at, duration_ms, raw_text, cleaned_text,
                       app_bundle_id, language, model_identifier, audio_path
                FROM voice_transcripts
                WHERE ended_at < ?
            """, arguments: [cutoff])
            let expired = rows.map(Self.transcript(from:))
            for transcript in expired {
                try conn.execute(sql: "DELETE FROM voice_transcripts WHERE id = ?", arguments: [transcript.id])
            }
            return expired
        }
    }

    private static func transcript(from row: Row) -> VoiceTranscript {
        VoiceTranscript(
            id: row["id"],
            startedAt: Date(timeIntervalSince1970: Double(row["started_at"] as Int64) / 1000),
            endedAt: Date(timeIntervalSince1970: Double(row["ended_at"] as Int64) / 1000),
            durationMs: Int(row["duration_ms"] as Int64),
            rawText: row["raw_text"],
            cleanedText: row["cleaned_text"],
            appBundleID: row["app_bundle_id"],
            language: VoiceLanguage(rawValue: row["language"]) ?? .unknown,
            modelIdentifier: row["model_identifier"],
            audioPath: row["audio_path"]
        )
    }

    private static func millis(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }
}
