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

    func testListRecentTranscriptsReturnsNewestFirstWithLimit() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceTranscriptStore-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let db = try Database(
            url: tempDir.appendingPathComponent("clipboard.sqlite"),
            migrations: ClipboardStore.migrations
        )
        let store = VoiceTranscriptStore(database: db)

        _ = try store.save(draft(rawText: "old", startedAt: 1, endedAt: 2))
        let newest = try store.save(draft(rawText: "newest", startedAt: 5, endedAt: 6))
        let middle = try store.save(draft(rawText: "middle", startedAt: 3, endedAt: 4))

        let recent = try store.listRecent(limit: 2)

        XCTAssertEqual(recent.map(\.id), [newest.id, middle.id])
    }

    func testDeleteTranscriptsRemovesOnlyRequestedIDs() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceTranscriptStore-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let db = try Database(
            url: tempDir.appendingPathComponent("clipboard.sqlite"),
            migrations: ClipboardStore.migrations
        )
        let store = VoiceTranscriptStore(database: db)

        let first = try store.save(draft(rawText: "first", startedAt: 1, endedAt: 2))
        let second = try store.save(draft(rawText: "second", startedAt: 3, endedAt: 4))
        let third = try store.save(draft(rawText: "third", startedAt: 5, endedAt: 6))

        try store.delete(ids: [first.id, third.id])

        XCTAssertEqual(try store.listRecent(limit: 10).map(\.id), [second.id])
        XCTAssertNil(try store.fetch(id: first.id))
        XCTAssertNil(try store.fetch(id: third.id))
    }

    private func draft(rawText: String, startedAt: TimeInterval, endedAt: TimeInterval) -> VoiceTranscriptDraft {
        VoiceTranscriptDraft(
            startedAt: Date(timeIntervalSince1970: startedAt),
            endedAt: Date(timeIntervalSince1970: endedAt),
            rawText: rawText,
            cleanedText: rawText,
            appBundleID: nil,
            language: .mixed,
            modelIdentifier: "qwen3-asr-0.6b-f32",
            audioPath: nil
        )
    }
}
