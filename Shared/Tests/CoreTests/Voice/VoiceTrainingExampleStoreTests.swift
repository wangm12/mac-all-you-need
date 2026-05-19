@testable import Core
import CryptoKit
import GRDB
import XCTest

final class VoiceTrainingExampleStoreTests: XCTestCase {
    private var tempDir: URL!
    private var db: Core.Database!
    private var key: SymmetricKey!
    private var store: VoiceTrainingExampleStore!
    private var transcripts: VoiceTranscriptStore!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceTrainingExampleStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        db = try Core.Database(
            url: tempDir.appendingPathComponent("voice.sqlite"),
            migrations: ClipboardStore.migrations
        )
        key = SymmetricKey(size: .bits256)
        store = VoiceTrainingExampleStore(
            database: db,
            deviceKey: key,
            audioRoot: tempDir.appendingPathComponent("audio", isDirectory: true)
        )
        transcripts = VoiceTranscriptStore(database: db)
    }

    override func tearDownWithError() throws {
        transcripts = nil
        store = nil
        db = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testSaveAndFetchTrainingExample() throws {
        let transcript = try saveTranscript()

        try store.save(.init(
            transcriptID: transcript.id,
            rawText: "hello world",
            cleanedText: "Hello world.",
            finalText: "Hello, world.",
            appBundleID: "com.apple.TextEdit",
            language: .english,
            modelIdentifier: "qwen3",
            audioPath: "/tmp/audio.wav.aesgcm",
            quality: .high,
            qualityReason: "verified_post_edit"
        ))

        let fetched = try XCTUnwrap(store.fetch(transcriptID: transcript.id))
        XCTAssertEqual(fetched.rawText, "hello world")
        XCTAssertEqual(fetched.cleanedText, "Hello world.")
        XCTAssertEqual(fetched.finalText, "Hello, world.")
        XCTAssertTrue(fetched.wasEdited)
        XCTAssertEqual(fetched.appBundleID, "com.apple.TextEdit")
        XCTAssertEqual(fetched.audioPath, "/tmp/audio.wav.aesgcm")
        XCTAssertEqual(fetched.quality, .high)
        XCTAssertEqual(fetched.qualityReason, "verified_post_edit")
    }

    func testPayloadIsEncryptedAtRest() throws {
        let transcript = try saveTranscript()
        let secret = "private final text"

        try store.save(.init(
            transcriptID: transcript.id,
            rawText: "raw",
            cleanedText: "clean",
            finalText: secret,
            appBundleID: nil,
            language: .english,
            modelIdentifier: "qwen3",
            audioPath: nil
        ))

        let blob = try db.queue.read { conn in
            try Data.fetchOne(
                conn,
                sql: "SELECT encrypted_payload FROM voice_training_examples WHERE transcript_id = ?",
                arguments: [transcript.id]
            )
        }
        XCTAssertNotNil(blob)
        let blobString = String(data: blob ?? Data(), encoding: .utf8) ?? ""
        XCTAssertFalse(blobString.contains(secret))
    }

    func testUpdateFinalTextMarksEditedAndCanUpgradeQuality() throws {
        let transcript = try saveTranscript()
        try store.save(.init(
            transcriptID: transcript.id,
            rawText: "raw",
            cleanedText: "clean",
            finalText: "clean",
            appBundleID: nil,
            language: .english,
            modelIdentifier: "qwen3",
            audioPath: nil
        ))

        try store.updateFinalText(
            transcriptID: transcript.id,
            finalText: "final",
            quality: .high,
            qualityReason: "post_edit_final_text_observed"
        )

        let fetched = try XCTUnwrap(store.fetch(transcriptID: transcript.id))
        XCTAssertEqual(fetched.finalText, "final")
        XCTAssertTrue(fetched.wasEdited)
        XCTAssertEqual(fetched.quality, .high)
        XCTAssertEqual(fetched.qualityReason, "post_edit_final_text_observed")
    }

    func testUpdateQualityReasonDoesNotChangeFinalText() throws {
        let transcript = try saveTranscript()
        try store.save(.init(
            transcriptID: transcript.id,
            rawText: "raw",
            cleanedText: "clean",
            finalText: "clean",
            appBundleID: nil,
            language: .english,
            modelIdentifier: "qwen3",
            audioPath: nil
        ))

        try store.updateQuality(
            transcriptID: transcript.id,
            quality: .medium,
            qualityReason: "post_edit_verification_unavailable"
        )

        let fetched = try XCTUnwrap(store.fetch(transcriptID: transcript.id))
        XCTAssertEqual(fetched.finalText, "clean")
        XCTAssertFalse(fetched.wasEdited)
        XCTAssertEqual(fetched.quality, .medium)
        XCTAssertEqual(fetched.qualityReason, "post_edit_verification_unavailable")
    }

    func testSaveDefaultsQualityToMedium() throws {
        let transcript = try saveTranscript()

        try store.save(.init(
            transcriptID: transcript.id,
            rawText: "raw",
            cleanedText: "clean",
            finalText: "clean",
            appBundleID: nil,
            language: .english,
            modelIdentifier: "qwen3",
            audioPath: nil
        ))

        let fetched = try XCTUnwrap(store.fetch(transcriptID: transcript.id))
        XCTAssertEqual(fetched.quality, .medium)
        XCTAssertEqual(fetched.qualityReason, "awaiting_post_edit_verification")
    }

    func testLegacyPayloadDefaultsQualityToMedium() throws {
        let transcript = try saveTranscript()
        let legacyPayload = try JSONEncoder().encode(LegacyPayload(
            rawText: "raw",
            cleanedText: "clean",
            finalText: "clean",
            wasEdited: false
        ))
        let encryptedPayload = try Cipher.seal(legacyPayload, with: key).combined

        try db.queue.write { conn in
            try conn.execute(sql: """
                INSERT INTO voice_training_examples (
                    id, transcript_id, app_bundle_id, language, model_identifier,
                    audio_path, encrypted_payload, created_at, updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                UUID().uuidString,
                transcript.id,
                nil,
                VoiceLanguage.english.rawValue,
                "qwen3",
                nil,
                encryptedPayload,
                Int64(1000),
                Int64(1000)
            ])
        }

        let fetched = try XCTUnwrap(store.fetch(transcriptID: transcript.id))
        XCTAssertEqual(fetched.quality, .medium)
        XCTAssertNil(fetched.qualityReason)
    }

    func testClearAllDeletesRowsAndAudioFiles() throws {
        let transcript = try saveTranscript()
        let audioPath = try store.saveEncryptedAudio(Data("wav".utf8), id: transcript.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: audioPath))
        try store.save(.init(
            transcriptID: transcript.id,
            rawText: "raw",
            cleanedText: "clean",
            finalText: "clean",
            appBundleID: nil,
            language: .english,
            modelIdentifier: "qwen3",
            audioPath: audioPath
        ))

        try store.clearAll()

        XCTAssertEqual(try store.count(), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: audioPath))
    }

    func testLoadEncryptedAudioRoundtripsWAVBytes() throws {
        let original = Data([0x52, 0x49, 0x46, 0x46, 0x01, 0x02, 0x03, 0x04])
        let path = try store.saveEncryptedAudio(original, id: "abc")

        let loaded = try store.loadEncryptedAudio(path: path)
        XCTAssertEqual(loaded, original)
    }

    func testAudioRootMatchesConstructor() {
        XCTAssertEqual(store.audioRoot, tempDir.appendingPathComponent("audio", isDirectory: true))
    }

    private func saveTranscript() throws -> VoiceTranscript {
        try transcripts.save(.init(
            startedAt: Date(timeIntervalSince1970: 1),
            endedAt: Date(timeIntervalSince1970: 2),
            rawText: "raw",
            cleanedText: "clean",
            appBundleID: nil,
            language: .english,
            modelIdentifier: "qwen3",
            audioPath: nil
        ))
    }
}

private struct LegacyPayload: Encodable {
    let rawText: String
    let cleanedText: String
    let finalText: String
    let wasEdited: Bool
}
