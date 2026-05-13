@testable import Core
import XCTest

final class VoiceAppProfileStoreTests: XCTestCase {
    func testUpsertListFetchAndDeleteProfile() throws {
        let store = try makeStore()
        let config = VoiceAppProfileConfig(
            isEnabled: true,
            customPrompt: "Format as a concise Git commit message.",
            language: .mixed,
            asrEngineID: "qwen3-asr-0.6b",
            autoSubmitKey: .commandReturn
        )

        let inserted = try store.upsert(
            bundleID: "com.todesktop.230313mzl4w4u92",
            displayName: "Cursor",
            config: config
        )
        let updated = try store.upsert(
            bundleID: "com.todesktop.230313mzl4w4u92",
            displayName: "Cursor Editor",
            config: VoiceAppProfileConfig(
                isEnabled: false,
                customPrompt: "Use terse engineering prose.",
                language: .english,
                asrEngineID: "parakeet-tdt-v3",
                autoSubmitKey: .returnKey
            )
        )

        XCTAssertEqual(inserted.id, updated.id)
        XCTAssertEqual(try store.list(), [updated])
        XCTAssertEqual(try store.fetch(bundleID: "com.todesktop.230313mzl4w4u92"), updated)

        try store.delete(id: updated.id)
        XCTAssertNil(try store.fetch(bundleID: "com.todesktop.230313mzl4w4u92"))
        XCTAssertEqual(try store.list(), [])
    }

    func testRejectsEmptyBundleID() throws {
        let store = try makeStore()

        XCTAssertThrowsError(try store.upsert(
            bundleID: " ",
            displayName: "Empty",
            config: .default
        )) { error in
            XCTAssertEqual(error as? VoiceAppProfileStoreError, .emptyBundleID)
        }
    }

    private func makeStore() throws -> VoiceAppProfileStore {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceAppProfileStore-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: tempDir) }
        let db = try Database(
            url: tempDir.appendingPathComponent("clipboard.sqlite"),
            migrations: ClipboardStore.migrations
        )
        return VoiceAppProfileStore(database: db)
    }
}
