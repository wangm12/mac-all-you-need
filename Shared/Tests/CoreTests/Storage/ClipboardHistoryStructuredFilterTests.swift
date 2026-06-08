import Core
import CryptoKit
import XCTest

final class ClipboardHistoryStructuredFilterTests: XCTestCase {
    private var dir: URL!
    private var clip: ClipboardStore!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let key = SymmetricKey(size: .bits256)
        let clipDB = try Database(url: dir.appendingPathComponent("clip.sqlite"), migrations: ClipboardStore.migrations)
        clip = try ClipboardStore(
            database: clipDB,
            deviceKey: key,
            deviceID: DeviceID(rawValue: "00000000-0000-0000-0000-000000000002")!
        )
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    func testStructuredAppFilterViaLoader() throws {
        let safari = try clip.append(.text("safari note"), sourceAppBundleID: "com.apple.Safari")
        let notes = try clip.append(.text("notes note"), sourceAppBundleID: "com.apple.Notes")

        let filter = ClipboardHistoryStructuredFilter(appIncludes: ["safari"])
        let hits = try ClipboardHistoryQueryLoader.loadRecentStructured(
            clip: clip,
            limit: 10,
            modifiedOnOrAfter: nil,
            structured: filter
        )

        XCTAssertEqual(hits.map(\.id), [safari.id])
    }

    func testStructuredAppFilterUsesSQLInList() throws {
        let safari = try clip.append(.text("safari note"), sourceAppBundleID: "com.apple.Safari")
        _ = try clip.append(.text("notes note"), sourceAppBundleID: "com.apple.Notes")
        let filter = ClipboardHistoryStructuredFilter(appIncludes: ["safari"])
        let hits = try clip.list(limit: 10, structured: filter)
        XCTAssertEqual(hits.map(\.id), [safari.id])
    }
}
