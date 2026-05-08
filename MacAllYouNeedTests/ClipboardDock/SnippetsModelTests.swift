@testable import MacAllYouNeed
import Core
import CryptoKit
import XCTest

@MainActor
final class SnippetsModelTests: XCTestCase {
    final class MockClient: ClipboardXPCInteracting, @unchecked Sendable {
        var pasteTextArgs: (text: String, plain: Bool, save: Bool)?

        func listItems(query: String?, pageToken: String?, limit: Int) async -> ClipboardXPCList {
            ClipboardXPCList(items: [], nextPageToken: nil)
        }

        func metasByIDs(ids: [String]) async -> ClipboardXPCList {
            ClipboardXPCList(items: [], nextPageToken: nil)
        }

        func bodyText(forID id: String) async -> String? { nil }
        func bodyFileURLs(forID id: String) async -> [String]? { nil }
        func paste(itemID: String, plainText: Bool) async -> String { "injected" }
        func pasteMany(itemIDs: [String], delimiter: String, plainText: Bool) async -> String { "injected" }
        func pasteText(text: String, plainText: Bool, saveAsNew: Bool) async -> String {
            pasteTextArgs = (text: text, plain: plainText, save: saveAsNew)
            return "injected"
        }

        func transformAndCopy(itemID: String, transform: String, saveAsNew: Bool) async -> String? { nil }
        func imageThumbnail(forID id: String, maxDim: Int) async -> Data? { nil }
        func listSnippets() async -> [SnippetXPCDTO] { [] }
        func deleteItem(id: String) async -> Bool { true }
    }

    private var dir: URL!
    private var snippets: SnippetStore!
    private var pinboards: PinboardStore!
    private var mock: MockClient!
    private var model: ClipboardDockModel!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Snip-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let key = SymmetricKey(size: .bits256)
        let snippetDB = try Database(
            url: dir.appendingPathComponent("s.sqlite"),
            migrations: SnippetStore.migrations
        )
        snippets = SnippetStore(database: snippetDB, deviceKey: key)
        let pinboardDB = try Database(
            url: dir.appendingPathComponent("p.sqlite"),
            migrations: PinboardStore.migrations
        )
        pinboards = PinboardStore(database: pinboardDB, deviceKey: key)
        mock = MockClient()
        model = ClipboardDockModel(
            xpc: mock,
            appIcons: AppIconResolver(),
            imageLoader: ImageBlobLoader(xpc: mock),
            fileLoader: FileURLLoader(xpc: mock),
            pinboards: pinboards,
            snippets: snippets
        )
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testLoadSnippetsReturnsExisting() async throws {
        _ = try snippets.create(name: "sig", body: "Best,\nMingjie")
        await model.loadSnippets()
        XCTAssertEqual(model.snippetItems.first?.name, "sig")
    }

    func testCreateSnippetPersistsAndReloads() async {
        await model.createSnippet(name: "code", body: "if true {}", trigger: ";code")
        XCTAssertEqual(model.snippetItems.first?.trigger, ";code")
    }

    func testDeleteSnippetRemovesIt() async throws {
        let snippet = try snippets.create(name: "tmp", body: "x")
        await model.loadSnippets()
        await model.deleteSnippet(id: snippet.id)
        XCTAssertTrue(model.snippetItems.isEmpty)
    }

    func testDuplicateSnippetCreatesCopyWithNewID() async throws {
        let snippet = try snippets.create(name: "orig", body: "b")
        await model.loadSnippets()
        await model.duplicateSnippet(id: snippet.id)
        XCTAssertEqual(model.snippetItems.count, 2)
        XCTAssertEqual(Set(model.snippetItems.map(\.name)), ["orig", "orig (copy)"])
    }

    func testPasteSnippetRoutesPasteText() async throws {
        let snippet = try snippets.create(name: "sig", body: "Best,\nM")
        await model.loadSnippets()
        await model.pasteSnippet(id: snippet.id, plainText: true)
        XCTAssertEqual(mock.pasteTextArgs?.text, "Best,\nM")
        XCTAssertTrue(mock.pasteTextArgs?.plain == true)
        XCTAssertTrue(mock.pasteTextArgs?.save == true)
    }
}
