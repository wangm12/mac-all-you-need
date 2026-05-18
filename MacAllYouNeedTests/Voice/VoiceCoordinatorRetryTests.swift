@testable import Core
import CryptoKit
@testable import MacAllYouNeed
import XCTest

@MainActor
final class VoiceCoordinatorRetryTests: XCTestCase {
    private var tempDir: URL!
    private var transcriptStore: VoiceTranscriptStore!
    private var trainingStore: VoiceTrainingExampleStore!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceCoordRetryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let db = try Core.Database(
            url: tempDir.appendingPathComponent("voice.sqlite"),
            migrations: ClipboardStore.migrations
        )
        transcriptStore = VoiceTranscriptStore(database: db)
        let key = SymmetricKey(size: .bits256)
        trainingStore = VoiceTrainingExampleStore(
            database: db,
            deviceKey: key,
            audioRoot: tempDir.appendingPathComponent("audio", isDirectory: true)
        )
    }

    override func tearDownWithError() throws {
        transcriptStore = nil
        trainingStore = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testRetry_insertsNewRow_andPreservesOriginal() async throws {
        let original = try seedTranscriptWithAudio(text: "hi")
        let stubASR = StubASREngine(result: .init(text: "hi there", language: .english, modelIdentifier: "stub"))
        let coordinator = makeCoordinator(asrEngine: stubASR)

        let newTranscript = try await coordinator.retryTranscript(id: original.id)

        XCTAssertNotEqual(newTranscript.id, original.id)
        XCTAssertEqual(newTranscript.rawText, "hi there")
        XCTAssertEqual(newTranscript.audioPath, original.audioPath)

        let listed = try transcriptStore.listRecent(limit: 10)
        XCTAssertEqual(listed.count, 2)
        XCTAssertNotNil(listed.first(where: { $0.id == original.id }))
    }

    func testRetry_throws_noAudio_when_audioPath_nil() async throws {
        let noAudioTranscript = try transcriptStore.save(VoiceTranscriptDraft(
            startedAt: Date(), endedAt: Date(),
            rawText: "hi", cleanedText: "hi",
            appBundleID: nil, language: .english,
            modelIdentifier: "m", audioPath: nil
        ))
        let coordinator = makeCoordinator(
            asrEngine: StubASREngine(result: .init(text: "", language: .english, modelIdentifier: ""))
        )

        do {
            _ = try await coordinator.retryTranscript(id: noAudioTranscript.id)
            XCTFail("Expected VoiceRetryError.noAudio")
        } catch let error as VoiceRetryError {
            XCTAssertEqual(error, .noAudio)
        }
    }

    func testRetry_throws_transcriptNotFound_for_unknown_id() async throws {
        let coordinator = makeCoordinator(
            asrEngine: StubASREngine(result: .init(text: "", language: .english, modelIdentifier: ""))
        )
        do {
            _ = try await coordinator.retryTranscript(id: "nonexistent-id")
            XCTFail("Expected VoiceRetryError.transcriptNotFound")
        } catch let error as VoiceRetryError {
            XCTAssertEqual(error, .transcriptNotFound)
        }
    }

    func testRetry_whenASRFails_leavesOriginalRow_intact() async throws {
        let original = try seedTranscriptWithAudio(text: "hi")
        let failingASR = StubASREngine(error: NSError(domain: "TestASR", code: 1))
        let coordinator = makeCoordinator(asrEngine: failingASR)

        do {
            _ = try await coordinator.retryTranscript(id: original.id)
            XCTFail("Expected error")
        } catch {
            // any error is fine
        }

        let listed = try transcriptStore.listRecent(limit: 10)
        XCTAssertEqual(listed.count, 1)
        XCTAssertEqual(listed.first?.id, original.id)
    }

    // MARK: - Helpers

    private func makeCoordinator(asrEngine: any VoiceTranscriptionEngine) -> VoiceCoordinator {
        VoiceCoordinator(
            transcripts: transcriptStore,
            trainingExampleStore: trainingStore,
            engine: asrEngine
        )
    }

    private func seedTranscriptWithAudio(text: String) throws -> VoiceTranscript {
        let id = UUID().uuidString
        let wav = VoiceAudioCodec.encodeWAV(samples: [0.1, -0.1], sampleRate: 16_000)
        let audioPath = try trainingStore.saveEncryptedAudio(wav, id: id)
        return try transcriptStore.save(VoiceTranscriptDraft(
            startedAt: Date(timeIntervalSince1970: 1),
            endedAt: Date(timeIntervalSince1970: 2),
            rawText: text, cleanedText: text,
            appBundleID: nil, language: .english,
            modelIdentifier: "test", audioPath: audioPath
        ), existingID: id)
    }
}

/// Stub ASR engine for testing.
private final class StubASREngine: VoiceTranscriptionEngine {
    let modelIdentifier: String = "stub"
    private let result: VoiceTranscriptionResult?
    private let stubError: Error?

    init(result: VoiceTranscriptionResult) {
        self.result = result
        self.stubError = nil
    }

    init(error: Error) {
        self.result = nil
        self.stubError = error
    }

    func transcribe(
        samples: [Float],
        sampleRate: Double,
        options: VoiceTranscriptionOptions
    ) async throws -> VoiceTranscriptionResult {
        if let stubError { throw stubError }
        return result!
    }
}
