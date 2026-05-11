@testable import MacAllYouNeed
import Core
import CryptoKit
import Platform
import XCTest

@MainActor
final class SelectionStateTests: XCTestCase {
    final class MockClient: ClipboardXPCInteracting, @unchecked Sendable {
        var pasteManyArgs: (ids: [String], delim: String, plain: Bool)?
        var deletes: [String] = []
        var transformCalls: [(String, String)] = []
        var listResults: [ClipboardXPCMeta] = []
        /// When true, `deleteItem` removes the matching meta from `listResults`
        /// before replying — modelling the real daemon, where a follow-up
        /// `listItems` reflects prior deletes.
        var shouldShrinkListOnDelete = false

        func listItems(query: String?, pageToken: String?, limit: Int) async -> ClipboardXPCList {
            ClipboardXPCList(items: listResults, nextPageToken: nil)
        }

        func metasByIDs(ids: [String]) async -> ClipboardXPCList {
            ClipboardXPCList(items: [], nextPageToken: nil)
        }

        func bodyText(forID id: String) async -> String? { nil }
        func bodyFileURLs(forID id: String) async -> [String]? { nil }
        func paste(itemID: String, plainText: Bool) async -> String { "injected" }

        func pasteMany(itemIDs: [String], delimiter: String, plainText: Bool) async -> String {
            pasteManyArgs = (itemIDs, delimiter, plainText)
            return "injected"
        }

        func pasteText(text: String, plainText: Bool, saveAsNew: Bool) async -> String { "injected" }

        func transformAndCopy(itemID: String, transform: String, saveAsNew: Bool) async -> String? {
            transformCalls.append((itemID, transform))
            return nil
        }

        func imageThumbnail(forID id: String, maxDim: Int) async -> Data? { nil }
        func listSnippets() async -> [SnippetXPCDTO] { [] }

        func deleteItem(id: String) async -> Bool {
            deletes.append(id)
            if shouldShrinkListOnDelete {
                listResults.removeAll { $0.id == id }
            }
            return true
        }
    }

    private var dir: URL!
    private var pinboards: PinboardStore!
    private var snippets: SnippetStore!
    private var mock: MockClient!
    private var model: ClipboardDockModel!

    override func setUp() async throws {
        AppGroupSettings.defaults.set(false, forKey: "search.fuzzy")
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Sel-\(UUID().uuidString)", isDirectory: true)
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
        mock.listResults = (0..<5).map {
            ClipboardXPCMeta(id: "i\($0)", modified: Date(), kind: "clipboardItem", preview: "v\($0)")
        }

        model = ClipboardDockModel(
            xpc: mock,
            appIcons: AppIconResolver(),
            imageLoader: ImageBlobLoader(xpc: mock),
            fileLoader: FileURLLoader(xpc: mock),
            fileThumbnailLoader: FileThumbnailLoader(),
            pinboards: pinboards,
            snippets: snippets
        )
        await model.refresh()
    }

    override func tearDown() async throws {
        AppGroupSettings.defaults.removeObject(forKey: "search.fuzzy")
        try? FileManager.default.removeItem(at: dir)
    }

    func testToggleSelectionAdds() {
        model.toggleSelection(itemID: "i0")
        XCTAssertEqual(model.selection, Set(["i0"]))
    }

    func testToggleSelectionRemovesIfPresent() {
        model.toggleSelection(itemID: "i0")
        model.toggleSelection(itemID: "i0")
        XCTAssertTrue(model.selection.isEmpty)
    }

    func testExtendSelectionRightAddsContiguousFromFocus() {
        model.focusedIndex = 1
        model.extendSelectionRight()
        XCTAssertEqual(model.selection, Set(["i1", "i2"]))
    }

    func testExtendSelectionLeftAddsContiguousFromFocus() {
        model.focusedIndex = 3
        model.extendSelectionLeft()
        XCTAssertEqual(model.selection, Set(["i2", "i3"]))
    }

    func testClearSelection() {
        model.toggleSelection(itemID: "i0")
        model.toggleSelection(itemID: "i1")
        model.clearSelection()
        XCTAssertTrue(model.selection.isEmpty)
    }

    func testSelectAllCapsAt50() async {
        mock.listResults = (0..<60).map {
            ClipboardXPCMeta(id: "i\($0)", modified: Date(), kind: "clipboardItem", preview: "v")
        }
        await model.refresh()
        model.selectAllVisible()
        XCTAssertEqual(model.selection.count, 50)
    }

    func testRefreshClearsSelection() async {
        model.toggleSelection(itemID: "i0")
        await model.refresh()
        XCTAssertTrue(model.selection.isEmpty)
    }

    func testPasteSelectionInOrderRoutesPasteMany() async {
        model.toggleSelection(itemID: "i2")
        model.toggleSelection(itemID: "i0")
        model.toggleSelection(itemID: "i1")

        await model.pasteSelectionInOrder(delimiter: "\n", plainText: true)

        XCTAssertEqual(mock.pasteManyArgs?.delim, "\n")
        XCTAssertEqual(mock.pasteManyArgs?.plain, true)
        XCTAssertEqual(mock.pasteManyArgs?.ids, ["i0", "i1", "i2"])
    }

    func testDeleteSelectedDeletesEachItem() async {
        model.toggleSelection(itemID: "i0")
        model.toggleSelection(itemID: "i1")

        await model.deleteSelected()

        XCTAssertEqual(Set(mock.deletes), Set(["i0", "i1"]))
        XCTAssertTrue(model.selection.isEmpty)
    }

    /// Regression test for the delete/refresh race called out in Phase D
    /// review item #15. deleteSelected is N awaits long; if itemsInvalidated
    /// fires (or anything else triggers refresh) mid-flight, the snapshot of
    /// selection IDs taken at the start of deleteSelected must still be
    /// honored, no item should escape deletion, and final selection must be
    /// empty. The mock's listResults shrinks per-delete to mimic the real
    /// daemon's view after each XPC call.
    func testDeleteSelectedSurvivesConcurrentRefresh() async {
        model.toggleSelection(itemID: "i0")
        model.toggleSelection(itemID: "i2")
        model.toggleSelection(itemID: "i4")
        let targetIDs = Set(model.selection)

        mock.shouldShrinkListOnDelete = true

        async let deletes: Void = model.deleteSelected()
        async let interleavedRefresh: Void = model.refresh()
        async let secondRefresh: Void = model.refresh()
        _ = await (deletes, interleavedRefresh, secondRefresh)

        XCTAssertEqual(Set(mock.deletes), targetIDs,
                       "Every item snapshotted before the concurrent refresh must still get deleted")
        XCTAssertTrue(model.selection.isEmpty,
                      "Selection must be cleared regardless of refresh interleaving")
        XCTAssertFalse(model.items.contains { targetIDs.contains($0.id) },
                       "Final items list must reflect the deletes the daemon already accepted")
    }

    func testApplyTransformRoutesEachSelectedItem() async {
        model.toggleSelection(itemID: "i0")
        model.toggleSelection(itemID: "i2")

        await model.applyTransform(.uppercase, saveAsNew: true)

        XCTAssertEqual(Set(mock.transformCalls.map(\.0)), Set(["i0", "i2"]))
        XCTAssertTrue(mock.transformCalls.allSatisfy { $0.1 == TextTransform.uppercase.rawValue })
    }

    func testApplyTransformOnlyToFocusedWhenNoSelection() async {
        model.focusedIndex = 1

        await model.applyTransform(.lowercase, saveAsNew: false)

        XCTAssertEqual(mock.transformCalls.first?.0, "i1")
        XCTAssertEqual(mock.transformCalls.first?.1, TextTransform.lowercase.rawValue)
    }
}
