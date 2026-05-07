@testable import Platform
import Core
import CryptoKit
import XCTest

final class ClipboardXPCServiceTests: XCTestCase {
    var dir: URL!
    var clip: ClipboardStore!
    var blobs: BlobStore!
    var search: SearchStore!
    var snippets: SnippetStore!
    var pasteboard: NSPasteboard!
    var service: ClipboardXPCService!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("XPCSvc-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let key = SymmetricKey(size: .bits256)
        let device = DeviceID.generate()
        let clipDB = try! Database(
            url: dir.appendingPathComponent("c.sqlite"),
            migrations: ClipboardStore.migrations
        )
        clip = try! ClipboardStore(database: clipDB, deviceKey: key, deviceID: device)
        blobs = BlobStore(rootURL: dir.appendingPathComponent("blobs"), key: key)
        let searchDB = try! Database(
            url: dir.appendingPathComponent("s.sqlite"),
            migrations: SearchStore.migrations
        )
        search = SearchStore(database: searchDB)
        let snippetDB = try! Database(
            url: dir.appendingPathComponent("snip.sqlite"),
            migrations: SnippetStore.migrations
        )
        snippets = SnippetStore(database: snippetDB, deviceKey: key)
        pasteboard = NSPasteboard(name: NSPasteboard.Name("test-\(UUID().uuidString)"))
        service = ClipboardXPCService(
            clip: clip, blobs: blobs, search: search, snippets: snippets, pasteboard: pasteboard
        )
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    func testListItemsReturnsEmptyWhenStoreEmpty() {
        let exp = expectation(description: "list")
        service.listItems(query: nil, pageToken: nil, limit: 10) { list in
            XCTAssertEqual(list.items.count, 0)
            XCTAssertNil(list.nextPageToken)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
    }

    func testListItemsReturnsAppendedRecord() throws {
        _ = try clip.append(.text("hello"))
        let exp = expectation(description: "list")
        service.listItems(query: nil, pageToken: nil, limit: 10) { list in
            XCTAssertEqual(list.items.count, 1)
            XCTAssertEqual(list.items.first?.preview, "hello")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
    }
}
