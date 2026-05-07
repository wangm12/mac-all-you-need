# Clipboard Dock — Phase C: Top Bar & Pinboards — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Phase B's placeholder search-only top bar with the full Paste-style top bar: search field with animated collapse/expand, Pinboard list tabs (built-in History / Pinned / Snippets + dynamic user lists), and a `⋯` more menu. Add the `ShortcutRegistry` for user-configurable in-dock shortcuts and surface it as a Settings tab. Allow users to add multiple global open-dock triggers (extending the existing HotkeyMapStore from a single descriptor per action to an array).

**Architecture:** New `MacAllYouNeed/ClipboardDock/Views/DockTopBar/` and `MacAllYouNeed/ClipboardDock/Shortcuts/` directories. `ClipboardDockModel` extends to hold `activeList` and `availableLists`, with a reserved `__pinned__` Pinboard implementing the cross-list pinning convention. `Pinboard.color: String?` is added inside the encrypted envelope (no schema migration — `Codable` Optional decodes missing keys to nil).

**Tech Stack:** SwiftUI, AppKit, GRDB (existing), `@Observable`, Carbon `RegisterEventHotKey` (via existing `GlobalHotkey`).

**Spec:** `docs/superpowers/specs/2026-05-07-clipboard-dock-redesign-design.md` §8, §9.

**Depends on:** Phases A and B merged. Uses Phase A's `Pinboard` model (`Shared/Sources/Core/Models/Pinboard.swift`) and `PinboardStore`. Uses Phase B's `ClipboardDockModel`, `DockListSelector`, `DockRootView`, and `DockWindowController`.

**Working directory:** `/Users/mingjie.wang/Documents/personal/mac-all-you-need`

---

## File Structure

### Created

| Path | Responsibility |
|---|---|
| `MacAllYouNeed/ClipboardDock/Shortcuts/ShortcutAction.swift` | Enum of all in-dock action IDs. |
| `MacAllYouNeed/ClipboardDock/Shortcuts/ShortcutBinding.swift` | `keyEquivalent + modifierFlags` codable struct. |
| `MacAllYouNeed/ClipboardDock/Shortcuts/ShortcutRegistry.swift` | `@Observable` action → [bindings] with persistence. |
| `MacAllYouNeed/ClipboardDock/Shortcuts/ShortcutDefaults.swift` | Default binding per action. |
| `MacAllYouNeed/ClipboardDock/Shortcuts/ShortcutRecorderView.swift` | SwiftUI control for capturing a key combo (separate from existing global `HotkeyRecorder`). |
| `MacAllYouNeed/ClipboardDock/Shortcuts/ShortcutMatcher.swift` | `func matches(_ event: NSEvent, _ action: ShortcutAction) -> Bool`. |
| `MacAllYouNeed/ClipboardDock/Views/DockTopBar/DockTopBar.swift` | Composes search + tabs + more menu. |
| `MacAllYouNeed/ClipboardDock/Views/DockTopBar/DockSearchField.swift` | Animated collapse/expand search field. |
| `MacAllYouNeed/ClipboardDock/Views/DockTopBar/DockListTabs.swift` | Tabs: built-in + Pinboards + `+`. |
| `MacAllYouNeed/ClipboardDock/Views/DockTopBar/DockMoreMenu.swift` | `⋯` menu. |
| `MacAllYouNeed/ClipboardDock/Views/DockTopBar/NewListSheet.swift` | Inline name + color swatch grid for new Pinboard. |
| `MacAllYouNeed/ClipboardDock/Model/PinnedPinboard.swift` | Helpers around the reserved `__pinned__` Pinboard. |
| `MacAllYouNeed/Settings/ShortcutsSettingsView.swift` | Shortcuts settings tab (in-dock + global). |
| `MacAllYouNeedTests/ClipboardDock/ShortcutRegistryTests.swift` | Persistence, conflict, matching. |
| `MacAllYouNeedTests/ClipboardDock/ClipboardDockModelListSwitchingTests.swift` | activeList switching, search scoping, togglePin. |
| `Shared/Tests/CoreTests/Storage/PinboardColorTests.swift` | `Pinboard.color` Codable backward compat. |

### Modified

| Path | Change |
|---|---|
| `Shared/Sources/Core/Models/Pinboard.swift` | Add `var color: String?`. |
| `Shared/Sources/Core/Storage/PinboardStore.swift` | Helpers `findOrCreate(name:)`, `togglePin(itemID:)`. |
| `MacAllYouNeed/App/AppDependencies.swift` | Construct & expose `pinboardStore`; pass into `dockModel`. |
| `MacAllYouNeed/ClipboardDock/Model/ClipboardDockModel.swift` | `activeList` switching, `availableLists`, `togglePin`, `addToPinboard`, scoped refresh. |
| `MacAllYouNeed/ClipboardDock/Model/DockListSelector.swift` | Add `.pinned, .pinboard(RecordID), .snippets`. |
| `MacAllYouNeed/ClipboardDock/Views/DockRootView.swift` | Replace placeholder bar with `DockTopBar`. |
| `MacAllYouNeed/ClipboardDock/Views/Carousel/ClipCarousel.swift` | Read shortcuts via `ShortcutMatcher`, no hard-coded keys. |
| `MacAllYouNeed/ClipboardDock/Window/DockWindowController.swift` | Inject `ShortcutRegistry`. |
| `MacAllYouNeed/Settings/SettingsRoot.swift` | Add Shortcuts tab. |
| `MacAllYouNeed/Settings/HotkeyMapStore.swift` | Allow `[HotkeyAction: [HotkeyDescriptor]]` (multiple triggers per action). |
| `MacAllYouNeed/App/HotkeyRegistry.swift` | Register every descriptor in the array, not just one. |

---

## Task 1: `Pinboard.color: String?`

**Files:**
- Modify: `Shared/Sources/Core/Models/Pinboard.swift`
- Test: `Shared/Tests/CoreTests/Storage/PinboardColorTests.swift`

`Codable` Optional + missing-key-decodes-to-nil means existing pinboard envelopes decode with `color = nil`. No SQL migration.

- [ ] **Step 1: Write the failing test**

```swift
@testable import Core
import CryptoKit
import XCTest

final class PinboardColorTests: XCTestCase {
    var dir: URL!
    override func setUp() {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PinColor-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    func testColorRoundTripsThroughEncryptedEnvelope() throws {
        let key = SymmetricKey(size: .bits256)
        let db = try Database(url: dir.appendingPathComponent("p.sqlite"),
                              migrations: PinboardStore.migrations)
        let store = PinboardStore(database: db, deviceKey: key)
        var pb = try store.create(name: "Project X")
        pb.color = "#FF8800"
        try store.update(pb)
        let loaded = try store.list().first { $0.id == pb.id }
        XCTAssertEqual(loaded?.color, "#FF8800")
    }

    func testLegacyEnvelopeWithoutColorDecodesToNil() throws {
        // Hand-craft a Pinboard JSON without color, encode through the same
        // CryptoKit envelope, persist directly, then load via PinboardStore.
        let key = SymmetricKey(size: .bits256)
        let db = try Database(url: dir.appendingPathComponent("p.sqlite"),
                              migrations: PinboardStore.migrations)
        let store = PinboardStore(database: db, deviceKey: key)

        let legacyJSON = #"""
        {"id":"01HFAKEFAKEFAKEFAKEFAKEFAK","name":"old","itemIDs":[],
         "modified":1700000000.0,"deviceID":null,"lamport":0}
        """#
        let env = try Cipher.seal(legacyJSON.data(using: .utf8)!, with: key)
        try db.queue.write { conn in
            try conn.execute(sql: """
                INSERT INTO pinboards(id,name,sort_order,envelope,modified,device_id,lamport)
                VALUES('01HFAKEFAKEFAKEFAKEFAKEFAK','old',0,?,1700000000,NULL,0)
                """, arguments: [env.combined])
        }
        let loaded = try store.list().first
        XCTAssertEqual(loaded?.name, "old")
        XCTAssertNil(loaded?.color)
    }
}
```

- [ ] **Step 2: Verify test fails**

```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter PinboardColorTests
```

Expected: FAIL — `Pinboard.color` doesn't exist; `PinboardStore.update` doesn't exist (yet).

- [ ] **Step 3: Add `color` to `Pinboard`**

Replace `Shared/Sources/Core/Models/Pinboard.swift`:

```swift
import Foundation

public struct Pinboard: Codable, Equatable, Sendable {
    public let id: RecordID
    public var name: String
    public var color: String?
    public var itemIDs: [RecordID]
    public var modified: Date
    public var deviceID: DeviceID?
    public var lamport: UInt64

    public init(name: String, color: String? = nil, itemIDs: [RecordID] = []) {
        id = RecordID.generate()
        self.name = name
        self.color = color
        self.itemIDs = itemIDs
        modified = Date()
        deviceID = nil
        lamport = 0
    }
}
```

- [ ] **Step 4: Expose `update(_:)` on `PinboardStore`**

In `Shared/Sources/Core/Storage/PinboardStore.swift`, change `private func update(_:)` to `public func update(_:)`:

```swift
    public func update(_ pinboard: Pinboard) throws {
        let env = try Cipher.seal(JSONEncoder().encode(pinboard), with: key)
        try db.queue.write { conn in
            try conn.execute(sql: """
                UPDATE pinboards SET name = ?, envelope = ?, modified = ?, device_id = ?, lamport = ? WHERE id = ?
            """, arguments: [
                pinboard.name, env.combined, pinboard.modified.timeIntervalSince1970,
                pinboard.deviceID?.rawValue, pinboard.lamport, pinboard.id.rawValue
            ])
        }
    }
```

Also extend `create` to accept color:

```swift
    @discardableResult
    public func create(name: String, color: String? = nil) throws -> Pinboard {
        let pinboard = Pinboard(name: name, color: color)
        try persist(pinboard, order: maxOrder() + 1)
        return pinboard
    }
```

- [ ] **Step 5: Run tests + commit**

```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter PinboardColorTests
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test  # full regression
git add Shared/Sources/Core/Models/Pinboard.swift \
        Shared/Sources/Core/Storage/PinboardStore.swift \
        Shared/Tests/CoreTests/Storage/PinboardColorTests.swift
git commit -m "$(cat <<'EOF'
feat(pinboard): add color field; expose update() on PinboardStore

Color lives inside the encrypted envelope; legacy envelopes without
color decode to nil via standard Codable Optional behavior. Promotes
update() and create() (with color param) to public so the dock UI
can mutate pinboards.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Reserved `__pinned__` Pinboard helper

**Files:**
- Create: `MacAllYouNeed/ClipboardDock/Model/PinnedPinboard.swift`

Cross-list "Pinned" tab in spec §8.2 is implemented via a reserved Pinboard with name `__pinned__`. Auto-created on first lookup. UI hides it from the user-facing list.

- [ ] **Step 1: Implement (no separate test — coverage via Task 7's model test)**

```swift
import Core
import Foundation

enum PinnedPinboard {
    static let reservedName = "__pinned__"

    static func findOrCreate(in store: PinboardStore) throws -> Pinboard {
        if let existing = (try? store.list())?.first(where: { $0.name == reservedName }) {
            return existing
        }
        return try store.create(name: reservedName, color: nil)
    }

    static func userVisibleLists(_ all: [Pinboard]) -> [Pinboard] {
        all.filter { $0.name != reservedName }
    }
}
```

- [ ] **Step 2: Build + commit**

```bash
xcodegen generate
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build 2>&1 | tail -5
git add MacAllYouNeed/ClipboardDock/Model/PinnedPinboard.swift MacAllYouNeed.xcodeproj
git commit -m "feat(dock): add reserved __pinned__ Pinboard helper"
```

---

## Task 3: Extend `DockListSelector`

**Files:**
- Modify: `MacAllYouNeed/ClipboardDock/Model/DockListSelector.swift`

- [ ] **Step 1: Replace contents**

```swift
import Core
import Foundation

enum DockListSelector: Hashable {
    case history
    case pinned
    case pinboard(RecordID)
    case snippets
}
```

- [ ] **Step 2: Build + commit**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build 2>&1 | tail -5
git add MacAllYouNeed/ClipboardDock/Model/DockListSelector.swift
git commit -m "feat(dock): extend DockListSelector with pinned/pinboard/snippets"
```

---

## Task 4: Wire `pinboardStore` into `AppDependencies`

**Files:**
- Modify: `MacAllYouNeed/App/AppDependencies.swift`

- [ ] **Step 1: Add stored property and construct it**

In `AppDependencies.swift` add at top (after `imageLoader`):

```swift
    let pinboardStore: PinboardStore
```

In `init`, before `dockModel = ...`:

```swift
        let key = try? KeyManager(keychain: SystemKeychain()).deviceKey()
        let pinboardDB = try? Database(
            url: AppGroup.containerURL().appendingPathComponent("databases/pinboards.sqlite"),
            migrations: PinboardStore.migrations
        )
        let pinboards: PinboardStore = {
            if let key, let pinboardDB { return PinboardStore(database: pinboardDB, deviceKey: key) }
            // Fallback: in-memory store (only used if KeyManager fails — never in prod)
            let tmp = try! Database(
                url: FileManager.default.temporaryDirectory.appendingPathComponent("pb-\(UUID()).sqlite"),
                migrations: PinboardStore.migrations
            )
            return PinboardStore(database: tmp, deviceKey: SymmetricKey(size: .bits256))
        }()
        pinboardStore = pinboards
```

Update `ClipboardDockModel.init` callsite (added in Task 5).

- [ ] **Step 2: Build + commit (after Task 5 widens model init)**

Combined with Task 5's commit.

---

## Task 5: `ClipboardDockModel` — `activeList`, `availableLists`, `togglePin`, `addToPinboard`, scoped refresh

**Files:**
- Modify: `MacAllYouNeed/ClipboardDock/Model/ClipboardDockModel.swift`
- Create: `MacAllYouNeedTests/ClipboardDock/ClipboardDockModelListSwitchingTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
@testable import MacAllYouNeed
import Core
import CryptoKit
import XCTest

@MainActor
final class ClipboardDockModelListSwitchingTests: XCTestCase {
    final class MockClient: ClipboardXPCInteracting {
        var lastQuery: String?
        var resultsByQuery: [String?: [ClipboardXPCMeta]] = [:]
        var metasByIDsResults: [ClipboardXPCMeta] = []
        func listItems(query: String?, pageToken: String?, limit: Int) async -> ClipboardXPCList {
            lastQuery = query
            return ClipboardXPCList(items: resultsByQuery[query] ?? [], nextPageToken: nil)
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
        let db = try Database(url: dir.appendingPathComponent("p.sqlite"),
                              migrations: PinboardStore.migrations)
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
        mock.resultsByQuery[nil] = [
            ClipboardXPCMeta(id: "a", modified: Date(), kind: "clipboardItem", preview: "x")
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
        let updated = try pinboards.list().first { $0.id == pinned.id }!
        XCTAssertTrue(updated.itemIDs.contains(id))
    }

    func testTogglePinRemovesIfAlreadyPinned() async throws {
        let id = RecordID.generate()
        await model.togglePin(itemID: id.rawValue)
        await model.togglePin(itemID: id.rawValue)
        let pinned = try pinboards.list().first { $0.name == PinnedPinboard.reservedName }!
        XCTAssertFalse(pinned.itemIDs.contains(id))
    }

    func testAvailableListsExcludesReservedPinned() async throws {
        _ = try PinnedPinboard.findOrCreate(in: pinboards)
        _ = try pinboards.create(name: "Useful")
        await model.loadAvailableLists()
        XCTAssertEqual(model.availableLists.map(\.name), ["Useful"])
    }
}
```

- [ ] **Step 2: Verify it fails**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeedTests test -only-testing:MacAllYouNeedTests/ClipboardDockModelListSwitchingTests 2>&1 | tail -10
```

Expected: FAIL — `pinboards` arg, `switchList`, `togglePin`, `loadAvailableLists`, `availableLists` don't exist.

- [ ] **Step 3: Update `ClipboardDockModel`**

Append/modify in `MacAllYouNeed/ClipboardDock/Model/ClipboardDockModel.swift`:

```swift
import Core
import Foundation
import Observation

@MainActor
@Observable
final class ClipboardDockModel {
    let xpc: any ClipboardXPCInteracting
    let appIcons: AppIconResolver
    let imageLoader: ImageBlobLoader
    let fileLoader: FileURLLoader
    let pinboards: PinboardStore

    var items: [DockItem] = []
    var search: String = ""
    var focusedIndex: Int = 0
    var activeList: DockListSelector = .history
    var availableLists: [Pinboard] = []

    init(
        xpc: any ClipboardXPCInteracting,
        appIcons: AppIconResolver,
        imageLoader: ImageBlobLoader,
        fileLoader: FileURLLoader,
        pinboards: PinboardStore
    ) {
        self.xpc = xpc
        self.appIcons = appIcons
        self.imageLoader = imageLoader
        self.fileLoader = fileLoader
        self.pinboards = pinboards
    }

    func loadAvailableLists() async {
        availableLists = ((try? pinboards.list()) ?? []).filter {
            $0.name != PinnedPinboard.reservedName
        }
    }

    func switchList(_ selector: DockListSelector) async {
        activeList = selector
        search = ""
        focusedIndex = 0
        await refresh()
    }

    func refresh() async {
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let query: String? = trimmed.isEmpty ? nil : trimmed

        switch activeList {
        case .history:
            await loadFromXPC(query: query)
        case .pinned:
            await loadPinned(query: query)
        case let .pinboard(id):
            await loadPinboard(id: id, query: query)
        case .snippets:
            // Phase F implements this branch; stub for now.
            items = []
            focusedIndex = 0
        }
    }

    func togglePin(itemID: String) async {
        guard let recordID = RecordID(rawValue: itemID),
              var pinned = try? PinnedPinboard.findOrCreate(in: pinboards) else { return }
        if pinned.itemIDs.contains(recordID) {
            pinned.itemIDs.removeAll { $0 == recordID }
        } else {
            pinned.itemIDs.append(recordID)
        }
        pinned.modified = Date()
        try? pinboards.update(pinned)
        if activeList == .pinned { await refresh() }
    }

    func addToPinboard(itemIDs: [String], boardID: RecordID) async {
        guard var pinboard = (try? pinboards.list())?.first(where: { $0.id == boardID }) else { return }
        for raw in itemIDs {
            guard let rid = RecordID(rawValue: raw),
                  !pinboard.itemIDs.contains(rid) else { continue }
            pinboard.itemIDs.append(rid)
        }
        pinboard.modified = Date()
        try? pinboards.update(pinboard)
    }

    func focusForward() {
        guard !items.isEmpty else { return }
        focusedIndex = min(items.count - 1, focusedIndex + 1)
    }

    func focusBackward() {
        guard !items.isEmpty else { return }
        focusedIndex = max(0, focusedIndex - 1)
    }

    private func loadFromXPC(query: String?) async {
        let list = await xpc.listItems(query: query, pageToken: nil, limit: 50)
        items = list.items.map { meta in
            buildDockItem(from: meta, isPinned: pinnedIDs().contains(RecordID(rawValue: meta.id)!))
        }
    }

    private func loadPinned(query: String?) async {
        guard let pinned = try? PinnedPinboard.findOrCreate(in: pinboards) else {
            items = []; return
        }
        await loadByIDs(pinned.itemIDs.map(\.rawValue), query: query)
    }

    private func loadPinboard(id: RecordID, query: String?) async {
        guard let board = (try? pinboards.list())?.first(where: { $0.id == id }) else {
            items = []; return
        }
        await loadByIDs(board.itemIDs.map(\.rawValue), query: query)
    }

    private func loadByIDs(_ ids: [String], query: String?) async {
        let list = await xpc.metasByIDs(ids: ids)
        let filtered: [ClipboardXPCMeta]
        if let query, !query.isEmpty {
            let q = query.lowercased()
            filtered = list.items.filter { $0.preview.lowercased().contains(q) }
        } else {
            filtered = list.items
        }
        items = filtered.map { buildDockItem(from: $0, isPinned: true) }
    }

    private func pinnedIDs() -> Set<RecordID> {
        guard let pinned = try? PinnedPinboard.findOrCreate(in: pinboards) else { return [] }
        return Set(pinned.itemIDs)
    }

    private func buildDockItem(from meta: ClipboardXPCMeta, isPinned: Bool) -> DockItem {
        let app: SourceApp? = meta.sourceAppBundleID.map {
            SourceApp(
                bundleID: $0,
                displayName: appIcons.displayName(for: $0),
                icon: appIcons.icon(for: $0)
            )
        }
        return DockItem(from: meta, sourceApp: app, isPinned: isPinned)
    }
}
```

- [ ] **Step 4: Update construction sites**

In `MacAllYouNeed/App/AppDependencies.swift`, replace:

```swift
        dockModel = ClipboardDockModel(
            xpc: client, appIcons: appIcons,
            imageLoader: imgLoader, fileLoader: urlLoader
        )
```

with:

```swift
        dockModel = ClipboardDockModel(
            xpc: client, appIcons: appIcons,
            imageLoader: imgLoader, fileLoader: urlLoader,
            pinboards: pinboards
        )
```

In Phase B's `ClipboardDockModelTests` (`MacAllYouNeedTests/ClipboardDock/ClipboardDockModelTests.swift`) update `makeModel`:

```swift
    private func makeModel(_ mock: MockClient) -> ClipboardDockModel {
        let key = SymmetricKey(size: .bits256)
        let db = try! Database(
            url: FileManager.default.temporaryDirectory.appendingPathComponent("pb-\(UUID()).sqlite"),
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
```

Also import `Core` and `CryptoKit` at top of that test file if not already present.

- [ ] **Step 5: Run tests + commit**

```bash
xcodegen generate
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeedTests test -only-testing:MacAllYouNeedTests/ClipboardDockModelListSwitchingTests test -only-testing:MacAllYouNeedTests/ClipboardDockModelTests 2>&1 | tail -10
git add MacAllYouNeed/ClipboardDock/Model/ClipboardDockModel.swift \
        MacAllYouNeed/App/AppDependencies.swift \
        MacAllYouNeedTests/ClipboardDock/ClipboardDockModelListSwitchingTests.swift \
        MacAllYouNeedTests/ClipboardDock/ClipboardDockModelTests.swift \
        MacAllYouNeed.xcodeproj
git commit -m "$(cat <<'EOF'
feat(dock): extend ClipboardDockModel with active list + pinning

activeList switching, scoped refresh per .history/.pinned/.pinboard
/.snippets, togglePin via reserved __pinned__ Pinboard, addToPinboard,
loadAvailableLists. AppDependencies now constructs PinboardStore from
the app group. .snippets branch is a stub until Phase F.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: `ShortcutAction` enum

**Files:**
- Create: `MacAllYouNeed/ClipboardDock/Shortcuts/ShortcutAction.swift`

- [ ] **Step 1: Implement**

```bash
mkdir -p MacAllYouNeed/ClipboardDock/Shortcuts
```

```swift
import Foundation

enum ShortcutAction: String, CaseIterable, Identifiable {
    case focusSearch
    case togglePin
    case addToList
    case deleteFocused
    case quickLook
    case cycleFocus
    case dismiss
    case paste
    case pastePlain
    case extendSelectionLeft
    case extendSelectionRight
    case jumpToFirst
    case jumpToLast
    case toggleCheatsheet
    case transformFocused
    // Phase E adds: case suspendCapture

    var id: String { rawValue }

    var label: String {
        switch self {
        case .focusSearch:           return "Focus search field"
        case .togglePin:             return "Pin / unpin focused item"
        case .addToList:             return "Add focused / selected to list"
        case .deleteFocused:         return "Delete focused item"
        case .quickLook:             return "Quick Look"
        case .cycleFocus:            return "Cycle focus area"
        case .dismiss:               return "Dismiss dock"
        case .paste:                 return "Paste focused (or merge selection)"
        case .pastePlain:            return "Paste as plain text"
        case .extendSelectionLeft:   return "Extend selection left"
        case .extendSelectionRight:  return "Extend selection right"
        case .jumpToFirst:           return "Jump to first item"
        case .jumpToLast:            return "Jump to last item"
        case .toggleCheatsheet:      return "Toggle keyboard cheatsheet"
        case .transformFocused:      return "Transform focused item"
        }
    }
}
```

- [ ] **Step 2: Build + commit**

```bash
xcodegen generate
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build 2>&1 | tail -5
git add MacAllYouNeed/ClipboardDock/Shortcuts/ShortcutAction.swift MacAllYouNeed.xcodeproj
git commit -m "feat(dock): add ShortcutAction enum"
```

---

## Task 7: `ShortcutBinding` codable struct

**Files:**
- Create: `MacAllYouNeed/ClipboardDock/Shortcuts/ShortcutBinding.swift`

- [ ] **Step 1: Implement**

```swift
import AppKit
import Foundation

struct ShortcutBinding: Codable, Hashable {
    /// The 16-bit virtual key code (NSEvent.keyCode).
    let keyCode: UInt16
    /// Bitmask of NSEvent.ModifierFlags.deviceIndependentFlagsMask.
    let modifierMask: UInt

    func display() -> String {
        var parts: [String] = []
        let m = NSEvent.ModifierFlags(rawValue: modifierMask)
        if m.contains(.control) { parts.append("⌃") }
        if m.contains(.option)  { parts.append("⌥") }
        if m.contains(.shift)   { parts.append("⇧") }
        if m.contains(.command) { parts.append("⌘") }
        parts.append(KeyCode.symbol(for: keyCode))
        return parts.joined()
    }
}

private enum KeyCode {
    static func symbol(for code: UInt16) -> String {
        switch code {
        case 49:  return "Space"
        case 36:  return "↩"
        case 48:  return "⇥"
        case 51:  return "⌫"
        case 53:  return "⎋"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default:
            // Best-effort character lookup via TIS (deferred). For now show keyCode.
            if let s = String(UnicodeScalar(0x40 + Int(code))) {
                return String(s).uppercased()
            }
            return "K\(code)"
        }
    }
}
```

- [ ] **Step 2: Build + commit**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build 2>&1 | tail -5
git add MacAllYouNeed/ClipboardDock/Shortcuts/ShortcutBinding.swift
git commit -m "feat(dock): add ShortcutBinding codable struct"
```

---

## Task 8: `ShortcutDefaults`

**Files:**
- Create: `MacAllYouNeed/ClipboardDock/Shortcuts/ShortcutDefaults.swift`

- [ ] **Step 1: Implement**

```swift
import AppKit
import Foundation

enum ShortcutDefaults {
    static func defaultBindings(for action: ShortcutAction) -> [ShortcutBinding] {
        let cmd: UInt = NSEvent.ModifierFlags.command.rawValue
        let shift: UInt = NSEvent.ModifierFlags.shift.rawValue
        let opt: UInt = NSEvent.ModifierFlags.option.rawValue
        switch action {
        case .focusSearch:
            return [ShortcutBinding(keyCode: 3, modifierMask: cmd)]                      // ⌘F
        case .togglePin:
            return [ShortcutBinding(keyCode: 35, modifierMask: cmd)]                     // ⌘P
        case .addToList:
            return [ShortcutBinding(keyCode: 37, modifierMask: cmd)]                     // ⌘L
        case .deleteFocused:
            return [ShortcutBinding(keyCode: 51, modifierMask: cmd)]                     // ⌘⌫
        case .quickLook:
            return [ShortcutBinding(keyCode: 49, modifierMask: 0)]                       // Space
        case .cycleFocus:
            return [ShortcutBinding(keyCode: 48, modifierMask: 0)]                       // Tab
        case .dismiss:
            return [ShortcutBinding(keyCode: 53, modifierMask: 0)]                       // Esc
        case .paste:
            return [ShortcutBinding(keyCode: 36, modifierMask: 0)]                       // Return
        case .pastePlain:
            return [ShortcutBinding(keyCode: 36, modifierMask: opt)]                     // ⌥+Return
        case .extendSelectionLeft:
            return [ShortcutBinding(keyCode: 123, modifierMask: shift)]                  // ⇧+←
        case .extendSelectionRight:
            return [ShortcutBinding(keyCode: 124, modifierMask: shift)]                  // ⇧+→
        case .jumpToFirst:
            return [ShortcutBinding(keyCode: 123, modifierMask: cmd)]                    // ⌘+←
        case .jumpToLast:
            return [ShortcutBinding(keyCode: 124, modifierMask: cmd)]                    // ⌘+→
        case .toggleCheatsheet:
            return [ShortcutBinding(keyCode: 44, modifierMask: cmd | shift)]             // ⌘?
        case .transformFocused:
            return [ShortcutBinding(keyCode: 17, modifierMask: cmd)]                     // ⌘T
        }
    }
}
```

- [ ] **Step 2: Build + commit**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build 2>&1 | tail -5
git add MacAllYouNeed/ClipboardDock/Shortcuts/ShortcutDefaults.swift
git commit -m "feat(dock): add ShortcutDefaults with default key bindings"
```

---

## Task 9: `ShortcutRegistry` + matcher

**Files:**
- Create: `MacAllYouNeed/ClipboardDock/Shortcuts/ShortcutRegistry.swift`
- Create: `MacAllYouNeed/ClipboardDock/Shortcuts/ShortcutMatcher.swift`
- Test: `MacAllYouNeedTests/ClipboardDock/ShortcutRegistryTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
@testable import MacAllYouNeed
import AppKit
import XCTest

@MainActor
final class ShortcutRegistryTests: XCTestCase {
    override func setUp() {
        // Isolate per-test by writing to a unique suite.
        let suite = "test.shortcuts.\(UUID().uuidString)"
        UserDefaults.standard.removePersistentDomain(forName: suite)
        ShortcutRegistry.testSuite = suite
    }

    func testReturnsDefaultBindingForUnconfiguredAction() {
        let r = ShortcutRegistry()
        let bindings = r.bindings(for: .focusSearch)
        XCTAssertEqual(bindings, ShortcutDefaults.defaultBindings(for: .focusSearch))
    }

    func testSetAndPersistBinding() {
        let r = ShortcutRegistry()
        let custom = ShortcutBinding(keyCode: 11, modifierMask: NSEvent.ModifierFlags.command.rawValue) // ⌘B
        r.setBindings([custom], for: .togglePin)
        XCTAssertEqual(r.bindings(for: .togglePin), [custom])

        let r2 = ShortcutRegistry()
        XCTAssertEqual(r2.bindings(for: .togglePin), [custom])
    }

    func testAddBindingAppendsToExisting() {
        let r = ShortcutRegistry()
        let extra = ShortcutBinding(keyCode: 11, modifierMask: NSEvent.ModifierFlags.command.rawValue)
        r.addBinding(extra, for: .togglePin)
        XCTAssertTrue(r.bindings(for: .togglePin).contains(extra))
        XCTAssertTrue(r.bindings(for: .togglePin).count >= 2)
    }

    func testResetRestoresDefaults() {
        let r = ShortcutRegistry()
        r.setBindings([], for: .togglePin)
        XCTAssertTrue(r.bindings(for: .togglePin).isEmpty)
        r.reset(action: .togglePin)
        XCTAssertEqual(r.bindings(for: .togglePin), ShortcutDefaults.defaultBindings(for: .togglePin))
    }

    func testReservedKeysAreRejectedForOtherActions() {
        let r = ShortcutRegistry()
        let escForPin = ShortcutBinding(keyCode: 53, modifierMask: 0)
        XCTAssertThrowsError(try r.validate(escForPin, for: .togglePin))
    }

    func testReservedKeyAcceptedForItsConventionalAction() {
        let r = ShortcutRegistry()
        let escForDismiss = ShortcutBinding(keyCode: 53, modifierMask: 0)
        XCTAssertNoThrow(try r.validate(escForDismiss, for: .dismiss))
    }
}
```

- [ ] **Step 2: Verify failure**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeedTests test -only-testing:MacAllYouNeedTests/ShortcutRegistryTests 2>&1 | tail -10
```

Expected: FAIL.

- [ ] **Step 3: Implement `ShortcutRegistry`**

```swift
import AppKit
import Core
import Foundation
import Observation

enum ShortcutValidationError: Error {
    case reservedKey(UInt16)
    case unsupportedModifier
}

@MainActor
@Observable
final class ShortcutRegistry {
    static var testSuite: String? = nil

    private let defaults: UserDefaults
    private var cache: [ShortcutAction: [ShortcutBinding]] = [:]

    init() {
        if let suite = Self.testSuite {
            defaults = UserDefaults(suiteName: suite) ?? .standard
        } else {
            defaults = AppGroupSettings.defaults
        }
    }

    func bindings(for action: ShortcutAction) -> [ShortcutBinding] {
        if let cached = cache[action] { return cached }
        let key = "shortcut.\(action.rawValue)"
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([ShortcutBinding].self, from: data) {
            cache[action] = decoded
            return decoded
        }
        return ShortcutDefaults.defaultBindings(for: action)
    }

    func setBindings(_ bindings: [ShortcutBinding], for action: ShortcutAction) {
        cache[action] = bindings
        let key = "shortcut.\(action.rawValue)"
        if let data = try? JSONEncoder().encode(bindings) {
            defaults.set(data, forKey: key)
        }
    }

    func addBinding(_ binding: ShortcutBinding, for action: ShortcutAction) {
        var current = bindings(for: action)
        if !current.contains(binding) { current.append(binding) }
        setBindings(current, for: action)
    }

    func removeBinding(_ binding: ShortcutBinding, for action: ShortcutAction) {
        var current = bindings(for: action)
        current.removeAll { $0 == binding }
        setBindings(current, for: action)
    }

    func reset(action: ShortcutAction) {
        let key = "shortcut.\(action.rawValue)"
        defaults.removeObject(forKey: key)
        cache.removeValue(forKey: action)
    }

    func validate(_ binding: ShortcutBinding, for action: ShortcutAction) throws {
        // Reserved unmodified keys: each is conventionally tied to one action.
        // User can bind a reserved key to its conventional action (default behavior)
        // but NOT to any other action.
        let conventional: [UInt16: ShortcutAction] = [
            53: .dismiss,                  // Esc
            36: .paste,                    // Return
            48: .cycleFocus,               // Tab
            49: .quickLook,                // Space
            123: .extendSelectionLeft,     // ⇧+← only when shift modifier; plain ← reserved for nav
            124: .extendSelectionRight     // analogous
        ]
        if binding.modifierMask == 0,
           let owner = conventional[binding.keyCode],
           owner != action {
            throw ShortcutValidationError.reservedKey(binding.keyCode)
        }
    }

    func matches(event: NSEvent, _ action: ShortcutAction) -> Bool {
        let mask = NSEvent.ModifierFlags.deviceIndependentFlagsMask.rawValue
        let eventMods = event.modifierFlags.rawValue & mask
        for b in bindings(for: action) {
            if b.keyCode == event.keyCode && b.modifierMask == eventMods {
                return true
            }
        }
        return false
    }
}
```

- [ ] **Step 4: Add `ShortcutMatcher` (stateless wrapper for SwiftUI)**

```swift
import AppKit

enum ShortcutMatcher {
    static func matches(_ event: NSEvent, _ action: ShortcutAction, registry: ShortcutRegistry) -> Bool {
        registry.matches(event: event, action)
    }
}
```

- [ ] **Step 5: Run tests + commit**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeedTests test -only-testing:MacAllYouNeedTests/ShortcutRegistryTests 2>&1 | tail -10
git add MacAllYouNeed/ClipboardDock/Shortcuts/ShortcutRegistry.swift \
        MacAllYouNeed/ClipboardDock/Shortcuts/ShortcutMatcher.swift \
        MacAllYouNeedTests/ClipboardDock/ShortcutRegistryTests.swift
git commit -m "$(cat <<'EOF'
feat(dock): add ShortcutRegistry with persistence + conflict policy

@Observable, app-group UserDefaults persistence, multiple bindings
per action, reset to defaults, validate against reserved nav keys
(Esc/Return/Tab/Space/arrows when no modifier). Matcher checks
NSEvent against registered bindings for in-dock use.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: `ShortcutRecorderView` SwiftUI control

**Files:**
- Create: `MacAllYouNeed/ClipboardDock/Shortcuts/ShortcutRecorderView.swift`

Modeled on existing `MacAllYouNeed/Settings/HotkeyRecorder.swift` (which targets `HotkeyDescriptor`); this one targets `ShortcutBinding`.

- [ ] **Step 1: Implement**

```swift
import AppKit
import SwiftUI

struct ShortcutRecorderView: NSViewRepresentable {
    @Binding var binding: ShortcutBinding?
    let onCapture: (ShortcutBinding) -> Void

    func makeNSView(context: Context) -> RecorderView {
        RecorderView(binding: $binding, onCapture: onCapture)
    }
    func updateNSView(_ nsView: RecorderView, context: Context) { nsView.refresh() }

    final class RecorderView: NSView {
        @Binding var binding: ShortcutBinding?
        let onCapture: (ShortcutBinding) -> Void
        private let label = NSTextField(labelWithString: "")

        init(binding: Binding<ShortcutBinding?>, onCapture: @escaping (ShortcutBinding) -> Void) {
            _binding = binding
            self.onCapture = onCapture
            super.init(frame: .zero)
            label.stringValue = binding.wrappedValue?.display() ?? "Click to record"
            addSubview(label)
            label.frame = NSRect(x: 4, y: 2, width: 120, height: 18)
            wantsLayer = true
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            layer?.cornerRadius = 4
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { return nil }

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            let mask = NSEvent.ModifierFlags.deviceIndependentFlagsMask.rawValue
            let mods = event.modifierFlags.rawValue & mask
            let captured = ShortcutBinding(keyCode: event.keyCode, modifierMask: mods)
            binding = captured
            label.stringValue = captured.display()
            onCapture(captured)
        }

        func refresh() {
            label.stringValue = binding?.display() ?? "Click to record"
        }
    }
}
```

- [ ] **Step 2: Build + commit**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build 2>&1 | tail -5
git add MacAllYouNeed/ClipboardDock/Shortcuts/ShortcutRecorderView.swift
git commit -m "feat(dock): add ShortcutRecorderView for in-dock shortcut capture"
```

---

## Task 11: `ShortcutsSettingsView` + tab in `SettingsRoot`

**Files:**
- Create: `MacAllYouNeed/Settings/ShortcutsSettingsView.swift`
- Modify: `MacAllYouNeed/Settings/SettingsRoot.swift`

- [ ] **Step 1: Implement settings view**

```swift
import SwiftUI

struct ShortcutsSettingsView: View {
    @Bindable var registry: ShortcutRegistry
    @State private var pendingError: String?

    var body: some View {
        Form {
            Section("In-Dock Shortcuts") {
                ForEach(ShortcutAction.allCases) { action in
                    HStack {
                        Text(action.label).frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(registry.bindings(for: action), id: \.self) { b in
                            Text(b.display())
                                .font(.system(.callout, design: .monospaced))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.15))
                                .clipShape(Capsule())
                                .contextMenu {
                                    Button("Remove") {
                                        registry.removeBinding(b, for: action)
                                    }
                                }
                        }
                        ShortcutRecorderView(binding: .constant(nil)) { captured in
                            do {
                                try registry.validate(captured, for: action)
                                registry.addBinding(captured, for: action)
                                pendingError = nil
                            } catch {
                                pendingError = "Cannot bind reserved key."
                            }
                        }
                        .frame(width: 130, height: 22)
                        Button("Reset") { registry.reset(action: action) }
                            .controlSize(.small)
                    }
                }
            }
            if let pendingError {
                Text(pendingError).foregroundStyle(.red).font(.callout)
            }
        }
        .padding()
    }
}
```

- [ ] **Step 2: Add tab to `SettingsRoot.swift`**

In the existing `TabView`, add (between Hotkeys and Advanced):

```swift
            ShortcutsSettingsView(registry: controller.shortcuts)
                .tabItem { Label("Shortcuts", systemImage: "command.square") }
```

- [ ] **Step 3: Add `shortcuts` to `AppController`**

In `MacAllYouNeed/App/AppController.swift`, add stored property:

```swift
    let shortcuts = ShortcutRegistry()
```

Pass it through to `DockWindowController` (Task 13 wires this).

- [ ] **Step 4: Build + commit**

```bash
xcodegen generate
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build 2>&1 | tail -5
git add MacAllYouNeed/Settings/ShortcutsSettingsView.swift \
        MacAllYouNeed/Settings/SettingsRoot.swift \
        MacAllYouNeed/App/AppController.swift \
        MacAllYouNeed.xcodeproj
git commit -m "feat(settings): add Shortcuts tab for in-dock shortcuts"
```

---

## Task 12: Wire `ClipCarousel` to `ShortcutRegistry`

**Files:**
- Modify: `MacAllYouNeed/ClipboardDock/Views/Carousel/ClipCarousel.swift`
- Modify: `MacAllYouNeed/ClipboardDock/Window/DockWindowController.swift`

Replace hard-coded `.onKeyPress(.leftArrow)` etc. with registry checks.

- [ ] **Step 1: Update `ClipCarousel`**

```swift
import SwiftUI

struct ClipCarousel: View {
    @Bindable var model: ClipboardDockModel
    let favicons: FaviconCache
    let registry: ShortcutRegistry
    let onPaste: (Int, Bool) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(Array(model.items.enumerated()), id: \.element.id) { idx, item in
                        CardSlot(
                            item: item, index: idx,
                            isFocused: idx == model.focusedIndex,
                            imageLoader: model.imageLoader,
                            favicons: favicons
                        )
                        .id(item.id)
                        .onTapGesture { onPaste(idx, false) }
                    }
                }
                .padding(.horizontal, 16)
            }
            .onChange(of: model.focusedIndex) { _, new in
                guard model.items.indices.contains(new) else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(model.items[new].id, anchor: .center)
                }
            }
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress { keyPress in
            // Build a synthetic NSEvent from KeyPress data is expensive; use simple
            // keyCode-equivalent matching for common in-dock actions.
            let raw = keyPress.key.character
            switch raw {
            case Character(UnicodeScalar(NSLeftArrowFunctionKey)!):
                model.focusBackward(); return .handled
            case Character(UnicodeScalar(NSRightArrowFunctionKey)!):
                model.focusForward(); return .handled
            case "\r":
                onPaste(model.focusedIndex, keyPress.modifiers.contains(.option))
                return .handled
            default:
                return .ignored
            }
        }
    }
}
```

For the full ShortcutRegistry-driven matching path, lower-level `NSEvent` interception (via `NSWindow.localMonitor` or a `NSResponder` chain on `BottomDockWindow`) is set up in step 2.

- [ ] **Step 2: Add `NSEvent.localMonitor` in `DockWindowController`**

```swift
    private var keyMonitor: Any?

    func show() {
        // … existing code …
        startKeyMonitor()
    }

    func hide() {
        stopKeyMonitor()
        // … existing code …
    }

    private func startKeyMonitor() {
        stopKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let win = window, win.isVisible else { return event }
            if registry.matches(event: event, .dismiss) {
                hide(); return nil
            }
            if registry.matches(event: event, .togglePin) {
                Task { @MainActor in
                    let id = model.items.indices.contains(model.focusedIndex)
                        ? model.items[model.focusedIndex].id : nil
                    if let id { await model.togglePin(itemID: id) }
                }
                return nil
            }
            // Phase D handles quickLook/transformFocused/extendSelection*; for now
            // forward unhandled events.
            return event
        }
    }

    private func stopKeyMonitor() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
    }
```

Add stored property `let registry: ShortcutRegistry` and accept it in init:

```swift
    init(model: ClipboardDockModel, pasteCoord: DockPasteCoordinator,
         favicons: FaviconCache, registry: ShortcutRegistry) {
        self.model = model
        self.pasteCoord = pasteCoord
        self.favicons = favicons
        self.registry = registry
    }
```

Update `AppController.swift` callsite:

```swift
        let dock = DockWindowController(
            model: deps.dockModel, pasteCoord: pasteCoord,
            favicons: favicons, registry: shortcuts
        )
```

Pass `registry: shortcuts` into `ClipCarousel` from `DockRootView`. Update both signatures.

- [ ] **Step 3: Build + commit**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build 2>&1 | tail -5
git add MacAllYouNeed/ClipboardDock/Views/Carousel/ClipCarousel.swift \
        MacAllYouNeed/ClipboardDock/Window/DockWindowController.swift \
        MacAllYouNeed/App/AppController.swift
git commit -m "feat(dock): route key events through ShortcutRegistry"
```

---

## Task 13: Multi-trigger global open-dock

**Files:**
- Modify: `MacAllYouNeed/Settings/HotkeyMapStore.swift`
- Modify: `MacAllYouNeed/App/HotkeyRegistry.swift`
- Modify: `MacAllYouNeed/Settings/HotkeysSettingsView.swift`

Today: one descriptor per `HotkeyAction`. Goal: an array per action so the user can register multiple combos for the same action (per spec §5 user requirement: "the user can add trigger / key comb themselves").

- [ ] **Step 1: Change storage shape**

```swift
import Core
import Foundation
import Platform

enum HotkeyAction: String, CaseIterable, Identifiable {
    case clipboard, addDownload, browseFolder
    var id: String { rawValue }
    var label: String {
        switch self {
        case .clipboard: return "Open clipboard popup"
        case .addDownload: return "Add download"
        case .browseFolder: return "Browse folder"
        }
    }
}

enum HotkeyMapStore {
    static let key = "hotkeyMapV2"

    static func load() -> [HotkeyAction: [HotkeyDescriptor]] {
        var defaults: [HotkeyAction: [HotkeyDescriptor]] = [
            .clipboard: [.defaultClipboard],
            .addDownload: [.defaultDownload],
            .browseFolder: [.defaultFolder]
        ]
        if let data = AppGroupSettings.defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([String: [HotkeyDescriptor]].self, from: data) {
            for (rawKey, descriptors) in decoded {
                if let action = HotkeyAction(rawValue: rawKey) { defaults[action] = descriptors }
            }
        }
        return defaults
    }

    static func save(_ map: [HotkeyAction: [HotkeyDescriptor]]) {
        let dict = Dictionary(uniqueKeysWithValues: map.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(dict) {
            AppGroupSettings.defaults.set(data, forKey: key)
        }
    }
}
```

Migration: previous `hotkeyMap` key is left untouched but ignored. New key is `hotkeyMapV2`.

- [ ] **Step 2: Update `HotkeyRegistry.apply(_:controller:)`**

Update its signature to `apply(_ map: [HotkeyAction: [HotkeyDescriptor]], controller: AppController)` and register each descriptor in the array (build N `GlobalHotkey` instances per action; store all).

- [ ] **Step 3: Update `HotkeysSettingsView`**

For each `HotkeyAction` row, render the existing `HotkeyRecorder` for the FIRST descriptor and add a `+` button to append a second/third descriptor. Each non-primary descriptor gets a `⌫` to remove.

- [ ] **Step 4: Update `AppController`**

```swift
        do {
            try hotkeyRegistry.apply(HotkeyMapStore.load(), controller: self)
        } catch {
            // Fallback unchanged
        }
```

(Already takes the new array shape after step 2.)

- [ ] **Step 5: Build + commit**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build 2>&1 | tail -5
git add MacAllYouNeed/Settings/HotkeyMapStore.swift \
        MacAllYouNeed/App/HotkeyRegistry.swift \
        MacAllYouNeed/Settings/HotkeysSettingsView.swift
git commit -m "feat(hotkeys): allow multiple global triggers per HotkeyAction"
```

---

## Task 14: `DockSearchField`

**Files:**
- Create: `MacAllYouNeed/ClipboardDock/Views/DockTopBar/DockSearchField.swift`

- [ ] **Step 1: Implement**

```bash
mkdir -p MacAllYouNeed/ClipboardDock/Views/DockTopBar
```

```swift
import SwiftUI

struct DockSearchField: View {
    @Binding var query: String
    @FocusState private var focused: Bool
    @State private var expanded = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .onTapGesture {
                    expanded = true
                    focused = true
                }
            if expanded || !query.isEmpty {
                TextField("Search…", text: $query)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .frame(width: 280)
                    .onChange(of: focused) { _, isFocused in
                        if !isFocused && query.isEmpty { expanded = false }
                    }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .animation(.easeOut(duration: 0.18), value: expanded)
    }
}
```

- [ ] **Step 2: Build + commit**

```bash
xcodegen generate
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build 2>&1 | tail -5
git add MacAllYouNeed/ClipboardDock/Views/DockTopBar/DockSearchField.swift MacAllYouNeed.xcodeproj
git commit -m "feat(dock): add DockSearchField with collapse/expand"
```

---

## Task 15: `DockListTabs`

**Files:**
- Create: `MacAllYouNeed/ClipboardDock/Views/DockTopBar/DockListTabs.swift`
- Create: `MacAllYouNeed/ClipboardDock/Views/DockTopBar/NewListSheet.swift`

- [ ] **Step 1: Implement `NewListSheet`**

```swift
import SwiftUI

struct NewListSheet: View {
    @Binding var isPresented: Bool
    let onCreate: (String, String?) -> Void

    @State private var name: String = ""
    @State private var color: String? = "#FF8800"
    private let palette: [String] = ["#FF8800", "#34C759", "#007AFF", "#FF3B30",
                                     "#AF52DE", "#5AC8FA", "#FFCC00", "#8E8E93"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New List").font(.headline)
            TextField("Name", text: $name).textFieldStyle(.roundedBorder)
            HStack {
                ForEach(palette, id: \.self) { hex in
                    Circle()
                        .fill(Color(hex: hex) ?? .gray)
                        .frame(width: 22, height: 22)
                        .overlay(
                            Circle().stroke(color == hex ? Color.accentColor : .clear, lineWidth: 2)
                        )
                        .onTapGesture { color = hex }
                }
            }
            HStack {
                Button("Cancel") { isPresented = false }
                Spacer()
                Button("Create") {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    onCreate(trimmed, color)
                    isPresented = false
                }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}

private extension Color {
    init?(hex: String) {
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard h.count == 6, let v = UInt64(h, radix: 16) else { return nil }
        self = Color(red: Double((v >> 16) & 0xFF) / 255,
                     green: Double((v >> 8) & 0xFF) / 255,
                     blue: Double(v & 0xFF) / 255)
    }
}
```

- [ ] **Step 2: Implement `DockListTabs`**

```swift
import Core
import SwiftUI

struct DockListTabs: View {
    @Bindable var model: ClipboardDockModel
    @State private var showNew = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                tab(label: "Clipboard History", selector: .history, dotColor: nil)
                tab(label: "📌 Pinned", selector: .pinned, dotColor: nil)
                tab(label: "Snippets", selector: .snippets, dotColor: nil)
                ForEach(model.availableLists, id: \.id) { board in
                    tab(label: board.name, selector: .pinboard(board.id),
                        dotColor: board.color)
                        .contextMenu {
                            Button("Rename…") { /* Phase C v1.1 */ }
                            Button("Delete", role: .destructive) {
                                Task {
                                    try? model.pinboards.delete(id: board.id)
                                    await model.loadAvailableLists()
                                }
                            }
                        }
                }
                Button { showNew = true } label: {
                    Image(systemName: "plus").font(.callout)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 6)
            }
            .padding(.horizontal, 8)
        }
        .task { await model.loadAvailableLists() }
        .sheet(isPresented: $showNew) {
            NewListSheet(isPresented: $showNew) { name, color in
                Task {
                    _ = try? model.pinboards.create(name: name, color: color)
                    await model.loadAvailableLists()
                }
            }
        }
    }

    @ViewBuilder
    private func tab(label: String, selector: DockListSelector, dotColor: String?) -> some View {
        let active = model.activeList == selector
        Button {
            Task { await model.switchList(selector) }
        } label: {
            HStack(spacing: 4) {
                if let dot = dotColor, let c = colorFromHex(dot) {
                    Circle().fill(c).frame(width: 8, height: 8)
                }
                Text(label).font(.callout)
            }
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(active ? Color.secondary.opacity(0.2) : .clear)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func colorFromHex(_ hex: String) -> Color? {
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard h.count == 6, let v = UInt64(h, radix: 16) else { return nil }
        return Color(red: Double((v >> 16) & 0xFF) / 255,
                     green: Double((v >> 8) & 0xFF) / 255,
                     blue: Double(v & 0xFF) / 255)
    }
}
```

- [ ] **Step 3: Build + commit**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build 2>&1 | tail -5
git add MacAllYouNeed/ClipboardDock/Views/DockTopBar/DockListTabs.swift \
        MacAllYouNeed/ClipboardDock/Views/DockTopBar/NewListSheet.swift
git commit -m "feat(dock): add DockListTabs with built-ins + Pinboards + new-list sheet"
```

---

## Task 16: `DockMoreMenu`

**Files:**
- Create: `MacAllYouNeed/ClipboardDock/Views/DockTopBar/DockMoreMenu.swift`

For Phase C the menu only opens Settings. Phase E expands it (Privacy submenu, Clear Older Than submenu, Clear All History) once the underlying retention plumbing exists.

- [ ] **Step 1: Implement**

```swift
import SwiftUI

struct DockMoreMenu: View {
    let openSettings: () -> Void

    var body: some View {
        Menu {
            Button("Open Settings…") { openSettings() }
        } label: {
            Image(systemName: "ellipsis").font(.title3).foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .frame(width: 28, height: 28)
    }
}
```

- [ ] **Step 2: Build + commit**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build 2>&1 | tail -5
git add MacAllYouNeed/ClipboardDock/Views/DockTopBar/DockMoreMenu.swift
git commit -m "feat(dock): add DockMoreMenu skeleton (Settings only; Phase E extends)"
```

---

## Task 17: `DockTopBar` composition

**Files:**
- Create: `MacAllYouNeed/ClipboardDock/Views/DockTopBar/DockTopBar.swift`

- [ ] **Step 1: Implement**

```swift
import SwiftUI

struct DockTopBar: View {
    @Bindable var model: ClipboardDockModel
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            DockSearchField(query: $model.search)
                .onChange(of: model.search) { _, _ in
                    Task { await model.refresh() }
                }
            DockListTabs(model: model)
                .frame(maxWidth: .infinity)
            DockMoreMenu(openSettings: openSettings)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .frame(height: 52)
        .background(.thinMaterial)
    }
}
```

- [ ] **Step 2: Build + commit**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build 2>&1 | tail -5
git add MacAllYouNeed/ClipboardDock/Views/DockTopBar/DockTopBar.swift
git commit -m "feat(dock): add DockTopBar composing search + tabs + more menu"
```

---

## Task 18: Replace `DockRootView` placeholder bar with `DockTopBar`

**Files:**
- Modify: `MacAllYouNeed/ClipboardDock/Views/DockRootView.swift`
- Modify: `MacAllYouNeed/ClipboardDock/Window/DockWindowController.swift`

- [ ] **Step 1: Update `DockRootView`**

Replace the placeholder `HStack { magnifyingglass + TextField }` block with `DockTopBar(...)`. The view's outer signature gains `openSettings`:

```swift
struct DockRootView: View {
    @Bindable var model: ClipboardDockModel
    let favicons: FaviconCache
    let registry: ShortcutRegistry
    let dismiss: () -> Void
    let onPaste: (Int, Bool) -> Void
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            DockTopBar(model: model, openSettings: openSettings)
            Divider()
            ClipCarousel(
                model: model, favicons: favicons, registry: registry,
                onPaste: onPaste
            )
            .frame(maxHeight: .infinity)
        }
        .background(VisualEffectBackground(material: .popover, blendingMode: .behindWindow))
        .clipShape(RoundedCorners(radius: 12, corners: [.topLeft, .topRight]))
    }
}
```

- [ ] **Step 2: Update `DockWindowController.show()` callsite**

```swift
        panel.contentView = NSHostingView(
            rootView: DockRootView(
                model: model, favicons: favicons, registry: registry,
                dismiss: { [weak self] in self?.hide() },
                onPaste: { [weak self] idx, plain in
                    guard let self, model.items.indices.contains(idx) else { return }
                    let id = model.items[idx].id
                    Task {
                        await self.pasteCoord.paste(
                            itemID: id, plainText: plain,
                            dismissWindow: { self.hide() }
                        )
                    }
                },
                openSettings: { NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) }
            )
        )
```

`DockMoreMenu` in Phase C exposes only Open Settings — Clear All History lands in Phase E together with the underlying retention plumbing. No "future" closure stubs ship in this phase.

- [ ] **Step 4: Build + commit**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build 2>&1 | tail -5
git add MacAllYouNeed/ClipboardDock/Views/DockRootView.swift \
        MacAllYouNeed/ClipboardDock/Views/DockTopBar/DockMoreMenu.swift \
        MacAllYouNeed/ClipboardDock/Views/DockTopBar/DockTopBar.swift \
        MacAllYouNeed/ClipboardDock/Window/DockWindowController.swift
git commit -m "feat(dock): swap placeholder search bar for full DockTopBar"
```

---

## Task 19: Phase C smoke + regression

- [ ] **Step 1: Run all tests**

```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeedTests test 2>&1 | tail -20
```

Expected: all green.

- [ ] **Step 2: Manual smoke**

1. ⌘⇧V opens dock; new top bar shows search icon + History/Pinned/Snippets tabs + ⋯.
2. Click `+` → New List sheet appears, name + color → click Create → tab appears with colored dot.
3. Click new tab → carousel becomes empty (no items pinned to it yet).
4. Switch to History → carousel shows recent items.
5. ⌘P on a focused item → switch to Pinned tab → that item appears.
6. ⌘P again → item disappears from Pinned.
7. Settings → Shortcuts tab: rebind Pin to ⌘B → in dock, ⌘B pins the focused item.
8. Settings → Hotkeys tab: add a second open-dock combo (e.g. ⌘⇧C) → ⌘⇧C also opens the dock.
9. Search query persists per active list; switching tab clears it.

- [ ] **Step 3: No-op commit not required.**

---

## Phase C — Done

End-state of Phase C:

- Top bar with search, list tabs (built-in + Pinboards), and `⋯` Settings menu.
- New List sheet with color picker.
- Cross-list pinning via reserved `__pinned__` Pinboard; ⌘P toggles.
- `ShortcutRegistry` for in-dock shortcuts with multi-binding support, persistence, conflict policy.
- Shortcuts settings tab with `ShortcutRecorderView`.
- Multiple global open-dock triggers via expanded `HotkeyMapStore`.
- All Phase A/B tests still green; new Phase C tests added.

---

## What comes next

- **Phase D** — Multi-select, Quick Look, Transformations menu, drag-out, color picker.
- **Phase E** — Maccy improvements (privacy, storage caps, fuzzy search, frequency).
- **Phase F** — Snippets surfacing.
