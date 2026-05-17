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
        AppGroupSettings.defaults.removeObject(forKey: ClipboardDockOpenFocusSetting.key)
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
        NSApplication.shared.windows
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

    func testDockOpenFocusSettingDefaultsToNewestItem() {
        let suiteName = "dock-open-focus-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertFalse(ClipboardDockOpenFocusSetting.load(from: defaults))
    }

    func testDockOpenFocusSettingCanPreservePreviousFocus() {
        let suiteName = "dock-open-focus-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: ClipboardDockOpenFocusSetting.key)

        XCTAssertTrue(ClipboardDockOpenFocusSetting.load(from: defaults))
    }

    func testRefreshForDockOpenFocusesNewestItemWhenPreserveFocusIsOff() async {
        let mock = MockClient()
        mock.listResults = [
            ClipboardXPCMeta(id: "old", modified: Date(), kind: "clipboardItem", preview: "old")
        ]
        let model = makeModel(mock)
        await model.refresh()

        mock.listResults = [
            ClipboardXPCMeta(id: "new", modified: Date(), kind: "clipboardItem", preview: "new"),
            ClipboardXPCMeta(id: "old", modified: Date(), kind: "clipboardItem", preview: "old")
        ]
        await model.refreshForDockOpen(preserveFocus: false)

        XCTAssertEqual(model.items.map(\.id), ["new", "old"])
        XCTAssertEqual(model.focusedIndex, 0)
        XCTAssertEqual(model.items[model.focusedIndex].id, "new")
    }

    func testRefreshForDockOpenCanPreservePreviousFocusedItem() async {
        let mock = MockClient()
        mock.listResults = [
            ClipboardXPCMeta(id: "old", modified: Date(), kind: "clipboardItem", preview: "old")
        ]
        let model = makeModel(mock)
        await model.refresh()

        mock.listResults = [
            ClipboardXPCMeta(id: "new", modified: Date(), kind: "clipboardItem", preview: "new"),
            ClipboardXPCMeta(id: "old", modified: Date(), kind: "clipboardItem", preview: "old")
        ]
        await model.refreshForDockOpen(preserveFocus: true)

        XCTAssertEqual(model.items.map(\.id), ["new", "old"])
        XCTAssertEqual(model.focusedIndex, 1)
        XCTAssertEqual(model.items[model.focusedIndex].id, "old")
    }

    func testDockWindowShowReusesVisiblePanel() {
        closeVisibleDockWindows()
        let mock = MockClient()
        let model = makeModel(mock)
        let controller = DockWindowController(
            model: model,
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

        let visibleDockWindows = NSApplication.shared.windows
            .compactMap { $0 as? BottomDockWindow }
            .filter(\.isVisible)
        XCTAssertEqual(visibleDockWindows.count, 1)
        XCTAssertTrue(controller.debugWindowForTesting === panel)
        XCTAssertTrue(visibleDockWindows.first === panel)
        XCTAssertTrue(controller.debugHasGlobalOutsideClickMonitorForTesting)
        XCTAssertTrue(controller.debugHasLocalOutsideClickMonitorForTesting)
        XCTAssertEqual(model.searchFocusRequestID, 1)
    }

    func testRequestSearchFocusIncrementsToken() {
        let mock = MockClient()
        let model = makeModel(mock)

        model.requestSearchFocus()
        model.requestSearchFocus()

        XCTAssertEqual(model.searchFocusRequestID, 2)
    }

    func testDockWindowUsesLevelAboveSystemDockAndBelowNativeDragPreview() {
        let panel = BottomDockWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 180))
        defer { panel.close() }

        XCTAssertGreaterThan(
            panel.level.rawValue,
            NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow))).rawValue
        )
        XCTAssertLessThan(
            panel.level.rawValue,
            NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.draggingWindow))).rawValue
        )
    }

    func testHeightPreviewInvokerLevelSitsAboveDockPanelAndBelowNativeDragPreview() {
        let panel = BottomDockWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 180))
        defer { panel.close() }
        let dockLevel = panel.level
        let invokerLevel = DockHeightPreviewLayering.invokerLevel(above: dockLevel)

        XCTAssertGreaterThan(invokerLevel.rawValue, dockLevel.rawValue)
        XCTAssertLessThan(
            invokerLevel.rawValue,
            NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.draggingWindow))).rawValue
        )
    }

    func testDockOutsideClickPolicyHidesOnlyOutsidePanelAfterIgnoreWindow() {
        let frame = NSRect(x: 0, y: 0, width: 320, height: 180)
        let now = Date(timeIntervalSince1970: 100)

        XCTAssertFalse(DockOutsideClickPolicy.shouldHide(
            panelFrame: frame,
            clickLocationOnScreen: NSPoint(x: 40, y: 40),
            ignoreOutsideClicksUntil: now.addingTimeInterval(1),
            now: now
        ))
        XCTAssertFalse(DockOutsideClickPolicy.shouldHide(
            panelFrame: frame,
            clickLocationOnScreen: NSPoint(x: 40, y: 40),
            ignoreOutsideClicksUntil: .distantPast,
            now: now
        ))
        XCTAssertTrue(DockOutsideClickPolicy.shouldHide(
            panelFrame: frame,
            clickLocationOnScreen: NSPoint(x: 400, y: 240),
            ignoreOutsideClicksUntil: .distantPast,
            now: now
        ))
    }

    func testPreviewTransitionDirectionTracksHorizontalNavigation() {
        XCTAssertEqual(PreviewPanelTransitionDirection.horizontal(from: 0, to: 1), .forward)
        XCTAssertEqual(PreviewPanelTransitionDirection.horizontal(from: 3, to: 2), .backward)
        XCTAssertEqual(PreviewPanelTransitionDirection.horizontal(from: 2, to: 2), .none)
    }

    func testPreviewLayoutAvoidsBottomDockFrame() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let dockFrame = NSRect(x: 0, y: 0, width: 1440, height: 360)

        let frame = PreviewPanelLayout.frame(
            desiredSize: NSSize(width: 760, height: 540),
            visibleFrame: visibleFrame,
            avoiding: dockFrame
        )

        XCTAssertGreaterThanOrEqual(frame.minY, dockFrame.maxY + PreviewPanelLayout.minimumClearance)
        XCTAssertLessThanOrEqual(frame.maxY, visibleFrame.maxY)
    }

    func testDockWindowHideDismissesFloatingPreview() {
        let mock = MockClient()
        let controller = DockWindowController(
            model: makeModel(mock),
            pasteCoordinator: DockPasteCoordinator(xpc: mock),
            favicons: FaviconCache(),
            registry: ShortcutRegistry()
        )
        PreviewPanel.debugResetDismissCountForTesting()

        controller.hide()

        XCTAssertEqual(PreviewPanel.debugDismissCountForTesting, 1)
    }

    func testDockTypingSearchAppendsPrintableText() {
        let updated = DockTypingSearch.updatedQuery(
            current: "dep",
            keyCode: 0,
            characters: "l",
            modifiers: []
        )

        XCTAssertEqual(updated, "depl")
    }

    func testDockTypingSearchAllowsShiftedPrintableText() {
        let updated = DockTypingSearch.updatedQuery(
            current: "A",
            keyCode: 0,
            characters: "B",
            modifiers: .shift
        )

        XCTAssertEqual(updated, "AB")
    }

    func testDockTypingSearchRejectsCommandShortcuts() {
        let updated = DockTypingSearch.updatedQuery(
            current: "query",
            keyCode: 0,
            characters: "a",
            modifiers: .command
        )

        XCTAssertNil(updated)
    }

    func testDockTypingSearchHandlesDelete() {
        let updated = DockTypingSearch.updatedQuery(
            current: "query",
            keyCode: 51,
            characters: "\u{7F}",
            modifiers: []
        )

        XCTAssertEqual(updated, "quer")
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

    func testCardReorderIsOnlyEnabledForPinboards() {
        let mock = MockClient()
        let model = makeModel(mock)

        model.activeList = .history
        XCTAssertFalse(model.isActiveListReorderable)

        model.activeList = .pinboard(RecordID.generate())
        XCTAssertTrue(model.isActiveListReorderable)
    }

    func testFinishDockDragClearsStateAndPublishesCompletionEvenWhenAlreadyInactive() {
        let mock = MockClient()
        let model = makeModel(mock)

        model.activeDraggedItemID = "card"
        model.isDockDragSurfaceActive = true

        model.finishDockDrag()

        XCTAssertNil(model.activeDraggedItemID)
        XCTAssertFalse(model.isDockDragSurfaceActive)
        XCTAssertEqual(model.dockDragCompletionCount, 1)

        model.finishDockDrag()

        XCTAssertEqual(model.dockDragCompletionCount, 2)
    }

    func testAppendCardInActivePinboardPersistsAtEnd() async throws {
        let mock = MockClient()
        let model = makeModel(mock)
        let board = try model.pinboards.create(name: "Pinned")
        let first = try XCTUnwrap(RecordID(rawValue: "01HY7J6Q000000000000000001"))
        let second = try XCTUnwrap(RecordID(rawValue: "01HY7J6Q000000000000000002"))
        let third = try XCTUnwrap(RecordID(rawValue: "01HY7J6Q000000000000000003"))
        try model.pinboards.mutate(id: board.id) { pinboard in
            pinboard.itemIDs = [first, second, third]
        }
        model.activeList = .pinboard(board.id)
        model.items = [
            DockItem(from: ClipboardXPCMeta(id: first.rawValue, modified: Date(), kind: "clipboardItem", preview: "first"), sourceApp: nil, isPinned: true),
            DockItem(from: ClipboardXPCMeta(id: second.rawValue, modified: Date(), kind: "clipboardItem", preview: "second"), sourceApp: nil, isPinned: true),
            DockItem(from: ClipboardXPCMeta(id: third.rawValue, modified: Date(), kind: "clipboardItem", preview: "third"), sourceApp: nil, isPinned: true)
        ]

        await model.appendCardInActivePinboard(movingID: first.rawValue)

        let updated = try XCTUnwrap(try model.pinboards.list().first { $0.id == board.id })
        XCTAssertEqual(updated.itemIDs, [second, third, first])
    }

    func testReorderCardInActivePinboardPersistsAfterTarget() async throws {
        let mock = MockClient()
        let model = makeModel(mock)
        let board = try model.pinboards.create(name: "Pinned")
        let first = try XCTUnwrap(RecordID(rawValue: "01HY7J6Q000000000000000001"))
        let second = try XCTUnwrap(RecordID(rawValue: "01HY7J6Q000000000000000002"))
        let third = try XCTUnwrap(RecordID(rawValue: "01HY7J6Q000000000000000003"))
        try model.pinboards.mutate(id: board.id) { pinboard in
            pinboard.itemIDs = [first, second, third]
        }
        model.activeList = .pinboard(board.id)
        model.items = [
            DockItem(from: ClipboardXPCMeta(id: first.rawValue, modified: Date(), kind: "clipboardItem", preview: "first"), sourceApp: nil, isPinned: true),
            DockItem(from: ClipboardXPCMeta(id: second.rawValue, modified: Date(), kind: "clipboardItem", preview: "second"), sourceApp: nil, isPinned: true),
            DockItem(from: ClipboardXPCMeta(id: third.rawValue, modified: Date(), kind: "clipboardItem", preview: "third"), sourceApp: nil, isPinned: true)
        ]

        await model.reorderCardInActivePinboard(
            movingID: first.rawValue,
            targetID: second.rawValue,
            placement: .after
        )

        let updated = try XCTUnwrap(try model.pinboards.list().first { $0.id == board.id })
        XCTAssertEqual(updated.itemIDs, [second, first, third])
    }

    func testPersistPinboardOrderSurvivesReload() async throws {
        let mock = MockClient()
        let model = makeModel(mock)
        let first = try model.pinboards.create(name: "First")
        let second = try model.pinboards.create(name: "Second")
        let third = try model.pinboards.create(name: "Third")
        await model.loadAvailableLists()
        let pinned = try XCTUnwrap(model.availableLists.first { $0.name == PinnedPinboard.displayName })

        model.reorderPinboardsLocally(orderedIDs: [third.id, first.id, second.id, pinned.id])
        await model.persistPinboardOrder()
        await model.loadAvailableLists()

        XCTAssertEqual(model.availableLists.map(\.id), [third.id, first.id, second.id, pinned.id])
    }
}
