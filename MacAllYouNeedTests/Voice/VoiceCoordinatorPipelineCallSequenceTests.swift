@testable import Core
import CryptoKit
@testable import MacAllYouNeed
import XCTest

/// The "spine" test for the voice pipeline decomposition. Drives the full
/// `processCapturedAudio` path end-to-end with mock ASR + cleanup + paster +
/// learning monitor and asserts:
///
///   (a) the phases run in the exact expected order with the exact inputs,
///   (b) the final transcript lands in the transcript store,
///   (c) the undo context contains the captured audio + ASR result the user
///       would need to replay if they cancelled.
/// Each phase records one tag here so tests can assert the order phases
/// fired AND the inputs they observed at the moment of firing.
final class PipelineCallLog: @unchecked Sendable {
    private(set) var entries: [String] = []
    private let lock = NSLock()
    func record(_ entry: String) {
        lock.lock()
        entries.append(entry)
        lock.unlock()
    }
}

@MainActor
final class VoiceCoordinatorPipelineCallSequenceTests: XCTestCase {

    // MARK: - Stubs

    private final class StubASREngine: VoiceTranscriptionEngine, @unchecked Sendable {
        let modelIdentifier: String = "stub-asr"
        let result: VoiceTranscriptionResult
        let log: PipelineCallLog
        var callCount = 0
        init(result: VoiceTranscriptionResult, log: PipelineCallLog) {
            self.result = result
            self.log = log
        }

        func transcribe(
            samples: [Float],
            sampleRate _: Double,
            options _: VoiceTranscriptionOptions
        ) async throws -> VoiceTranscriptionResult {
            callCount += 1
            log.record("asr(samples=\(samples.count))")
            return result
        }
    }

    // MARK: - Fixtures

    private var tempDir: URL!
    private var transcriptStore: VoiceTranscriptStore!
    private var trainingStore: VoiceTrainingExampleStore!
    private var callLog: PipelineCallLog!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceCoordPipelineTests-\(UUID().uuidString)", isDirectory: true)
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
        callLog = PipelineCallLog()
    }

    override func tearDownWithError() throws {
        transcriptStore = nil
        trainingStore = nil
        callLog = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Spine: full pipeline call sequence

    func testFullPipeline_runsPhasesInOrder_andPersistsTranscript() async throws {
        let asrResult = VoiceTranscriptionResult(
            text: "hello world",
            language: .english,
            modelIdentifier: "stub-asr"
        )
        let engine = StubASREngine(result: asrResult, log: callLog)
        let captured = makeCaptured(sampleCount: 1600)
        let coordinator = makeCoordinator(engine: engine)

        await coordinator.processCapturedAudio(
            captured: captured,
            presetASRResult: nil,
            presetAppBundleID: "com.apple.TextEdit"
        )

        // (a) Phase call sequence: ASR, then cleanup, then paste, then learning.
        XCTAssertEqual(callLog.entries, [
            "asr(samples=\(captured.samples.count))",
            "cleanup(text=hello world)",
            "snapshotFocused",
            "paste(hello world)",
            "learning(text=hello world,bundle=com.apple.TextEdit)"
        ], "phases must run in ASR → cleanup → snapshot → paste → learning order")

        // (b) Final transcript persisted to the store.
        let saved = try transcriptStore.listRecent(limit: 10)
        XCTAssertEqual(saved.count, 1, "exactly one transcript row persisted")
        XCTAssertEqual(saved.first?.rawText, "hello world")
        XCTAssertEqual(saved.first?.cleanedText, "hello world")
        XCTAssertEqual(saved.first?.appBundleID, "com.apple.TextEdit")
    }

    func testPipeline_withPresetASRResult_skipsASRPhase() async throws {
        let presetASR = VoiceTranscriptionResult(
            text: "undo replay text",
            language: .english,
            modelIdentifier: "stub-asr"
        )
        let engine = StubASREngine(
            result: .init(text: "should not be called", language: .english, modelIdentifier: ""),
            log: callLog
        )
        let captured = makeCaptured(sampleCount: 1600)
        let coordinator = makeCoordinator(engine: engine)

        await coordinator.processCapturedAudio(
            captured: captured,
            presetASRResult: presetASR,
            presetAppBundleID: "com.apple.Mail"
        )

        XCTAssertEqual(engine.callCount, 0,
                       "ASR must be skipped when presetASRResult is provided (undo replay)")
        XCTAssertFalse(callLog.entries.contains(where: { $0.hasPrefix("asr(") }),
                       "no asr(...) tag should appear when ASR is skipped")
        // Cleanup must still run with the preset's text.
        XCTAssertTrue(callLog.entries.contains("cleanup(text=undo replay text)"))
        XCTAssertTrue(callLog.entries.contains("paste(undo replay text)"))

        let saved = try transcriptStore.listRecent(limit: 10)
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.rawText, "undo replay text")
    }

    // MARK: - Undo bookkeeping

    func testCancelDuringTranscribing_recordsUndoContext_withCapturedAudio() async throws {
        // Block the ASR engine indefinitely so the coordinator stays in
        // .transcribing long enough for us to cancel mid-flight.
        let engine = BlockingASREngine(log: callLog)
        let captured = makeCaptured(sampleCount: 1600)
        let coordinator = makeCoordinator(engine: engine)

        let processTask = Task {
            await coordinator.processCapturedAudio(
                captured: captured,
                presetASRResult: nil,
                presetAppBundleID: "com.apple.TextEdit"
            )
        }
        // Yield so processCapturedAudio reaches the await on engine.transcribe.
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(coordinator.state, .transcribing,
                       "precondition: pipeline must be parked in .transcribing")

        coordinator.cancelCurrentOperation()

        // Inspect undo context BEFORE the in-flight task tears down (cancel
        // races the engine continuation — give the scheduler a beat first).
        try await Task.sleep(for: .milliseconds(20))

        XCTAssertEqual(coordinator.state, .idle,
                       "cancel must drop state to .idle for the next dictation")
        let undo = coordinator.undoBookkeeping.pendingUndo
        XCTAssertNotNil(undo, "cancel during transcribing must record an undo snapshot")
        XCTAssertEqual(undo?.captured.samples.count, captured.samples.count,
                       "undo must hold the captured audio so replay does not require re-dictation")
        XCTAssertEqual(undo?.appBundleID, "com.apple.TextEdit",
                       "undo must retain the dictation's target bundle id")

        engine.resume(throwing: CancellationError())
        _ = await processTask.value
    }

    func testPasteFailure_persistsFailedTranscriptWithAudio() async throws {
        let asrResult = VoiceTranscriptionResult(
            text: "hello world",
            language: .english,
            modelIdentifier: "stub-asr"
        )
        let engine = StubASREngine(result: asrResult, log: callLog)
        let captured = makeCaptured(sampleCount: 1600)
        let coordinator = VoiceCoordinator(
            transcripts: transcriptStore,
            trainingExampleStore: trainingStore,
            engine: engine,
            cleanupPipelineFactory: { _ in VoiceCleanupPipeline() },
            paster: { _, _ in
                CursorPaster.Result(
                    accessibilityTrusted: true,
                    deliveryPath: .clipboardOnly,
                    failureReason: .targetNotWritable
                )
            },
            snapshotFocused: { nil },
            learningStarter: { _, _, _, _, _ in },
            cleanupObserver: { _ in }
        )

        await coordinator.processCapturedAudio(
            captured: captured,
            presetASRResult: nil,
            presetAppBundleID: "com.apple.TextEdit"
        )

        let saved = try transcriptStore.listRecent(limit: 10)
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.status, .failed)
        XCTAssertEqual(saved.first?.failedStage, .paste)
        XCTAssertEqual(saved.first?.failureReason, "paste_targetNotWritable")
        XCTAssertNotNil(saved.first?.audioPath)
    }

    // MARK: - Helpers

    private func makeCaptured(sampleCount: Int) -> CapturedAudio {
        CapturedAudio(
            samples: Array(repeating: Float(0.1), count: sampleCount),
            sampleRate: 16_000,
            startedAt: Date(timeIntervalSince1970: 1),
            endedAt: Date(timeIntervalSince1970: 2),
            peakLevel: 0.5
        )
    }

    private func makeCoordinator(engine: any VoiceTranscriptionEngine) -> VoiceCoordinator {
        let log = callLog!
        return VoiceCoordinator(
            transcripts: transcriptStore,
            trainingExampleStore: trainingStore,
            engine: engine,
            cleanupPipelineFactory: { _ in
                // Local-only cleanup keeps tests offline and deterministic.
                VoiceCleanupPipeline()
            },
            paster: { text, _ in
                log.record("paste(\(text))")
                return CursorPaster.Result(
                    accessibilityTrusted: true,
                    deliveryPath: .preferredAX,
                    failureReason: nil
                )
            },
            snapshotFocused: {
                log.record("snapshotFocused")
                return nil
            },
            learningStarter: { pastedText, _, appBundleID, _, _ in
                log.record("learning(text=\(pastedText),bundle=\(appBundleID ?? "nil"))")
            },
            cleanupObserver: { request in
                log.record("cleanup(text=\(request.rawText))")
            }
        )
    }
}

// MARK: - Blocking ASR engine for cancel-during-transcribing test

private actor BlockingASREngineState {
    private var continuation: CheckedContinuation<Void, Error>?

    func wait() async throws {
        try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func resume(throwing error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

private final class BlockingASREngine: VoiceTranscriptionEngine, @unchecked Sendable {
    let modelIdentifier: String = "blocking-asr"
    private let state = BlockingASREngineState()
    let log: PipelineCallLog
    init(log: PipelineCallLog) { self.log = log }

    func transcribe(
        samples _: [Float],
        sampleRate _: Double,
        options _: VoiceTranscriptionOptions
    ) async throws -> VoiceTranscriptionResult {
        log.record("asr-blocking-entered")
        try await state.wait()
        return VoiceTranscriptionResult(text: "unreachable", language: .english, modelIdentifier: "")
    }

    func resume(throwing error: Error) {
        Task { await state.resume(throwing: error) }
    }
}
