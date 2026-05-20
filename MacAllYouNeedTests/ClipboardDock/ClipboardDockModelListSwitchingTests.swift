import Core
import CryptoKit
@testable import MacAllYouNeed
import XCTest

@MainActor
final class ClipboardDockModelListSwitchingTests: XCTestCase {
    final class MockClient: ClipboardXPCInteracting, @unchecked Sendable {
        var lastQuery: String?
        var resultsByQuery: [String: [ClipboardXPCMeta]] = [:]
        var nilQueryResults: [ClipboardXPCMeta] = []
        var metasByIDsResults: [ClipboardXPCMeta] = []

        func listItems(query: String?, pageToken _: String?, limit _: Int) async -> ClipboardXPCList {
            lastQuery = query
            if let query {
                return ClipboardXPCList(items: resultsByQuery[query] ?? [], nextPageToken: nil)
            }
            return ClipboardXPCList(items: nilQueryResults, nextPageToken: nil)
        }

        func metasByIDs(ids _: [String]) async -> ClipboardXPCList {
            ClipboardXPCList(items: metasByIDsResults, nextPageToken: nil)
        }

        func bodyText(forID _: String) async -> String? {
            nil
        }

        func bodyFileURLs(forID _: String) async -> [String]? {
            nil
        }

        func paste(itemID _: String, plainText _: Bool) async -> String {
            "injected"
        }

        func pasteMany(itemIDs _: [String], delimiter _: String, plainText _: Bool) async -> String {
            "injected"
        }

        func pasteText(text _: String, plainText _: Bool, saveAsNew _: Bool) async -> String {
            "injected"
        }

        func transformAndCopy(itemID _: String, transform _: String, saveAsNew _: Bool) async -> String? {
            nil
        }

        func imageThumbnail(forID _: String, maxDim _: Int) async -> Data? {
            nil
        }

        func listSnippets() async -> [SnippetXPCDTO] {
            []
        }

        func deleteItem(id _: String) async -> Bool {
            false
        }
    }

    private var dir: URL!
    private var pinboards: PinboardStore!
    private var snippets: SnippetStore!
    private var mock: MockClient!
    private var model: ClipboardDockModel!

    override func setUp() async throws {
        AppGroupSettings.defaults.set(false, forKey: "search.fuzzy")
        AppGroupSettings.defaults.removeObject(forKey: PinnedPinboard.deletedDefaultKey)
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PMod-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let key = SymmetricKey(size: .bits256)
        let pinboardDB = try Database(
            url: dir.appendingPathComponent("p.sqlite"),
            migrations: PinboardStore.migrations
        )
        let snippetDB = try Database(
            url: dir.appendingPathComponent("s.sqlite"),
            migrations: SnippetStore.migrations
        )
        pinboards = PinboardStore(database: pinboardDB, deviceKey: key)
        snippets = SnippetStore(database: snippetDB, deviceKey: key)
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
        AppGroupSettings.defaults.removeObject(forKey: "search.fuzzy")
        AppGroupSettings.defaults.removeObject(forKey: PinnedPinboard.deletedDefaultKey)
        try? FileManager.default.removeItem(at: dir)
    }

    func testActiveListDefaultsToHistory() {
        XCTAssertEqual(model.activeList, .history)
    }

    func testSwitchingListClearsSearchAndResetsFocus() async throws {
        let pinned = try PinnedPinboard.findOrCreate(in: pinboards)
        mock.nilQueryResults = [
            ClipboardXPCMeta(id: RecordID.generate().rawValue, modified: Date(), kind: "clipboardItem", preview: "x")
        ]

        await model.refresh()
        model.search = "needle"
        model.focusedIndex = 5

        await model.switchList(.pinboard(pinned.id))

        XCTAssertEqual(model.activeList, .pinboard(pinned.id))
        XCTAssertEqual(model.search, "")
        XCTAssertEqual(model.focusedIndex, 0)
    }

    func testHistorySearchPassesQueryToXPC() async {
        model.search = "found"
        await model.refresh()
        XCTAssertEqual(mock.lastQuery, "found")
    }

    func testTogglePinAddsToReservedPinboard() async throws {
        let pinned = try PinnedPinboard.findOrCreate(in: pinboards)
        let id = RecordID.generate()

        await model.togglePin(itemID: id.rawValue)

        let updated = try XCTUnwrap(try pinboards.list().first(where: { $0.id == pinned.id }))
        XCTAssertTrue(updated.itemIDs.contains(id))
    }

    func testTogglePinRemovesIfAlreadyPinned() async throws {
        let id = RecordID.generate()

        await model.togglePin(itemID: id.rawValue)
        await model.togglePin(itemID: id.rawValue)

        let pinned = try XCTUnwrap(try pinboards.list().first(where: { $0.name == PinnedPinboard.displayName }))
        XCTAssertFalse(pinned.itemIDs.contains(id))
    }

    func testAvailableListsIncludesPinnedPinboard() async throws {
        _ = try PinnedPinboard.findOrCreate(in: pinboards)
        _ = try pinboards.create(name: "Useful")

        await model.loadAvailableLists()

        XCTAssertEqual(model.availableLists.map(\.name), [PinnedPinboard.displayName, "Useful"])
    }

    func testDeletingPinnedPinboardDoesNotRecreateItOnReload() async throws {
        let pinned = try PinnedPinboard.findOrCreate(in: pinboards)
        await model.loadAvailableLists()
        XCTAssertTrue(model.availableLists.contains { $0.id == pinned.id })

        model.activeList = .pinboard(pinned.id)
        await model.deletePinboard(id: pinned.id)
        await model.loadAvailableLists()

        XCTAssertEqual(model.activeList, .history)
        XCTAssertFalse(try pinboards.list().contains { $0.name == PinnedPinboard.displayName })
        XCTAssertFalse(model.availableLists.contains { $0.name == PinnedPinboard.displayName })
    }

    func testSnippetsListLoadsWhenActiveListIsSnippets() async throws {
        _ = try snippets.create(name: "sig", body: "Best,\nMingjie")
        await model.switchList(.snippets)
        XCTAssertEqual(model.snippetItems.map(\.name), ["sig"])
    }
}
