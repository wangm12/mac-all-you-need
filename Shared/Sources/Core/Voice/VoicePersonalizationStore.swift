import CryptoKit
import Foundation
import GRDB

public final class VoicePersonalizationStore: @unchecked Sendable {
    private let db: Database
    private let key: SymmetricKey
    private let now: () -> Date

    public init(database: Database, deviceKey: SymmetricKey, now: @escaping () -> Date = Date.init) {
        db = database
        key = deviceKey
        self.now = now
    }

    @discardableResult
    public func upsertContext(_ draft: VoicePersonalizationContextDraft) throws -> VoicePersonalizationContext {
        let bundleID = draft.bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bundleID.isEmpty else { throw VoicePersonalizationStoreError.emptyBundleID }

        let nowMs = Self.millis(now())
        let id = try db.queue.write { conn -> String in
            if let row = try Row.fetchOne(
                conn,
                sql: "SELECT id FROM voice_personalization_contexts WHERE bundle_id = ? LIMIT 1",
                arguments: [bundleID]
            ) {
                let id: String = row["id"]
                try conn.execute(sql: """
                    UPDATE voice_personalization_contexts
                    SET display_name = ?,
                        enabled = ?,
                        asr_model_id = ?,
                        auto_submit_key = ?,
                        custom_prompt_override = ?,
                        style_notes = ?,
                        updated_at = ?
                    WHERE id = ?
                """, arguments: [
                    draft.displayName,
                    draft.enabled ? 1 : 0,
                    draft.asrModelID,
                    draft.autoSubmitKey?.rawValue,
                    draft.customPromptOverride,
                    draft.styleNotes,
                    nowMs,
                    id
                ])
                return id
            }

            let id = UUID().uuidString
            try conn.execute(sql: """
                INSERT INTO voice_personalization_contexts (
                    id, bundle_id, display_name, enabled,
                    asr_model_id, auto_submit_key, custom_prompt_override, style_notes,
                    encrypted_summary, summary_source_count, summary_generated_at,
                    sample_count, last_learned_at, created_at, updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, NULL, 0, NULL, 0, NULL, ?, ?)
            """, arguments: [
                id,
                bundleID,
                draft.displayName,
                draft.enabled ? 1 : 0,
                draft.asrModelID,
                draft.autoSubmitKey?.rawValue,
                draft.customPromptOverride,
                draft.styleNotes,
                nowMs,
                nowMs
            ])
            return id
        }

        guard let context = try fetchContext(id: id) else {
            throw VoicePersonalizationStoreError.contextNotFound
        }
        return context
    }

    public func fetchContext(bundleID: String) throws -> VoicePersonalizationContext? {
        try db.queue.read { conn in
            try Row.fetchOne(conn, sql: contextSelect + " WHERE bundle_id = ?", arguments: [bundleID])
                .map { try self.context(from: $0) }
        }
    }

    public func fetchContext(id: String) throws -> VoicePersonalizationContext? {
        try db.queue.read { conn in
            try Row.fetchOne(conn, sql: contextSelect + " WHERE id = ?", arguments: [id])
                .map { try self.context(from: $0) }
        }
    }

    public func listContexts() throws -> [VoicePersonalizationContext] {
        try db.queue.read { conn in
            let rows = try Row.fetchAll(
                conn,
                sql: contextSelect + " ORDER BY (bundle_id = 'global') DESC, display_name COLLATE NOCASE ASC"
            )
            return try rows.map { try self.context(from: $0) }
        }
    }

    public func deleteContext(id: String) throws {
        try db.queue.write { conn in
            try conn.execute(sql: "DELETE FROM voice_personalization_contexts WHERE id = ?", arguments: [id])
        }
    }

    public func clearAll() throws {
        try db.queue.write { conn in
            try conn.execute(sql: "DELETE FROM voice_personalization_samples")
            try conn.execute(sql: "DELETE FROM voice_personalization_contexts")
        }
    }

    @discardableResult
    public func appendSample(_ draft: VoicePersonalizationSampleDraft) throws -> VoicePersonalizationSample {
        let payload = EncryptedSamplePayload(
            v: EncryptedSamplePayload.currentVersion,
            before: draft.before,
            after: draft.after,
            diffOffset: draft.diffOffset,
            diffLength: draft.diffLength
        )
        let plaintext = try JSONEncoder().encode(payload)
        let envelope = try Cipher.seal(plaintext, with: key)

        let observedAt = now()
        let expiresAt = observedAt.addingTimeInterval(draft.ttlSeconds)
        let id = UUID().uuidString

        try db.queue.write { conn in
            try conn.execute(sql: """
                INSERT INTO voice_personalization_samples (
                    id, context_id, transcript_id, encrypted_payload,
                    observed_at, expires_at, summarized
                )
                VALUES (?, ?, ?, ?, ?, ?, 0)
            """, arguments: [
                id,
                draft.contextID,
                draft.transcriptID,
                envelope.combined,
                Self.millis(observedAt),
                Self.millis(expiresAt)
            ])
            try conn.execute(sql: """
                UPDATE voice_personalization_contexts
                SET sample_count = sample_count + 1,
                    last_learned_at = ?,
                    updated_at = ?
                WHERE id = ?
            """, arguments: [
                Self.millis(observedAt),
                Self.millis(observedAt),
                draft.contextID
            ])
        }

        return VoicePersonalizationSample(
            id: id,
            contextID: draft.contextID,
            transcriptID: draft.transcriptID,
            before: draft.before,
            after: draft.after,
            diffOffset: draft.diffOffset,
            diffLength: draft.diffLength,
            observedAt: observedAt,
            expiresAt: expiresAt,
            summarized: false
        )
    }

    public func listRecentSamples(contextID: String, limit: Int) throws -> [VoicePersonalizationSample] {
        let normalizedLimit = max(1, limit)
        return try db.queue.read { conn in
            let rows = try Row.fetchAll(conn, sql: """
                SELECT id, context_id, transcript_id, encrypted_payload,
                       observed_at, expires_at, summarized
                FROM voice_personalization_samples
                WHERE context_id = ?
                ORDER BY observed_at DESC
                LIMIT ?
            """, arguments: [contextID, normalizedLimit])
            return try rows.map { try self.sample(from: $0) }
        }
    }

    public func listUnsummarizedSamples(contextID: String, olderThan: Date? = nil) throws -> [VoicePersonalizationSample] {
        try db.queue.read { conn in
            let rows: [Row]
            if let olderThan {
                rows = try Row.fetchAll(conn, sql: """
                    SELECT id, context_id, transcript_id, encrypted_payload,
                           observed_at, expires_at, summarized
                    FROM voice_personalization_samples
                    WHERE context_id = ? AND summarized = 0 AND observed_at <= ?
                    ORDER BY observed_at ASC
                """, arguments: [contextID, Self.millis(olderThan)])
            } else {
                rows = try Row.fetchAll(conn, sql: """
                    SELECT id, context_id, transcript_id, encrypted_payload,
                           observed_at, expires_at, summarized
                    FROM voice_personalization_samples
                    WHERE context_id = ? AND summarized = 0
                    ORDER BY observed_at ASC
                """, arguments: [contextID])
            }
            return try rows.map { try self.sample(from: $0) }
        }
    }

    public func markSamplesSummarized(ids: [String]) throws {
        guard !ids.isEmpty else { return }
        try db.queue.write { conn in
            for id in ids {
                try conn.execute(
                    sql: "UPDATE voice_personalization_samples SET summarized = 1 WHERE id = ?",
                    arguments: [id]
                )
            }
        }
    }

    public func deleteSamples(ids: [String]) throws {
        guard !ids.isEmpty else { return }
        try db.queue.write { conn in
            for id in ids {
                let contextID = try String.fetchOne(
                    conn,
                    sql: "SELECT context_id FROM voice_personalization_samples WHERE id = ?",
                    arguments: [id]
                )
                try conn.execute(
                    sql: "DELETE FROM voice_personalization_samples WHERE id = ?",
                    arguments: [id]
                )
                if let contextID {
                    try conn.execute(sql: """
                        UPDATE voice_personalization_contexts
                        SET sample_count = MAX(0, sample_count - 1),
                            updated_at = ?
                        WHERE id = ?
                    """, arguments: [Self.millis(self.now()), contextID])
                }
            }
        }
    }

    public func expireSamplesByCount(contextID: String, max: Int) throws -> Int {
        let normalizedMax = Swift.max(0, max)
        return try db.queue.write { conn in
            let toDelete = try String.fetchAll(conn, sql: """
                SELECT id FROM voice_personalization_samples
                WHERE context_id = ?
                ORDER BY observed_at DESC
                LIMIT -1 OFFSET ?
            """, arguments: [contextID, normalizedMax])

            for id in toDelete {
                try conn.execute(
                    sql: "DELETE FROM voice_personalization_samples WHERE id = ?",
                    arguments: [id]
                )
            }

            if !toDelete.isEmpty {
                try conn.execute(sql: """
                    UPDATE voice_personalization_contexts
                    SET sample_count = MAX(0, sample_count - ?),
                        updated_at = ?
                    WHERE id = ?
                """, arguments: [toDelete.count, Self.millis(self.now()), contextID])
            }

            return toDelete.count
        }
    }

    public func expireSamplesByDate() throws -> Int {
        try db.queue.write { conn in
            let nowMs = Self.millis(self.now())
            let rows = try Row.fetchAll(conn, sql: """
                SELECT id, context_id FROM voice_personalization_samples
                WHERE expires_at <= ?
            """, arguments: [nowMs])

            var deletedPerContext: [String: Int] = [:]
            for row in rows {
                let id: String = row["id"]
                let ctx: String = row["context_id"]
                try conn.execute(
                    sql: "DELETE FROM voice_personalization_samples WHERE id = ?",
                    arguments: [id]
                )
                deletedPerContext[ctx, default: 0] += 1
            }

            for (ctx, count) in deletedPerContext {
                try conn.execute(sql: """
                    UPDATE voice_personalization_contexts
                    SET sample_count = MAX(0, sample_count - ?),
                        updated_at = ?
                    WHERE id = ?
                """, arguments: [count, nowMs, ctx])
            }

            return rows.count
        }
    }

    public func setSummary(contextID: String, summary: String, sourceSampleCount: Int) throws {
        let plaintext = Data(summary.utf8)
        let envelope = try Cipher.seal(plaintext, with: key)
        let nowMs = Self.millis(now())
        try db.queue.write { conn in
            try conn.execute(sql: """
                UPDATE voice_personalization_contexts
                SET encrypted_summary = ?,
                    summary_source_count = ?,
                    summary_generated_at = ?,
                    updated_at = ?
                WHERE id = ?
            """, arguments: [
                envelope.combined,
                sourceSampleCount,
                nowMs,
                nowMs,
                contextID
            ])
        }
    }

    public func clearSummary(contextID: String) throws {
        let nowMs = Self.millis(now())
        try db.queue.write { conn in
            try conn.execute(sql: """
                UPDATE voice_personalization_contexts
                SET encrypted_summary = NULL,
                    summary_source_count = 0,
                    summary_generated_at = NULL,
                    updated_at = ?
                WHERE id = ?
            """, arguments: [nowMs, contextID])
        }
    }

    private let contextSelect = """
        SELECT id, bundle_id, display_name, enabled,
               asr_model_id, auto_submit_key, custom_prompt_override, style_notes,
               encrypted_summary, summary_source_count, summary_generated_at,
               sample_count, last_learned_at, created_at, updated_at
        FROM voice_personalization_contexts
    """

    private func context(from row: Row) throws -> VoicePersonalizationContext {
        let summary: String?
        if let summaryBlob = row["encrypted_summary"] as Data? {
            let envelope = Envelope(combined: summaryBlob)
            let decrypted = try Cipher.open(envelope, with: key)
            summary = String(data: decrypted, encoding: .utf8)
        } else {
            summary = nil
        }

        let autoSubmit: VoiceAutoSubmitKey?
        if let raw = row["auto_submit_key"] as String? {
            autoSubmit = VoiceAutoSubmitKey(rawValue: raw)
        } else {
            autoSubmit = nil
        }

        return VoicePersonalizationContext(
            id: row["id"],
            bundleID: row["bundle_id"],
            displayName: row["display_name"],
            enabled: (row["enabled"] as Int64) != 0,
            asrModelID: row["asr_model_id"] as String?,
            autoSubmitKey: autoSubmit,
            customPromptOverride: row["custom_prompt_override"] as String?,
            styleNotes: row["style_notes"] as String?,
            summary: summary,
            summarySourceCount: Int(row["summary_source_count"] as Int64),
            summaryGeneratedAt: (row["summary_generated_at"] as Int64?).map { Self.date(from: $0) },
            sampleCount: Int(row["sample_count"] as Int64),
            lastLearnedAt: (row["last_learned_at"] as Int64?).map { Self.date(from: $0) },
            createdAt: Self.date(from: row["created_at"] as Int64),
            updatedAt: Self.date(from: row["updated_at"] as Int64)
        )
    }

    private func sample(from row: Row) throws -> VoicePersonalizationSample {
        let blob = row["encrypted_payload"] as Data
        let envelope = Envelope(combined: blob)
        let plaintext = try Cipher.open(envelope, with: key)
        let payload = try JSONDecoder().decode(EncryptedSamplePayload.self, from: plaintext)
        guard payload.v == EncryptedSamplePayload.currentVersion else {
            throw VoicePersonalizationStoreError.unsupportedSchemaVersion(payload.v)
        }

        return VoicePersonalizationSample(
            id: row["id"],
            contextID: row["context_id"],
            transcriptID: row["transcript_id"] as String?,
            before: payload.before,
            after: payload.after,
            diffOffset: payload.diffOffset,
            diffLength: payload.diffLength,
            observedAt: Self.date(from: row["observed_at"] as Int64),
            expiresAt: Self.date(from: row["expires_at"] as Int64),
            summarized: (row["summarized"] as Int64) != 0
        )
    }

    private static func millis(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    private static func date(from millis: Int64) -> Date {
        Date(timeIntervalSince1970: Double(millis) / 1000)
    }
}
