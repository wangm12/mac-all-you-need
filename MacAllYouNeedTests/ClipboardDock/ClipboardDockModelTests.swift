@testable import MacAllYouNeed
import Core
import CryptoKit
import XCTest

@MainActor
final class ClipboardDockModelTests: XCTestCase {
    override func setUp() {
        super.setUp()
        AppGroupSettings.defaults.set(false, forKey: "search.fuzzy")
    }

    override func tearDown() {
        AppGroupSettings.defaults.removeObject(forKey: "search.fuzzy")
        super.tearDown()
    }

    final class MockClient: ClipboardXPCInteracting, @unchecked Sendable {
        var listCalls = 0
        var listResults: [ClipboardXPCMeta] = []
        var listResultsByQuery: [String: [ClipboardXPCMeta]] = [:]
        var listDelayMsByQuery: [String: Int] = [:]

        func listItems(query: String?, pageToken: String?, limit: Int) async -> ClipboardXPCList {
            listCalls += 1
            let key = query ?? "__nil__"
            if let delayMs = listDelayMsByQuery[key] {
                try? await Task.sleep(for: .milliseconds(delayMs))
            }
            let items = listResultsByQuery[key] ?? listResults
            return ClipboardXPCList(items: items, nextPageToken: nil)
        }

        func metasByIDs(ids: [String]) async -> ClipboardXPCList {
            ClipboardXPCList(items: [], nextPageToken: nil)
        }

        func bodyText(forID id: String) async -> String? { nil }
        func bodyFileURLs(forID id: String) async -> [String]? { nil }
        func paste(itemID: String, plainText: Bool) async -> String { "injected" }
        func pasteMany(itemIDs: [String], delimiter: String, plainText: Bool) async -> String { "injected" }
        func pasteText(text: String, plainText: Bool, saveAsNew: Bool) async -> String { "injected" }
        func transformAndCopy(itemID: String, transform: String, saveAsNew: Bool) async -> String? { nil }
        func imageThumbnail(forID id: String, maxDim: Int) async -> Data? { nil }
        func listSnippets() async -> [SnippetXPCDTO] { [] }
        func deleteItem(id: String) async -> Bool { false }
    }

    private func makeModel(_ mock: MockClient) -> ClipboardDockModel {
        let key = SymmetricKey(size: .bits256)
        let pinboardDB = try! Database(
            url: FileManager.default.temporaryDirectory.appendingPathComponent("pb-\(UUID().uuidString).sqlite"),
            migrations: PinboardStore.migrations
        )
        let snippetDB = try! Database(
            url: FileManager.default.temporaryDirectory.appendingPathComponent("sn-\(UUID().uuidString).sqlite"),
            migrations: SnippetStore.migrations
        )
        let pinboards = PinboardStore(database: pinboardDB, deviceKey: key)
        let snippets = SnippetStore(database: snippetDB, deviceKey: key)
        return ClipboardDockModel(
            xpc: mock,
            appIcons: AppIconResolver(),
            imageLoader: ImageBlobLoader(xpc: mock),
            fileLoader: FileURLLoader(xpc: mock),
            fileThumbnailLoader: FileThumbnailLoader(),
            pinboards: pinboards,
            snippets: snippets
        )
    }

    private func closeVisibleDockWindows() {
        NSApp.windows
            .compactMap { $0 as? BottomDockWindow }
            .forEach { window in
                window.orderOut(nil)
                window.close()
            }
    }

    func testRefreshLoadsItemsFromXPC() async {
        let mock = MockClient()
        mock.listResults = [
            ClipboardXPCMeta(id: "a", modified: Date(), kind: "clipboardItem", preview: "alpha"),
            ClipboardXPCMeta(id: "b", modified: Date(), kind: "clipboardItem", preview: "beta")
        ]
        let model = makeModel(mock)
        await model.refresh()
        XCTAssertEqual(model.items.count, 2)
        XCTAssertEqual(model.items.first?.preview, "alpha")
    }

    func testDockWindowShowReusesVisiblePanel() {
        closeVisibleDockWindows()
        let mock = MockClient()
        let controller = DockWindowController(
            model: makeModel(mock),
            pasteCoordinator: DockPasteCoordinator(xpc: mock),
            favicons: FaviconCache(),
            registry: ShortcutRegistry()
        )
        let frame = NSRect(x: 0, y: 0, width: 320, height: 180)
        let panel = BottomDockWindow(contentRect: frame)
        panel.contentView = NSView(frame: NSRect(origin: .zero, size: frame.size))
        panel.orderFrontRegardless()
        controller.debugSetWindowForTesting(panel)
        defer {
            controller.debugTearDownForTesting()
            closeVisibleDockWindows()
        }

        controller.show()

        let visibleDockWindows = NSApp.windows
            .compactMap { $0 as? BottomDockWindow }
            .filter(\.isVisible)
        XCTAssertEqual(visibleDockWindows.count, 1)
        XCTAssertTrue(controller.debugWindowForTesting === panel)
        XCTAssertTrue(visibleDockWindows.first === panel)
    }

    func testFocusedIndexResetsToZeroAfterRefresh() async {
        let mock = MockClient()
        mock.listResults = [
            ClipboardXPCMeta(id: "a", modified: Date(), kind: "clipboardItem", preview: "alpha")
        ]
        let model = makeModel(mock)
        model.focusedIndex = 5
        await model.refresh()
        XCTAssertEqual(model.focusedIndex, 0)
    }

    func testFocusForwardClampsToCount() async {
        let mock = MockClient()
        mock.listResults = [
            ClipboardXPCMeta(id: "a", modified: Date(), kind: "clipboardItem", preview: "alpha"),
            ClipboardXPCMeta(id: "b", modified: Date(), kind: "clipboardItem", preview: "beta")
        ]
        let model = makeModel(mock)
        await model.refresh()
        model.focusForward()
        XCTAssertEqual(model.focusedIndex, 1)
        model.focusForward()
        XCTAssertEqual(model.focusedIndex, 1)
    }

    func testFocusBackwardClampsToZero() async {
        let mock = MockClient()
        mock.listResults = [
            ClipboardXPCMeta(id: "a", modified: Date(), kind: "clipboardItem", preview: "alpha"),
            ClipboardXPCMeta(id: "b", modified: Date(), kind: "clipboardItem", preview: "beta")
        ]
        let model = makeModel(mock)
        await model.refresh()
        model.focusedIndex = 1
        model.focusBackward()
        XCTAssertEqual(model.focusedIndex, 0)
        model.focusBackward()
        XCTAssertEqual(model.focusedIndex, 0)
    }

    func testRefreshAppliesSearchQuery() async {
        let mock = MockClient()
        let model = makeModel(mock)
        model.search = "needle"
        await model.refresh()
        XCTAssertEqual(mock.listCalls, 1)
    }

    func testFocusPreservedWhenItemStillPresent() async {
        let mock = MockClient()
        mock.listResults = [
            ClipboardXPCMeta(id: "a", modified: Date(), kind: "clipboardItem", preview: "alpha"),
            ClipboardXPCMeta(id: "b", modified: Date(), kind: "clipboardItem", preview: "beta"),
            ClipboardXPCMeta(id: "c", modified: Date(), kind: "clipboardItem", preview: "gamma")
        ]
        let model = makeModel(mock)
        await model.refresh()
        model.focusedIndex = 1
        await model.refresh()
        XCTAssertEqual(model.focusedIndex, 1)
    }

    func testFocusJumpsToZeroWhenItemRemoved() async {
        let mock = MockClient()
        mock.listResults = [
            ClipboardXPCMeta(id: "a", modified: Date(), kind: "clipboardItem", preview: "alpha"),
            ClipboardXPCMeta(id: "b", modified: Date(), kind: "clipboardItem", preview: "beta")
        ]
        let model = makeModel(mock)
        await model.refresh()
        model.focusedIndex = 1
        mock.listResults = [
            ClipboardXPCMeta(id: "a", modified: Date(), kind: "clipboardItem", preview: "alpha")
        ]
        await model.refresh()
        XCTAssertEqual(model.focusedIndex, 0)
    }

    func testFocusFollowsItemWhenReordered() async {
        let mock = MockClient()
        mock.listResults = [
            ClipboardXPCMeta(id: "a", modified: Date(), kind: "clipboardItem", preview: "alpha"),
            ClipboardXPCMeta(id: "b", modified: Date(), kind: "clipboardItem", preview: "beta")
        ]
        let model = makeModel(mock)
        await model.refresh()
        model.focusedIndex = 1
        mock.listResults = [
            ClipboardXPCMeta(id: "b", modified: Date(), kind: "clipboardItem", preview: "beta"),
            ClipboardXPCMeta(id: "a", modified: Date(), kind: "clipboardItem", preview: "alpha")
        ]
        await model.refresh()
        XCTAssertEqual(model.focusedIndex, 0)
    }

    func testRefreshIgnoresStaleOutOfOrderResponse() async {
        let mock = MockClient()
        mock.listResultsByQuery["old"] = [
            ClipboardXPCMeta(id: "old", modified: Date(), kind: "clipboardItem", preview: "old")
        ]
        mock.listResultsByQuery["new"] = [
            ClipboardXPCMeta(id: "new", modified: Date(), kind: "clipboardItem", preview: "new")
        ]
        mock.listDelayMsByQuery["old"] = 200
        mock.listDelayMsByQuery["new"] = 20
        let model = makeModel(mock)

        model.search = "old"
        let oldTask = Task { await model.refresh() }
        try? await Task.sleep(for: .milliseconds(10))
        model.search = "new"
        let newTask = Task { await model.refresh() }

        await oldTask.value
        await newTask.value

        XCTAssertEqual(model.items.map(\.id), ["new"])
        XCTAssertEqual(model.items.map(\.preview), ["new"])
    }
}
