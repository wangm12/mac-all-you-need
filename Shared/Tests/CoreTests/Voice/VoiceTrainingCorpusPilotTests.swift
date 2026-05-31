import CryptoKit
@testable import Core
import Foundation
import XCTest

/// Integration checks against the developer's App Group container (skipped in CI without data).
final class VoiceTrainingCorpusPilotTests: XCTestCase {
    private var container: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/group.com.macallyouneed.shared", isDirectory: true)
    }

    private func openStore() throws -> (VoiceTrainingExampleStore, [VoiceTrainingExample]) {
        let dbURL = container.appendingPathComponent("databases/clipboard.sqlite")
        guard FileManager.default.fileExists(atPath: dbURL.path) else {
            throw XCTSkip("No local App Group database at \(dbURL.path)")
        }

        let key = try KeyManager(keychain: SystemKeychain()).deviceKey()
        let db = try Database(url: dbURL, migrations: ClipboardStore.migrations)
        let store = VoiceTrainingExampleStore(
            database: db,
            deviceKey: key,
            audioRoot: container.appendingPathComponent("voice-training-audio", isDirectory: true)
        )
        let examples = try store.listRecent(limit: 20_000)
        return (store, examples)
    }

    func testProductionCorpusStats() throws {
        let (_, examples) = try openStore()
        let highWithAudio = examples.filter { $0.quality == .high && $0.audioPath != nil }
        let mediumWithAudio = examples.filter { $0.quality == .medium && $0.audioPath != nil }
        let anyWithAudio = examples.filter { $0.audioPath != nil }

        fputs(
            """
            voice-training corpus:
              container: \(container.path)
              training_rows: \(examples.count)
              with_audio: \(anyWithAudio.count)
              high+audio: \(highWithAudio.count)
              medium+audio: \(mediumWithAudio.count)

            """,
            stderr
        )
    }

    func testProductionCorpusExport() throws {
        guard let path = ProcessInfo.processInfo.environment["MAYN_PILOT_EXPORT_PATH"], !path.isEmpty else {
            throw XCTSkip("Set MAYN_PILOT_EXPORT_PATH to write an export archive")
        }

        let (store, examples) = try openStore()
        let anyWithAudio = examples.filter { $0.audioPath != nil }
        guard !anyWithAudio.isEmpty else {
            throw XCTSkip("No training examples with audio in App Group store")
        }

        let exportURL = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
        try FileManager.default.createDirectory(
            at: exportURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let anyQuality = ProcessInfo.processInfo.environment["MAYN_EXPORT_ANY_QUALITY"] == "1"
        let summary = try VoiceTrainingExporter(store: store).export(
            to: exportURL,
            options: VoiceTrainingExportOptions(
                quality: .high,
                anyQuality: anyQuality,
                requiresAudio: true,
                minDurationMs: 1_000,
                maxDurationMs: 30_000
            )
        )

        XCTAssertGreaterThan(summary.exportedCount, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: exportURL.path))

        fputs(
            """
            voice-training export: exported=\(summary.exportedCount) skipped=\(summary.skippedCount) \
            archive=\(exportURL.path) any_quality=\(anyQuality)\n
            """,
            stderr
        )
    }
}
