@testable import Core
import XCTest

final class VoiceDictionaryStoreTests: XCTestCase {
    func testUpsertListAndDeleteDictionaryEntry() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceDictionaryStore-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let db = try Database(
            url: tempDir.appendingPathComponent("clipboard.sqlite"),
            migrations: ClipboardStore.migrations
        )
        let store = VoiceDictionaryStore(database: db)

        let inserted = try store.upsert(phrase: "海涛", replacement: "江涛")
        let updated = try store.upsert(phrase: "海涛", replacement: "江涛 Jiang Tao")

        XCTAssertEqual(inserted.id, updated.id)
        XCTAssertEqual(updated.replacement, "江涛 Jiang Tao")
        XCTAssertEqual(try store.list(), [updated])

        try store.delete(id: updated.id)
        XCTAssertEqual(try store.list(), [])
    }
}
