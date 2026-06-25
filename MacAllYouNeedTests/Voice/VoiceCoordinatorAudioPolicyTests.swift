@testable import Core
import CryptoKit
@testable import MacAllYouNeed
import XCTest

@MainActor
final class VoiceCoordinatorAudioPolicyTests: XCTestCase {
    private var tempDir: URL!
    private var transcriptStore: VoiceTranscriptStore!
    private var trainingStore: VoiceTrainingExampleStore!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceCoordAudioPolicyTests-\(UUID().uuidString)", isDirectory: true)
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

    // MARK: - persistAudio gating

    func testPersistAudio_saves_when_saveAudio_isTrue() {
        let coordinator = makeCoordinator(saveAudio: true, personalizationSaveExamples: false)
        let id = UUID().uuidString
        let path = coordinator.persistAudio(captured: fakeCaptured(), transcriptID: id)
        XCTAssertNotNil(path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path!))
        XCTAssertEqual(try? trainingStore.count(), 0)
    }

    func testPersistAudio_saves_when_forceSave_evenIfSaveAudioOff() {
        let coordinator = makeCoordinator(saveAudio: false, personalizationSaveExamples: false)
        let id = UUID().uuidString
        let path = coordinator.persistAudio(captured: fakeCaptured(), transcriptID: id, forceSave: true)
        XCTAssertNotNil(path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path!))
    }

    func testPersistAudio_returnsNil_when_saveAudioOff_andNotForced() {
        let coordinator = makeCoordinator(saveAudio: false, personalizationSaveExamples: false)
        let id = UUID().uuidString
        let path = coordinator.persistAudio(captured: fakeCaptured(), transcriptID: id)
        XCTAssertNil(path)
        XCTAssertEqual(try? trainingStore.count(), 0)
    }

    // MARK: - Helpers

    private func makeCoordinator(
        saveAudio: Bool,
        personalizationSaveExamples: Bool
    ) -> VoiceCoordinator {
        VoiceCoordinator(
            transcripts: transcriptStore,
            trainingExampleStore: trainingStore,
            personalizationSettings: {
                var s = VoicePersonalizationSettings.default
                s.saveTrainingExamplesEnabled = personalizationSaveExamples
                return s
            },
            historySettings: {
                VoiceHistorySettings(retention: .forever, saveAudio: saveAudio)
            }
        )
    }

    private func fakeCaptured() -> CapturedAudio {
        CapturedAudio(
            samples: [0.1, -0.1, 0.2],
            sampleRate: 16_000,
            startedAt: Date(timeIntervalSince1970: 1),
            endedAt: Date(timeIntervalSince1970: 2),
            peakLevel: 0.2
        )
    }
}
