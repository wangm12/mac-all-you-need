# Clipboard Dock — Phase F: Snippets Surfacing — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render snippets in the dock when the `Snippets` tab is active. Provide create / edit / delete / duplicate via a sheet. Pasting a snippet calls Phase A's `pasteText` so the action shows up in history with `com.macallyouneed.app` as the source.

**Architecture:** New `SnippetsListView` swaps in for the carousel when `model.activeList == .snippets`. `ClipboardDockModel` gains `snippets: [Snippet]` and a `loadSnippets()` method that calls `SnippetStore.list()`. `NewSnippetSheet` creates new snippets; right-click context menu on a snippet card edits/duplicates/deletes. Pasting fires `xpc.pasteText(text:plainText:saveAsNew:)`.

**Tech Stack:** SwiftUI, existing `SnippetStore` + `SnippetExpander`.

**Spec:** `docs/superpowers/specs/2026-05-07-clipboard-dock-redesign-design.md` §10.6.

**Depends on:** Phases A–E merged. Uses Phase A's `pasteText` RPC. Uses Phase C's `DockListSelector.snippets` and active-list switching.

**Working directory:** `/Users/mingjie.wang/Documents/personal/mac-all-you-need`

---

## File Structure

### Created

| Path | Responsibility |
|---|---|
| `MacAllYouNeed/ClipboardDock/Views/Snippets/SnippetsListView.swift` | Replaces carousel content when `.snippets` active. |
| `MacAllYouNeed/ClipboardDock/Views/Snippets/SnippetCard.swift` | One snippet (name + body preview + trigger chip). |
| `MacAllYouNeed/ClipboardDock/Views/Snippets/SnippetSheet.swift` | New / Edit sheet. |
| `MacAllYouNeedTests/ClipboardDock/SnippetsModelTests.swift` | Loading + create + delete + paste route. |

### Modified

| Path | Change |
|---|---|
| `MacAllYouNeed/App/AppDependencies.swift` | Construct `SnippetStore` and pass into model. |
| `MacAllYouNeed/ClipboardDock/Model/ClipboardDockModel.swift` | `snippets`, `loadSnippets`, `pasteSnippet`, `createSnippet`, `updateSnippet`, `deleteSnippet`, `duplicateSnippet`. Refresh on `.snippets` calls `loadSnippets`. |
| `MacAllYouNeed/ClipboardDock/Views/DockRootView.swift` | Conditionally render `SnippetsListView` instead of `ClipCarousel` for `.snippets`. |

---

## Task 1: Construct `SnippetStore` in `AppDependencies` and pass to model

**Files:**
- Modify: `MacAllYouNeed/App/AppDependencies.swift`
- Modify: `MacAllYouNeed/ClipboardDock/Model/ClipboardDockModel.swift` (init signature)

- [ ] **Step 1: Update `AppDependencies`**

```swift
        let snippetDB = try? Database(
            url: AppGroup.containerURL().appendingPathComponent("databases/snippets.sqlite"),
            migrations: SnippetStore.migrations
        )
        let snippets: SnippetStore = {
            if let key, let snippetDB { return SnippetStore(database: snippetDB, deviceKey: key) }
            // Fallback in-memory (only on key load failure)
            let tmp = try! Database(
                url: FileManager.default.temporaryDirectory.appendingPathComponent("snip-\(UUID()).sqlite"),
                migrations: SnippetStore.migrations
            )
            return SnippetStore(database: tmp, deviceKey: SymmetricKey(size: .bits256))
        }()
        snippetStore = snippets
```

Add stored property:

```swift
    let snippetStore: SnippetStore
```

Pass into model construction:

```swift
        dockModel = ClipboardDockModel(
            xpc: client, appIcons: appIcons,
            imageLoader: imgLoader, fileLoader: urlLoader,
            pinboards: pinboards, snippets: snippets
        )
```

- [ ] **Step 2: Update model init**

```swift
@MainActor
@Observable
final class ClipboardDockModel {
    let xpc: any ClipboardXPCInteracting
    let appIcons: AppIconResolver
    let imageLoader: ImageBlobLoader
    let fileLoader: FileURLLoader
    let pinboards: PinboardStore
    let snippets: SnippetStore

    var snippetItems: [Snippet] = []   // surfaced when activeList == .snippets

    init(
        xpc: any ClipboardXPCInteracting,
        appIcons: AppIconResolver,
        imageLoader: ImageBlobLoader,
        fileLoader: FileURLLoader,
        pinboards: PinboardStore,
        snippets: SnippetStore
    ) {
        self.xpc = xpc
        self.appIcons = appIcons
        self.imageLoader = imageLoader
        self.fileLoader = fileLoader
        self.pinboards = pinboards
        self.snippets = snippets
    }
```

Update test mocks (Phase B/C/D `MockClient` test files: `ClipboardDockModelTests`, `ClipboardDockModelListSwitchingTests`, `SelectionStateTests`) to construct a real `SnippetStore` (in-memory) and pass it.

- [ ] **Step 3: Build + run + commit**

```bash
xcodegen generate
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build 2>&1 | tail -10
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeedTests test 2>&1 | tail -10
git add MacAllYouNeed/App/AppDependencies.swift \
        MacAllYouNeed/ClipboardDock/Model/ClipboardDockModel.swift \
        MacAllYouNeedTests/ClipboardDock/ \
        MacAllYouNeed.xcodeproj
git commit -m "feat(dock): wire SnippetStore into AppDependencies + model"
```

---

## Task 2: `loadSnippets`, `pasteSnippet`, snippet CRUD on the model

**Files:**
- Modify: `MacAllYouNeed/ClipboardDock/Model/ClipboardDockModel.swift`
- Test: `MacAllYouNeedTests/ClipboardDock/SnippetsModelTests.swift`

- [ ] **Step 1: Failing tests**

```swift
@testable import MacAllYouNeed
import Core
import CryptoKit
import XCTest

@MainActor
final class SnippetsModelTests: XCTestCase {
    final class MockClient: ClipboardXPCInteracting {
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
            pasteTextArgs = (text, plainText, saveAsNew); return "injected"
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
        let sdb = try Database(url: dir.appendingPathComponent("s.sqlite"),
                               migrations: SnippetStore.migrations)
        snippets = SnippetStore(database: sdb, deviceKey: key)
        let pdb = try Database(url: dir.appendingPathComponent("p.sqlite"),
                               migrations: PinboardStore.migrations)
        pinboards = PinboardStore(database: pdb, deviceKey: key)
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
        let s = try snippets.create(name: "tmp", body: "x")
        await model.loadSnippets()
        await model.deleteSnippet(id: s.id)
        XCTAssertTrue(model.snippetItems.isEmpty)
    }

    func testDuplicateSnippetCreatesCopyWithNewID() async throws {
        let s = try snippets.create(name: "orig", body: "b")
        await model.loadSnippets()
        await model.duplicateSnippet(id: s.id)
        XCTAssertEqual(model.snippetItems.count, 2)
        XCTAssertEqual(Set(model.snippetItems.map(\.name)), ["orig", "orig (copy)"])
    }

    func testPasteSnippetRoutesPasteText() async throws {
        let s = try snippets.create(name: "sig", body: "Best,\nM")
        await model.loadSnippets()
        await model.pasteSnippet(id: s.id, plainText: true)
        XCTAssertEqual(mock.pasteTextArgs?.text, "Best,\nM")
        XCTAssertTrue(mock.pasteTextArgs?.plain == true)
        XCTAssertTrue(mock.pasteTextArgs?.save == true)
    }
}
```

- [ ] **Step 2: Verify failure**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeedTests test -only-testing:MacAllYouNeedTests/SnippetsModelTests 2>&1 | tail -10
```

- [ ] **Step 3: Implement on the model**

```swift
    func loadSnippets() async {
        snippetItems = (try? snippets.list()) ?? []
    }

    func createSnippet(name: String, body: String, trigger: String?) async {
        _ = try? snippets.create(name: name, body: body, trigger: trigger)
        await loadSnippets()
    }

    func updateSnippet(id: RecordID, name: String, body: String, trigger: String?) async {
        try? snippets.update(id: id, name: name, body: body, trigger: trigger)
        await loadSnippets()
    }

    func deleteSnippet(id: RecordID) async {
        try? snippets.delete(id: id)
        await loadSnippets()
    }

    func duplicateSnippet(id: RecordID) async {
        guard let original = snippetItems.first(where: { $0.id == id }) else { return }
        _ = try? snippets.create(
            name: "\(original.name) (copy)",
            body: original.body,
            trigger: nil   // Triggers are unique per snippet; copy starts without one.
        )
        await loadSnippets()
    }

    func pasteSnippet(id: RecordID, plainText: Bool) async {
        guard let snippet = snippetItems.first(where: { $0.id == id }) else { return }
        _ = await xpc.pasteText(text: snippet.body, plainText: plainText, saveAsNew: true)
    }
```

In `refresh()`, replace the `.snippets` branch:

```swift
        case .snippets:
            await loadSnippets()
            items = []
            focusedIndex = 0
```

- [ ] **Step 4: Run + commit**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeedTests test -only-testing:MacAllYouNeedTests/SnippetsModelTests 2>&1 | tail -10
git add MacAllYouNeed/ClipboardDock/Model/ClipboardDockModel.swift \
        MacAllYouNeedTests/ClipboardDock/SnippetsModelTests.swift
git commit -m "feat(dock): snippet load/create/update/delete/duplicate/paste"
```

---

## Task 3: `SnippetCard` view

**Files:**
- Create: `MacAllYouNeed/ClipboardDock/Views/Snippets/SnippetCard.swift`

- [ ] **Step 1: Implement**

```bash
mkdir -p MacAllYouNeed/ClipboardDock/Views/Snippets
```

```swift
import Core
import SwiftUI

struct SnippetCard: View {
    let snippet: Snippet
    let isFocused: Bool
    let onPaste: (Bool) -> Void
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    private var cardBackground: Color { Color(NSColor.controlBackgroundColor) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(snippet.name).font(.callout).bold().lineLimit(1)
                Spacer()
                if let trigger = snippet.trigger {
                    Text(trigger)
                        .font(.caption2.monospaced())
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            Text(snippet.body)
                .font(.system(.callout, design: .monospaced))
                .lineLimit(6)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(width: 220, height: 240, alignment: .topLeading)
        .padding(10)
        .background(cardBackground)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isFocused ? Color.accentColor : .clear, lineWidth: 2)
        )
        .onTapGesture {
            let plain = NSEvent.modifierFlags.contains(.option)
            onPaste(plain)
        }
        .contextMenu {
            Button("Edit…", action: onEdit)
            Button("Duplicate", action: onDuplicate)
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        }
    }
}
```

- [ ] **Step 2: Build + commit**

```bash
xcodegen generate
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build 2>&1 | tail -5
git add MacAllYouNeed/ClipboardDock/Views/Snippets/SnippetCard.swift MacAllYouNeed.xcodeproj
git commit -m "feat(dock): add SnippetCard view"
```

---

## Task 4: `SnippetSheet` (new + edit)

**Files:**
- Create: `MacAllYouNeed/ClipboardDock/Views/Snippets/SnippetSheet.swift`

- [ ] **Step 1: Implement**

```swift
import Core
import SwiftUI

struct SnippetSheet: View {
    let editing: Snippet?
    let onSave: (String, String, String?) -> Void
    @Binding var isPresented: Bool

    @State private var name: String
    @State private var body: String
    @State private var trigger: String

    init(editing: Snippet?, isPresented: Binding<Bool>, onSave: @escaping (String, String, String?) -> Void) {
        self.editing = editing
        self.onSave = onSave
        self._isPresented = isPresented
        _name = State(initialValue: editing?.name ?? "")
        _body = State(initialValue: editing?.body ?? "")
        _trigger = State(initialValue: editing?.trigger ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(editing == nil ? "New Snippet" : "Edit Snippet").font(.headline)
            TextField("Name", text: $name).textFieldStyle(.roundedBorder)
            TextEditor(text: $body)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 160)
                .border(Color.secondary.opacity(0.3))
            TextField("Trigger (optional, e.g. ;sig)", text: $trigger)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Cancel") { isPresented = false }
                Spacer()
                Button("Save") {
                    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedTrig = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmedName.isEmpty, !body.isEmpty else { return }
                    onSave(trimmedName, body, trimmedTrig.isEmpty ? nil : trimmedTrig)
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
```

- [ ] **Step 2: Build + commit**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build 2>&1 | tail -5
git add MacAllYouNeed/ClipboardDock/Views/Snippets/SnippetSheet.swift
git commit -m "feat(dock): add SnippetSheet for new + edit"
```

---

## Task 5: `SnippetsListView`

**Files:**
- Create: `MacAllYouNeed/ClipboardDock/Views/Snippets/SnippetsListView.swift`

- [ ] **Step 1: Implement**

```swift
import Core
import SwiftUI

struct SnippetsListView: View {
    @Bindable var model: ClipboardDockModel
    @State private var sheet: SheetMode? = nil

    enum SheetMode: Identifiable {
        case new
        case edit(Snippet)
        var id: String {
            switch self {
            case .new: return "new"
            case let .edit(s): return s.id.rawValue
            }
        }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                Button { sheet = .new } label: {
                    VStack {
                        Image(systemName: "plus.circle.fill").font(.title)
                        Text("New Snippet").font(.callout)
                    }
                    .foregroundStyle(.secondary)
                    .frame(width: 220, height: 240)
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
                ForEach(Array(model.snippetItems.enumerated()), id: \.element.id) { idx, snip in
                    SnippetCard(
                        snippet: snip,
                        isFocused: idx == model.focusedIndex,
                        onPaste: { plain in
                            Task {
                                await model.pasteSnippet(id: snip.id, plainText: plain)
                            }
                        },
                        onEdit: { sheet = .edit(snip) },
                        onDuplicate: { Task { await model.duplicateSnippet(id: snip.id) } },
                        onDelete: { Task { await model.deleteSnippet(id: snip.id) } }
                    )
                }
            }
            .padding(.horizontal, 16)
        }
        .task { await model.loadSnippets() }
        .sheet(item: $sheet) { mode in
            switch mode {
            case .new:
                SnippetSheet(editing: nil, isPresented: Binding(
                    get: { sheet != nil }, set: { if !$0 { sheet = nil } }
                )) { name, body, trigger in
                    Task { await model.createSnippet(name: name, body: body, trigger: trigger) }
                }
            case let .edit(snippet):
                SnippetSheet(editing: snippet, isPresented: Binding(
                    get: { sheet != nil }, set: { if !$0 { sheet = nil } }
                )) { name, body, trigger in
                    Task { await model.updateSnippet(id: snippet.id, name: name, body: body, trigger: trigger) }
                }
            }
        }
    }
}
```

- [ ] **Step 2: Build + commit**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build 2>&1 | tail -5
git add MacAllYouNeed/ClipboardDock/Views/Snippets/SnippetsListView.swift
git commit -m "feat(dock): add SnippetsListView with new + edit + duplicate + delete"
```

---

## Task 6: Conditionally render `SnippetsListView` in `DockRootView`

**Files:**
- Modify: `MacAllYouNeed/ClipboardDock/Views/DockRootView.swift`

- [ ] **Step 1: Branch on `model.activeList`**

Replace the `ClipCarousel(...)` block with:

```swift
            Group {
                if model.activeList == .snippets {
                    SnippetsListView(model: model)
                } else {
                    ClipCarousel(
                        model: model, favicons: favicons, registry: registry,
                        onPaste: onPaste
                    )
                }
            }
            .frame(maxHeight: .infinity)
```

- [ ] **Step 2: Build + commit**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build 2>&1 | tail -5
git add MacAllYouNeed/ClipboardDock/Views/DockRootView.swift
git commit -m "feat(dock): swap to SnippetsListView when activeList == .snippets"
```

---

## Task 7: Phase F smoke + regression

- [ ] **Step 1: Run all tests**

```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeedTests test 2>&1 | tail -20
```

Expected: every test green across all phases.

- [ ] **Step 2: Manual smoke**

1. ⌘⇧V opens dock; click `Snippets` tab.
2. Click `+ New Snippet` → sheet appears.
3. Enter name "sig", body "Best,\nMingjie", trigger ";sig" → Save.
4. New snippet card appears in carousel position 1 (right of `+`).
5. Click card → "Best,\nMingjie" pastes into focused app; new entry visible in History tab with com.macallyouneed.app source.
6. Right-click snippet → Edit → change body → Save → updated.
7. Right-click → Duplicate → "(copy)" appears with same body, no trigger.
8. Right-click → Delete → snippet vanishes.
9. Type `;sig<space>` in any app → existing `SnippetExpander` (independent of dock) expands to body.

---

## Phase F — Done

End-state of Phase F:

- Snippets tab fully functional: list, create, edit, duplicate, delete, paste.
- Pasting routes through Phase A's `pasteText` so it appears in History with the app's bundle ID as source.
- Existing trigger-based `SnippetExpander` unaffected.

---

## All Phases — Done

Every spec section is now implemented. Final regression sweep:

```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeedTests test 2>&1 | tail -20
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build 2>&1 | tail -5
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme ClipboardDaemon -configuration Debug build 2>&1 | tail -5
```

All 16 manual smoke checks from spec §12.6 should pass:

1. ⌘⇧V opens dock with slide-up; ⌘⇧V dismisses. ✓ Phase B
2. Multi-monitor: dock follows cursor screen. ✓ Phase B
3. Reduced-motion: no slide. ✓ Phase B
4. Source-app icon top-right with gradient. ✓ Phase B
5. Image card thumbnail < 200ms. ✓ Phase B
6. File card with Finder icon. ✓ Phase B
7. Search filters live. ✓ Phase B
8. Pinboard create + drag + switch. ✓ Phase C
9. Multi-select 3 + Paste joined. ✓ Phase D
10. Quick Look with arrow cycling. ✓ Phase D
11. Transform → Pretty JSON → new clip. ✓ Phase D
12. Drag card into TextEdit. ✓ Phase D
13. Privacy ignore Chrome. ✓ Phase E
14. Settings rebind Pin to ⌘B. ✓ Phase C
15. Keychain copy → no card. ✓ Phase E
16. Storage cap → oldest non-pinned vanish. ✓ Phase E

Spec is complete.
