@testable import Core
import XCTest

final class VoiceTranscriptStoreTests: XCTestCase {
    func testSaveAndFetchTranscript() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceTranscriptStore-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let db = try Database(
            url: tempDir.appendingPathComponent("clipboard.sqlite"),
            migrations: ClipboardStore.migrations
        )
        let store = VoiceTranscriptStore(database: db)

        let saved = try store.save(VoiceTranscriptDraft(
            startedAt: Date(timeIntervalSince1970: 1),
            endedAt: Date(timeIntervalSince1970: 4),
            rawText: "我今天要 deploy 这个 service 到 production。",
            cleanedText: "我今天要 deploy 这个 service 到 production。",
            appBundleID: "com.apple.TextEdit",
            language: .mixed,
            modelIdentifier: "qwen3-asr-0.6b-f32",
            audioPath: nil
        ))

        let fetched = try store.fetch(id: saved.id)
        XCTAssertEqual(fetched?.rawText, saved.rawText)
        XCTAssertEqual(fetched?.cleanedText, saved.cleanedText)
        XCTAssertEqual(fetched?.language, .mixed)
        XCTAssertEqual(fetched?.durationMs, 3000)
    }
}
