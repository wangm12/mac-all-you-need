@testable import MacAllYouNeed
import Core
import CryptoKit
import XCTest

@MainActor
final class ClipboardDockModelListSwitchingTests: XCTestCase {
    final class MockClient: ClipboardXPCInteracting, @unchecked Sendable {
        var lastQuery: String?
        var resultsByQuery: [String: [ClipboardXPCMeta]] = [:]
        var nilQueryResults: [ClipboardXPCMeta] = []
        var metasByIDsResults: [ClipboardXPCMeta] = []

        func listItems(query: String?, pageToken: String?, limit: Int) async -> ClipboardXPCList {
            lastQuery = query
            if let query {
                return ClipboardXPCList(items: resultsByQuery[query] ?? [], nextPageToken: nil)
            }
            return ClipboardXPCList(items: nilQueryResults, nextPageToken: nil)
        }

        func metasByIDs(ids: [String]) async -> ClipboardXPCList {
            ClipboardXPCList(items: metasByIDsResults, nextPageToken: nil)
        }

        func bodyText(forID id: String) async -> String? { nil }
        func bodyFileURLs(forID id: String) async -> [String]? { nil }
        func paste(itemID: String, plainText: Bool) async -> String { "injected" }
        func pasteMany(itemIDs: [String], delimiter: String, plainText: Bool) async -> String { "injected" }
        func pasteText(text: String, plainText: Bool, saveAsNew: Bool) async -> String { "injected" }
        func transformAndCopy(itemID: String, transform: String, saveAsNew: Bool) async -> String? { nil }
        func imageThumbnail(forID id: String, maxDim: Int) async -> Data? { nil }
        func listSnippets() async -> [SnippetXPCDTO] { [] }
    }

    private var dir: URL!
    private var pinboards: PinboardStore!
    private var mock: MockClient!
    private var model: ClipboardDockModel!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PMod-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let key = SymmetricKey(size: .bits256)
        let db = try Database(url: dir.appendingPathComponent("p.sqlite"), migrations: PinboardStore.migrations)
        pinboards = PinboardStore(database: db, deviceKey: key)
        mock = MockClient()
        model = ClipboardDockModel(
            xpc: mock,
            appIcons: AppIconResolver(),
            imageLoader: ImageBlobLoader(xpc: mock),
            fileLoader: FileURLLoader(xpc: mock),
            pinboards: pinboards
        )
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testActiveListDefaultsToHistory() {
        XCTAssertEqual(model.activeList, .history)
    }

    func testSwitchingListClearsSearchAndResetsFocus() async {
        mock.nilQueryResults = [
            ClipboardXPCMeta(id: RecordID.generate().rawValue, modified: Date(), kind: "clipboardItem", preview: "x")
        ]

        await model.refresh()
        model.search = "needle"
        model.focusedIndex = 5

        await model.switchList(.pinned)

        XCTAssertEqual(model.activeList, .pinned)
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

        let pinned = try XCTUnwrap(try pinboards.list().first(where: { $0.name == PinnedPinboard.reservedName }))
        XCTAssertFalse(pinned.itemIDs.contains(id))
    }

    func testAvailableListsExcludesReservedPinned() async throws {
        _ = try PinnedPinboard.findOrCreate(in: pinboards)
        _ = try pinboards.create(name: "Useful")

        await model.loadAvailableLists()

        XCTAssertEqual(model.availableLists.map(\.name), ["Useful"])
    }
}
