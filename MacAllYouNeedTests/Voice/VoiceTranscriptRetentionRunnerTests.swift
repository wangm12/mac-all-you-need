@testable import Core
import CryptoKit
@testable import MacAllYouNeed
import XCTest

final class VoiceTranscriptRetentionRunnerTests: XCTestCase {
    private var tempDir: URL!
    private var transcriptStore: VoiceTranscriptStore!
    private var trainingStore: VoiceTrainingExampleStore!
    private var audioRoot: URL!
    let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceRetentionRunnerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let db = try Core.Database(
            url: tempDir.appendingPathComponent("voice.sqlite"),
            migrations: ClipboardStore.migrations
        )
        transcriptStore = VoiceTranscriptStore(database: db)
        let key = SymmetricKey(size: .bits256)
        audioRoot = tempDir.appendingPathComponent("audio", isDirectory: true)
        trainingStore = VoiceTrainingExampleStore(
            database: db,
            deviceKey: key,
            audioRoot: audioRoot
        )
    }

    override func tearDownWithError() throws {
        transcriptStore = nil
        trainingStore = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testSweep_forever_doesNothing() throws {
        try seedTranscript(ageDays: 100, withAudio: true)
        let runner = makeRunner(retention: .forever)
        runner.sweepNow()
        XCTAssertEqual(try transcriptStore.listRecent(limit: 10).count, 1)
        XCTAssertEqual(audioFileCount(), 1)
    }

    func testSweep_30d_deletesOldRows_andAudio() throws {
        try seedTranscript(ageDays: 100, withAudio: true)
        try seedTranscript(ageDays: 1, withAudio: true)
        let runner = makeRunner(retention: .days30)
        runner.sweepNow()
        let remaining = try transcriptStore.listRecent(limit: 10)
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(audioFileCount(), 1)
    }

    func testOrphanSweep_keepsFiles_referencedByTrainingExample() throws {
        // Seed a transcript and a corresponding training example with audio.
        let transcriptID = UUID().uuidString
        let ended = fixedNow.addingTimeInterval(-1 * 86_400) // 1 day old
        _ = try transcriptStore.save(VoiceTranscriptDraft(
            startedAt: ended.addingTimeInterval(-1),
            endedAt: ended,
            rawText: "r", cleanedText: "c",
            appBundleID: nil, language: .english,
            modelIdentifier: "m", audioPath: nil
        ), existingID: transcriptID)

        let wav = VoiceAudioCodec.encodeWAV(samples: [0.1], sampleRate: 16_000)
        let path = try trainingStore.saveEncryptedAudio(wav, id: transcriptID)
        try trainingStore.save(.init(
            transcriptID: transcriptID,
            rawText: "", cleanedText: "", finalText: "",
            appBundleID: nil, language: .english,
            modelIdentifier: "m", audioPath: path,
            quality: .medium, qualityReason: nil
        ))
        XCTAssertEqual(audioFileCount(), 1)

        // Use forever retention so transcript row is not expired.
        // The orphan sweep must not remove audio referenced by the training example.
        let runner = makeRunner(retention: .forever)
        runner.sweepNow()

        XCTAssertEqual(audioFileCount(), 1,
            "audio file referenced by training example must survive orphan sweep")
    }

    // MARK: - Helpers

    private func makeRunner(retention: VoiceHistoryRetention) -> VoiceTranscriptRetentionRunner {
        VoiceTranscriptRetentionRunner(
            transcriptStore: transcriptStore,
            trainingExampleStore: trainingStore,
            audioRoot: audioRoot,
            historySettings: { VoiceHistorySettings(retention: retention, saveAudio: true) },
            now: { self.fixedNow }
        )
    }

    @discardableResult
    private func seedTranscript(ageDays: Int, withAudio: Bool) throws -> VoiceTranscript {
        let id = UUID().uuidString
        let ended = fixedNow.addingTimeInterval(-Double(ageDays) * 86_400)
        let audioPath: String?
        if withAudio {
            let wav = VoiceAudioCodec.encodeWAV(samples: [0.1], sampleRate: 16_000)
            audioPath = try trainingStore.saveEncryptedAudio(wav, id: id)
        } else {
            audioPath = nil
        }
        return try transcriptStore.save(VoiceTranscriptDraft(
            startedAt: ended.addingTimeInterval(-1),
            endedAt: ended,
            rawText: "r", cleanedText: "c",
            appBundleID: nil, language: .english,
            modelIdentifier: "m", audioPath: audioPath
        ), existingID: id)
    }

    private func audioFileCount() -> Int {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: audioRoot.path)) ?? []
        return files.filter { $0.hasSuffix(".aesgcm") }.count
    }
}
