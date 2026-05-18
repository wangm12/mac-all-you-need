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
            fileThumbnailLoader: FileThumbnailLoader(),
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

    func testCreateSnippetPersistsAndReloads() async throws {
        try await model.createSnippet(name: "code", body: "if true {}", trigger: ";code")
        XCTAssertEqual(model.snippetItems.first?.trigger, ";code")
    }

    func testCreateSnippetWithDuplicateTriggerThrows() async throws {
        try await model.createSnippet(name: "first", body: "one", trigger: ";dup")
        do {
            try await model.createSnippet(name: "second", body: "two", trigger: ";dup")
            XCTFail("Creating a second snippet with an existing trigger must throw")
        } catch {
            // Expected: SnippetStore propagates the SQLite UNIQUE(trigger) error.
        }
        XCTAssertEqual(model.snippetItems.count, 1, "Failed insert must not appear in the list")
    }

    func testUpdateSnippetToExistingTriggerThrows() async throws {
        try await model.createSnippet(name: "alpha", body: "a", trigger: ";a")
        try await model.createSnippet(name: "beta", body: "b", trigger: ";b")
        let beta = model.snippetItems.first { $0.name == "beta" }!

        do {
            try await model.updateSnippet(id: beta.id, name: "beta", body: "b", trigger: ";a")
            XCTFail("Updating to a trigger another snippet already owns must throw")
        } catch {
            // Expected.
        }
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

    func testBeginSnippetDraftFromClipboardTextPrefillsDraftWithoutSaving() async throws {
        let key = SymmetricKey(size: .bits256)
        let clipboardDB = try Database(
            url: dir.appendingPathComponent("clipboard.sqlite"),
            migrations: ClipboardStore.migrations
        )
        let clip = try ClipboardStore(
            database: clipboardDB,
            deviceKey: key,
            deviceID: DeviceID(rawValue: "00000000-0000-0000-0000-000000000000")!
        )
        let localModel = ClipboardDockModel(
            xpc: mock,
            appIcons: AppIconResolver(),
            imageLoader: ImageBlobLoader(xpc: mock, clip: clip),
            fileLoader: FileURLLoader(xpc: mock, clip: clip),
            fileThumbnailLoader: FileThumbnailLoader(),
            pinboards: pinboards,
            snippets: snippets,
            clip: clip
        )
        let meta = try clip.append(.text("Best,\nMingjie"))

        let didBegin = await localModel.beginSnippetDraftFromClipboard(itemIDs: [meta.id.rawValue])

        XCTAssertTrue(didBegin)
        XCTAssertEqual(localModel.pendingSnippetDraft?.name, "Clipboard snippet")
        XCTAssertEqual(localModel.pendingSnippetDraft?.body, "Best,\nMingjie")
        XCTAssertNil(localModel.pendingSnippetDraft?.trigger)
        XCTAssertTrue((try? snippets.list())?.isEmpty == true)
    }
}
