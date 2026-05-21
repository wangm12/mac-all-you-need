import Core
import CryptoKit
@testable import MacAllYouNeed
import XCTest

/// Spine test for the Phase 6 ClipboardDockModel decomposition.
///
/// Runs a scripted sequence (pin -> search -> filter -> transform -> drag cancel
/// -> undo) and serialises every publicly readable state slot the dock UI
/// observes. The expected snapshot was captured against the pre-extraction
/// monolithic ClipboardDockModel; after the facade + 5 sub-models split, the
/// snapshot must remain identical so observation behavior is preserved.
@MainActor
final class ClipboardDockModelSpineSnapshotTests: XCTestCase {
    final class MockClient: ClipboardXPCInteracting, @unchecked Sendable {
        var listResults: [ClipboardXPCMeta] = []
        var listResultsByQuery: [String: [ClipboardXPCMeta]] = [:]

        func listItems(query: String?, pageToken _: String?, limit _: Int) async -> ClipboardXPCList {
            let key = query ?? "__nil__"
            let items = listResultsByQuery[key] ?? listResults
            return ClipboardXPCList(items: items, nextPageToken: nil)
        }

        func metasByIDs(ids _: [String]) async -> ClipboardXPCList {
            ClipboardXPCList(items: [], nextPageToken: nil)
        }

        func bodyText(forID _: String) async -> String? { nil }
        func bodyFileURLs(forID _: String) async -> [String]? { nil }
        func paste(itemID _: String, plainText _: Bool) async -> String { "injected" }
        func pasteMany(itemIDs _: [String], delimiter _: String, plainText _: Bool) async -> String { "injected" }
        func pasteText(text _: String, plainText _: Bool, saveAsNew _: Bool) async -> String { "injected" }
        func transformAndCopy(itemID _: String, transform _: String, saveAsNew _: Bool) async -> String? { nil }
        func imageThumbnail(forID _: String, maxDim _: Int) async -> Data? { nil }
        func listSnippets() async -> [SnippetXPCDTO] { [] }
        func deleteItem(id _: String) async -> Bool { false }
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
            .appendingPathComponent("Spine-\(UUID().uuidString)", isDirectory: true)
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

    // swiftlint:disable function_body_length
    func testScriptedSequencePreservesPublishedState_pin_search_filter_transform_dragCancel_undo() async throws {
        // Deterministic record IDs so the snapshot is stable.
        let firstID = try XCTUnwrap(RecordID(rawValue: "01HY7J6Q000000000000000001"))
        let secondID = try XCTUnwrap(RecordID(rawValue: "01HY7J6Q000000000000000002"))
        let thirdID = try XCTUnwrap(RecordID(rawValue: "01HY7J6Q000000000000000003"))
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

        let items: [ClipboardXPCMeta] = [
            ClipboardXPCMeta(id: firstID.rawValue, modified: fixedDate, kind: "clipboardItem", preview: "alpha"),
            ClipboardXPCMeta(id: secondID.rawValue, modified: fixedDate, kind: "clipboardItem", preview: "beta needle"),
            ClipboardXPCMeta(id: thirdID.rawValue, modified: fixedDate, kind: "clipboardItem", preview: "gamma")
        ]
        mock.listResults = items
        mock.listResultsByQuery["__nil__"] = items
        mock.listResultsByQuery["needle"] = [items[1]]

        // 1. Initial refresh — load history.
        await model.refresh()

        // 2. Toggle pin on second item.
        await model.togglePin(itemID: secondID.rawValue)

        // 3. Set search query and refresh.
        model.search = "needle"
        await model.refresh()

        // 4. Apply a filter (focus + select first visible).
        if let firstVisible = model.items.first {
            model.selectOnly(itemID: firstVisible.id)
        }

        // 5. Begin a transform menu.
        model.showTransformMenu = true
        model.pendingTransform = .uppercase

        // 6. Begin a drag.
        model.activeDraggedItemID = items[0].id
        model.isDockDragSurfaceActive = true

        // 7. Cancel the drag.
        model.finishDockDrag()

        // 8. Undo / clear transform menu.
        model.pendingTransform = nil
        model.showTransformMenu = false

        // 9. Clear search to restore full list and refresh.
        model.search = ""
        await model.refresh()

        // Begin a snippet draft as a final cross-feature interaction.
        model.pendingSnippetDraft = SnippetDraft(name: "Draft", body: "text")

        let snapshot = Self.serializePublishedState(model)

        let expected: [String: String] = [
            "activeDraggedItemID": "nil",
            "activeList": "history",
            "availableListNames": "",
            "dockDragCompletionCount": "1",
            "focusedIndex": "1",
            "isDockDragSurfaceActive": "false",
            "isQuickLooking": "false",
            "itemCount": "3",
            "itemIDsJoined": "01HY7J6Q000000000000000001|01HY7J6Q000000000000000002|01HY7J6Q000000000000000003",
            "pendingSnippetDraftBody": "text",
            "pendingSnippetDraftName": "Draft",
            "pendingTransform": "nil",
            "previousFrontmostBundleID": "nil",
            "search": "",
            "searchFocusRequestID": "0",
            "selectionAnchorIndex": "0",
            "selectionCount": "0",
            "showCheatsheet": "false",
            "showTransformMenu": "false",
            "snippetItemCount": "0"
        ]

        XCTAssertEqual(snapshot, expected, "Spine snapshot drift — observation surface changed.")
    }
    // swiftlint:enable function_body_length

    /// Walks every publicly readable property the dock UI depends on. Returns a
    /// stable, ordered dictionary so the test diff is human-readable when a
    /// drift is detected.
    private static func serializePublishedState(_ model: ClipboardDockModel) -> [String: String] {
        let activeListLabel: String = {
            switch model.activeList {
            case .history: return "history"
            case .snippets: return "snippets"
            case let .pinboard(id): return "pinboard(\(id.rawValue))"
            }
        }()
        return [
            "activeList": activeListLabel,
            "search": model.search,
            "searchFocusRequestID": String(model.searchFocusRequestID),
            "focusedIndex": String(model.focusedIndex),
            "selectionCount": String(model.selection.count),
            "selectionAnchorIndex": model.selectionAnchorIndex.map(String.init) ?? "nil",
            "isQuickLooking": String(model.isQuickLooking),
            "pendingTransform": model.pendingTransform?.rawValue ?? "nil",
            "showTransformMenu": String(model.showTransformMenu),
            "showCheatsheet": String(model.showCheatsheet),
            "activeDraggedItemID": model.activeDraggedItemID ?? "nil",
            "isDockDragSurfaceActive": String(model.isDockDragSurfaceActive),
            "dockDragCompletionCount": String(model.dockDragCompletionCount),
            "previousFrontmostBundleID": model.previousFrontmostBundleID ?? "nil",
            "itemCount": String(model.items.count),
            "itemIDsJoined": model.items.map(\.id).joined(separator: "|"),
            "snippetItemCount": String(model.snippetItems.count),
            "pendingSnippetDraftName": model.pendingSnippetDraft?.name ?? "nil",
            "pendingSnippetDraftBody": model.pendingSnippetDraft?.body ?? "nil",
            "availableListNames": model.availableLists.map(\.name).joined(separator: "|")
        ]
    }
}
