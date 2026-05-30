@testable import Core
import CryptoKit
@testable import MacAllYouNeed
import XCTest

/// Proves the `.reminder` VoiceIntent routes the cleaned text to the reminder
/// writer and NEVER pastes, while `.dictation` is unchanged (still pastes,
/// never writes a reminder).
@MainActor
final class VoiceCoordinatorReminderIntentTests: XCTestCase {
    private var tempDir: URL!
    private var transcriptStore: VoiceTranscriptStore!
    private var trainingStore: VoiceTrainingExampleStore!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceReminderIntentTests-\(UUID().uuidString)", isDirectory: true)
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

    // MARK: - Stubs

    private final class StubASREngine: VoiceTranscriptionEngine, @unchecked Sendable {
        let modelIdentifier = "stub-asr"
        let result: VoiceTranscriptionResult
        init(text: String) {
            result = VoiceTranscriptionResult(text: text, language: .english, modelIdentifier: "stub-asr")
        }

        func transcribe(samples _: [Float], sampleRate _: Double, options _: VoiceTranscriptionOptions) async throws -> VoiceTranscriptionResult {
            result
        }
    }

    private final class PasteSpy: @unchecked Sendable {
        private(set) var pasted: [String] = []
        func record(_ s: String) { pasted.append(s) }
    }

    private func makeCaptured() -> CapturedAudio {
        CapturedAudio(
            samples: Array(repeating: Float(0.1), count: 1600),
            sampleRate: 16_000,
            startedAt: Date(timeIntervalSince1970: 1),
            endedAt: Date(timeIntervalSince1970: 2),
            peakLevel: 0.5
        )
    }

    private func makeCoordinator(
        text: String,
        paste: PasteSpy,
        reminderSettings: @escaping () -> ReminderSettings = { .default }
    ) -> VoiceCoordinator {
        VoiceCoordinator(
            transcripts: transcriptStore,
            trainingExampleStore: trainingStore,
            engine: StubASREngine(text: text),
            historySettings: { .init() },
            reminderSettings: reminderSettings,
            cleanupPipelineFactory: { _ in VoiceCleanupPipeline() },
            paster: { t in
                paste.record(t)
                return CursorPaster.Result(accessibilityTrusted: true, didPostPasteEvent: true)
            },
            snapshotFocused: { nil },
            learningStarter: { _, _, _, _, _ in },
            cleanupObserver: { _ in }
        )
    }

    func testReminderIntentWritesAndNeverPastes() async throws {
        let paste = PasteSpy()
        let writer = MockReminderWriter()
        let coordinator = makeCoordinator(text: "buy milk", paste: paste)
        coordinator.activeIntent = .reminder
        coordinator.reminderWriterOverride = writer

        await coordinator.processCapturedAudio(
            captured: makeCaptured(),
            presetASRResult: nil,
            presetAppBundleID: "com.apple.TextEdit"
        )

        XCTAssertEqual(writer.created.count, 1, "reminder must be written")
        XCTAssertEqual(writer.created.first?.title, "buy milk")
        XCTAssertTrue(paste.pasted.isEmpty, "reminder intent must NEVER paste")
        XCTAssertEqual(try transcriptStore.listRecent(limit: 10).count, 0,
                       "reminder intent must not persist a dictation transcript")
        XCTAssertEqual(coordinator.activeIntent, .dictation,
                       "intent resets to dictation after a reminder run")
    }

    func testDictationIntentPastesAndNeverWritesReminder() async throws {
        let paste = PasteSpy()
        let writer = MockReminderWriter()
        let coordinator = makeCoordinator(text: "the meeting is at three", paste: paste)
        // Default intent is .dictation. Writer is wired but must not be used.
        coordinator.reminderWriterOverride = writer

        await coordinator.processCapturedAudio(
            captured: makeCaptured(),
            presetASRResult: nil,
            presetAppBundleID: "com.apple.TextEdit"
        )

        XCTAssertEqual(paste.pasted, ["the meeting is at three"], "dictation must paste")
        XCTAssertTrue(writer.created.isEmpty, "dictation must never write a reminder")
        XCTAssertEqual(try transcriptStore.listRecent(limit: 10).count, 1)
    }

    func testSpokenPrefixPromotesToReminderIntent() async throws {
        let paste = PasteSpy()
        let writer = MockReminderWriter()
        let coordinator = makeCoordinator(text: "remind me to call the dentist", paste: paste)
        // Intent starts as .dictation; the spoken prefix should promote it.
        coordinator.reminderWriterOverride = writer

        await coordinator.processCapturedAudio(
            captured: makeCaptured(),
            presetASRResult: nil,
            presetAppBundleID: "com.apple.TextEdit"
        )

        XCTAssertEqual(writer.created.count, 1, "spoken prefix must promote to reminder write")
        XCTAssertTrue(paste.pasted.isEmpty, "promoted reminder must not paste")
    }

    func testSpokenPrefixIgnoredWhenSettingDisabled() async throws {
        let paste = PasteSpy()
        let writer = MockReminderWriter()
        let disabled = ReminderSettings(
            isEnabled: true, defaultListID: nil, spokenPrefixEnabled: false, upcomingIntervalDays: 7
        )
        let coordinator = makeCoordinator(
            text: "remind me to call the dentist", paste: paste, reminderSettings: { disabled }
        )
        coordinator.reminderWriterOverride = writer

        await coordinator.processCapturedAudio(
            captured: makeCaptured(),
            presetASRResult: nil,
            presetAppBundleID: "com.apple.TextEdit"
        )

        XCTAssertTrue(writer.created.isEmpty, "prefix detection off → no reminder")
        XCTAssertEqual(paste.pasted.count, 1, "falls back to normal dictation paste")
    }
}
