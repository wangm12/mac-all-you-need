@testable import MacAllYouNeed
import Core
import CryptoKit
import XCTest

@MainActor
final class ClipboardDockModelTests: XCTestCase {
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
        let db = try! Database(
            url: FileManager.default.temporaryDirectory.appendingPathComponent("pb-\(UUID().uuidString).sqlite"),
            migrations: PinboardStore.migrations
        )
        let pinboards = PinboardStore(database: db, deviceKey: key)
        return ClipboardDockModel(
            xpc: mock,
            appIcons: AppIconResolver(),
            imageLoader: ImageBlobLoader(xpc: mock),
            fileLoader: FileURLLoader(xpc: mock),
            pinboards: pinboards
        )
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
