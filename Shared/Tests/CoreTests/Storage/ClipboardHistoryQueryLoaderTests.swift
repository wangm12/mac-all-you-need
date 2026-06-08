import Core
import CryptoKit
import XCTest

final class ClipboardHistoryQueryLoaderTests: XCTestCase {
    private var dir: URL!
    private var clip: ClipboardStore!
    private var search: SearchStore!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let key = SymmetricKey(size: .bits256)
        let clipDB = try Database(url: dir.appendingPathComponent("clip.sqlite"), migrations: ClipboardStore.migrations)
        clip = try ClipboardStore(
            database: clipDB,
            deviceKey: key,
            deviceID: DeviceID(rawValue: "00000000-0000-0000-0000-000000000001")!
        )
        let searchDB = try Database(url: dir.appendingPathComponent("search.sqlite"), migrations: SearchStore.migrations)
        search = SearchStore(database: searchDB)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    func testFTSQueryReturnsMatchingMetaInRankOrder() throws {
        let alpha = try clip.append(.text("alpha bravo"))
        let beta = try clip.append(.text("charlie delta"))
        try search.upsert(kind: .clipboardItem, id: alpha.id, text: "alpha bravo")
        try search.upsert(kind: .clipboardItem, id: beta.id, text: "charlie delta")

        let hits = try ClipboardHistoryQueryLoader.load(
            clip: clip,
            search: search,
            query: "bravo",
            limit: 10,
            modifiedOnOrAfter: nil
        )

        XCTAssertEqual(hits.map(\.id), [alpha.id])
    }

    func testEmptyQueryListsRecency() throws {
        _ = try clip.append(.text("one"))
        _ = try clip.append(.text("two"))

        let listed = try ClipboardHistoryQueryLoader.load(
            clip: clip,
            search: search,
            query: nil,
            limit: 1,
            modifiedOnOrAfter: nil
        )

        XCTAssertEqual(listed.count, 1)
        XCTAssertEqual(listed[0].preview, "two")
    }
}
