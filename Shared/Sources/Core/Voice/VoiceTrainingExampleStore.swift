import CryptoKit
import Foundation
import GRDB

public struct VoiceTrainingExampleDraft: Equatable, Sendable {
    public var transcriptID: String
    public var rawText: String
    public var cleanedText: String
    public var finalText: String
    public var appBundleID: String?
    public var language: VoiceLanguage
    public var modelIdentifier: String
    public var audioPath: String?
    public var quality: VoiceTrainingExampleQuality
    public var qualityReason: String?

    public init(
        transcriptID: String,
        rawText: String,
        cleanedText: String,
        finalText: String,
        appBundleID: String?,
        language: VoiceLanguage,
        modelIdentifier: String,
        audioPath: String?,
        quality: VoiceTrainingExampleQuality = .medium,
        qualityReason: String? = "awaiting_post_edit_verification"
    ) {
        self.transcriptID = transcriptID
        self.rawText = rawText
        self.cleanedText = cleanedText
        self.finalText = finalText
        self.appBundleID = appBundleID
        self.language = language
        self.modelIdentifier = modelIdentifier
        self.audioPath = audioPath
        self.quality = quality
        self.qualityReason = qualityReason
    }
}

public struct VoiceTrainingExample: Identifiable, Equatable, Sendable {
    public let id: String
    public let transcriptID: String
    public let rawText: String
    public let cleanedText: String
    public let finalText: String
    public let wasEdited: Bool
    public let appBundleID: String?
    public let language: VoiceLanguage
    public let modelIdentifier: String
    public let audioPath: String?
    public let quality: VoiceTrainingExampleQuality
    public let qualityReason: String?
    public let createdAt: Date
    public let updatedAt: Date
}

public final class VoiceTrainingExampleStore: @unchecked Sendable {
    private let db: Database
    private let key: SymmetricKey
    private let audioRoot: URL
    private let now: () -> Date

    public init(
        database: Database,
        deviceKey: SymmetricKey,
        audioRoot: URL,
        now: @escaping () -> Date = Date.init
    ) {
        db = database
        key = deviceKey
        self.audioRoot = audioRoot
        self.now = now
    }

    @discardableResult
    public func save(_ draft: VoiceTrainingExampleDraft) throws -> VoiceTrainingExample {
        let id = UUID().uuidString
        let timestamp = Self.millis(now())
        let payload = VoiceTrainingExamplePayload(
            rawText: draft.rawText,
            cleanedText: draft.cleanedText,
            finalText: draft.finalText,
            wasEdited: draft.finalText != draft.cleanedText,
            quality: draft.quality,
            qualityReason: draft.qualityReason
        )
        let encryptedPayload = try Cipher.seal(JSONEncoder().encode(payload), with: key).combined

        try db.queue.write { conn in
            try conn.execute(sql: """
                INSERT INTO voice_training_examples (
                    id, transcript_id, app_bundle_id, language, model_identifier,
                    audio_path, encrypted_payload, created_at, updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                id,
                draft.transcriptID,
                draft.appBundleID,
                draft.language.rawValue,
                draft.modelIdentifier,
                draft.audioPath,
                encryptedPayload,
                timestamp,
                timestamp
            ])
        }

        guard let example = try fetch(transcriptID: draft.transcriptID) else {
            throw VoiceTrainingExampleStoreError.exampleNotFound
        }
        return example
    }

    public func saveEncryptedAudio(_ wavData: Data, id: String) throws -> String {
        try FileManager.default.createDirectory(at: audioRoot, withIntermediateDirectories: true)
        let envelope = try Cipher.seal(wavData, with: key)
        let url = audioRoot.appendingPathComponent("\(id).wav.aesgcm", isDirectory: false)
        try envelope.combined.write(to: url, options: .atomic)
        return url.path
    }

    public func updateFinalText(
        transcriptID: String,
        finalText: String,
        quality: VoiceTrainingExampleQuality = .high,
        qualityReason: String? = "post_edit_final_text_observed"
    ) throws {
        let timestamp = Self.millis(now())
        try db.queue.write { conn in
            guard let row = try Row.fetchOne(
                conn,
                sql: "SELECT encrypted_payload FROM voice_training_examples WHERE transcript_id = ?",
                arguments: [transcriptID]
            ) else {
                throw VoiceTrainingExampleStoreError.exampleNotFound
            }

            let encryptedPayload: Data = row["encrypted_payload"]
            let data = try Cipher.open(Envelope(combined: encryptedPayload), with: key)
            var payload = try JSONDecoder().decode(VoiceTrainingExamplePayload.self, from: data)
            payload.finalText = finalText
            payload.wasEdited = finalText != payload.cleanedText
            payload.quality = quality
            payload.qualityReason = qualityReason

            let nextPayload = try Cipher.seal(JSONEncoder().encode(payload), with: key).combined
            try conn.execute(sql: """
                UPDATE voice_training_examples
                SET encrypted_payload = ?, updated_at = ?
                WHERE transcript_id = ?
            """, arguments: [nextPayload, timestamp, transcriptID])
        }
    }

    public func updateQuality(
        transcriptID: String,
        quality: VoiceTrainingExampleQuality,
        qualityReason: String?
    ) throws {
        let timestamp = Self.millis(now())
        try db.queue.write { conn in
            guard let row = try Row.fetchOne(
                conn,
                sql: "SELECT encrypted_payload FROM voice_training_examples WHERE transcript_id = ?",
                arguments: [transcriptID]
            ) else {
                throw VoiceTrainingExampleStoreError.exampleNotFound
            }

            let encryptedPayload: Data = row["encrypted_payload"]
            let data = try Cipher.open(Envelope(combined: encryptedPayload), with: key)
            var payload = try JSONDecoder().decode(VoiceTrainingExamplePayload.self, from: data)
            payload.quality = quality
            payload.qualityReason = qualityReason

            let nextPayload = try Cipher.seal(JSONEncoder().encode(payload), with: key).combined
            try conn.execute(sql: """
                UPDATE voice_training_examples
                SET encrypted_payload = ?, updated_at = ?
                WHERE transcript_id = ?
            """, arguments: [nextPayload, timestamp, transcriptID])
        }
    }

    public func fetch(transcriptID: String) throws -> VoiceTrainingExample? {
        try db.queue.read { conn in
            try Row.fetchOne(
                conn,
                sql: Self.selectSQL + " WHERE transcript_id = ?",
                arguments: [transcriptID]
            ).map { try self.example(from: $0) }
        }
    }

    public func count() throws -> Int {
        try db.queue.read { conn in
            try Int.fetchOne(conn, sql: "SELECT COUNT(*) FROM voice_training_examples") ?? 0
        }
    }

    public func clearAll() throws {
        let audioPaths = try db.queue.write { conn -> [String] in
            let rows = try Row.fetchAll(conn, sql: "SELECT audio_path FROM voice_training_examples")
            let paths: [String] = rows.compactMap { $0["audio_path"] }
            try conn.execute(sql: "DELETE FROM voice_training_examples")
            return paths
        }

        for path in audioPaths {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    private func example(from row: Row) throws -> VoiceTrainingExample {
        let encryptedPayload: Data = row["encrypted_payload"]
        let data = try Cipher.open(Envelope(combined: encryptedPayload), with: key)
        let payload = try JSONDecoder().decode(VoiceTrainingExamplePayload.self, from: data)

        return VoiceTrainingExample(
            id: row["id"],
            transcriptID: row["transcript_id"],
            rawText: payload.rawText,
            cleanedText: payload.cleanedText,
            finalText: payload.finalText,
            wasEdited: payload.wasEdited,
            appBundleID: row["app_bundle_id"],
            language: VoiceLanguage(rawValue: row["language"]) ?? .unknown,
            modelIdentifier: row["model_identifier"],
            audioPath: row["audio_path"],
            quality: payload.quality,
            qualityReason: payload.qualityReason,
            createdAt: Date(timeIntervalSince1970: Double(row["created_at"] as Int64) / 1000),
            updatedAt: Date(timeIntervalSince1970: Double(row["updated_at"] as Int64) / 1000)
        )
    }

    private static let selectSQL = """
        SELECT id, transcript_id, app_bundle_id, language, model_identifier,
               audio_path, encrypted_payload, created_at, updated_at
        FROM voice_training_examples
    """

    private static func millis(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }
}

public enum VoiceTrainingExampleStoreError: Error, Equatable {
    case exampleNotFound
}

private struct VoiceTrainingExamplePayload: Codable {
    var rawText: String
    var cleanedText: String
    var finalText: String
    var wasEdited: Bool
    var quality: VoiceTrainingExampleQuality
    var qualityReason: String?

    init(
        rawText: String,
        cleanedText: String,
        finalText: String,
        wasEdited: Bool,
        quality: VoiceTrainingExampleQuality,
        qualityReason: String?
    ) {
        self.rawText = rawText
        self.cleanedText = cleanedText
        self.finalText = finalText
        self.wasEdited = wasEdited
        self.quality = quality
        self.qualityReason = qualityReason
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rawText = try container.decode(String.self, forKey: .rawText)
        cleanedText = try container.decode(String.self, forKey: .cleanedText)
        finalText = try container.decode(String.self, forKey: .finalText)
        wasEdited = try container.decode(Bool.self, forKey: .wasEdited)

        if let rawQuality = try container.decodeIfPresent(String.self, forKey: .quality),
           let decodedQuality = VoiceTrainingExampleQuality(rawValue: rawQuality)
        {
            quality = decodedQuality
        } else {
            quality = .medium
        }
        qualityReason = try container.decodeIfPresent(String.self, forKey: .qualityReason)
    }
}
