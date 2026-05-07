# Clipboard Dock — Phase D: Power Features — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add multi-select with merge/stack paste, in-dock Quick Look overlay, Transformations menu, drag-out, ColorCard color picker, and the keyboard cheatsheet. After Phase D, every interaction in spec §10 works end-to-end. Adds a small XPC addition (`deleteItem`) discovered to be necessary by Phase D's multi-select Delete action.

**Architecture:** Extends `ClipboardDockModel` with `selection`, `isQuickLooking`, `pendingTransform` state. New views land under `MacAllYouNeed/ClipboardDock/Views/MultiSelect/` and `Views/QuickLook/`. Per-card `.draggable(...)` modifiers on each existing card view. ColorCard gains an `NSColorPanel` integration. A new lightweight `CheatsheetOverlay` reads bindings live from `ShortcutRegistry`.

**Tech Stack:** SwiftUI `Transferable`, `NSColorPanel`, `NSDraggingSession`, AppKit text view in Quick Look, existing XPC infra.

**Spec:** `docs/superpowers/specs/2026-05-07-clipboard-dock-redesign-design.md` §10.

**Depends on:** Phases A, B, C merged. Uses Phase A's `pasteMany`, `transformAndCopy`, `imageThumbnail`. Uses Phase B's per-kind cards. Uses Phase C's `ShortcutRegistry`.

**Working directory:** `/Users/mingjie.wang/Documents/personal/mac-all-you-need`

---

## File Structure

### Created

| Path | Responsibility |
|---|---|
| `MacAllYouNeed/ClipboardDock/Views/MultiSelect/MultiSelectBar.swift` | Bottom bar shown when `selection` non-empty. |
| `MacAllYouNeed/ClipboardDock/Views/MultiSelect/TransformMenu.swift` | Menu of Phase A `TextTransform` cases. |
| `MacAllYouNeed/ClipboardDock/Views/QuickLook/QuickLookOverlay.swift` | Translucent overlay covering carousel area. |
| `MacAllYouNeed/ClipboardDock/Views/QuickLook/QuickLookContent.swift` | Per-kind dispatcher (Text/Image/File/Link/Color). |
| `MacAllYouNeed/ClipboardDock/Views/Cheatsheet/CheatsheetOverlay.swift` | Lists active shortcuts from `ShortcutRegistry`. |
| `MacAllYouNeed/ClipboardDock/Services/ColorPickerCoordinator.swift` | NSColorPanel integration with new-clip writeback. |
| `MacAllYouNeedTests/ClipboardDock/SelectionStateTests.swift` | Multi-select extension/clearing semantics. |

### Modified

| Path | Change |
|---|---|
| `Shared/Sources/Core/XPC/ClipboardXPCProtocol.swift` | Add `deleteItem(id:reply:)`. |
| `Shared/Sources/Platform/XPC/ClipboardXPCService.swift` | Implement `deleteItem`. |
| `ClipboardDaemon/ClipboardXPCServer.swift` | Forwarding stub. |
| `Shared/Sources/Core/XPC/ClipboardXPCInteracting.swift` | Add async `deleteItem`. |
| `Shared/Sources/Core/XPC/ClipboardXPCClient.swift` | Conform new method. |
| `MacAllYouNeed/ClipboardDock/Model/ClipboardDockModel.swift` | `selection`, `isQuickLooking`, `pendingTransform`; methods for multi-select / paste in order / delete / transform. |
| `MacAllYouNeed/ClipboardDock/Views/Carousel/CardSlot.swift` | Multi-select checkmark badge. |
| `MacAllYouNeed/ClipboardDock/Views/Cards/TextCard.swift` | `.draggable` String. |
| `MacAllYouNeed/ClipboardDock/Views/Cards/ImageCard.swift` | `.draggable` NSImage. |
| `MacAllYouNeed/ClipboardDock/Views/Cards/FileCard.swift` | `.draggable` `[URL]`. |
| `MacAllYouNeed/ClipboardDock/Views/Cards/LinkCard.swift` | `.draggable` URL. |
| `MacAllYouNeed/ClipboardDock/Views/Cards/ColorCard.swift` | `.draggable` String + "C" key cycle + Open Color Picker context menu. |
| `MacAllYouNeed/ClipboardDock/Views/DockRootView.swift` | Compose MultiSelectBar + QuickLookOverlay + CheatsheetOverlay. |
| `MacAllYouNeed/ClipboardDock/Window/DockWindowController.swift` | Drag-aware auto-dismiss; key monitor extends to QuickLook + cheatsheet + selection extension shortcuts. |

---

## Task 1: `deleteItem` XPC RPC

**Files:**
- Modify: `Shared/Sources/Core/XPC/ClipboardXPCProtocol.swift`
- Modify: `Shared/Sources/Platform/XPC/ClipboardXPCService.swift`
- Modify: `ClipboardDaemon/ClipboardXPCServer.swift`
- Modify: `Shared/Sources/Core/XPC/ClipboardXPCInteracting.swift`
- Modify: `Shared/Sources/Core/XPC/ClipboardXPCClient.swift`
- Test: `Shared/Tests/PlatformTests/XPC/ClipboardXPCServiceTests.swift`

- [ ] **Step 1: Append failing test to existing `ClipboardXPCServiceTests`**

```swift
    func testDeleteItemRemovesRecord() throws {
        let item = try clip.append(.text("doomed"))
        let exp = expectation(description: "delete")
        service.deleteItem(id: item.id.rawValue) { ok in
            XCTAssertTrue(ok)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
        XCTAssertEqual(try clip.list(limit: 10).count, 0)
    }

    func testDeleteItemReturnsFalseForUnknownID() {
        let exp = expectation(description: "delete")
        service.deleteItem(id: "01HFAKEFAKEFAKEFAKEFAKEFAK") { ok in
            XCTAssertFalse(ok)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
    }
```

- [ ] **Step 2: Verify failure**

```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter ClipboardXPCServiceTests/testDeleteItemRemovesRecord
```

Expected: FAIL.

- [ ] **Step 3: Add to protocol**

In `ClipboardXPCProtocol.swift`:

```swift
    func deleteItem(id: String, reply: @escaping (Bool) -> Void)
```

- [ ] **Step 4: Implement in service**

In `ClipboardXPCService.swift`:

```swift
    public func deleteItem(id: String, reply: @escaping (Bool) -> Void) {
        guard let rid = RecordID(rawValue: id) else { reply(false); return }
        do {
            // Verify record exists before deleting; ClipboardStore.delete is idempotent.
            _ = try clip.body(for: rid)
            try clip.delete(id: rid)
            reply(true)
        } catch {
            reply(false)
        }
    }
```

- [ ] **Step 5: Forward in server**

In `ClipboardXPCServer.swift`:

```swift
    func deleteItem(id: String, reply: @escaping (Bool) -> Void) {
        service.deleteItem(id: id, reply: reply)
    }
```

- [ ] **Step 6: Add async wrapper in `ClipboardXPCInteracting`**

```swift
    func deleteItem(id: String) async -> Bool
```

In `ClipboardXPCClient.swift` extension:

```swift
    public func deleteItem(id: String) async -> Bool {
        await withCheckedContinuation { cont in
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in
                cont.resume(returning: false)
            }) as? ClipboardXPCProtocol else { cont.resume(returning: false); return }
            proxy.deleteItem(id: id) { cont.resume(returning: $0) }
        }
    }
```

Update Phase B and C `MockClient` test classes to add `func deleteItem(id: String) async -> Bool { false }`.

- [ ] **Step 7: Run tests + commit**

```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeedTests test 2>&1 | tail -10
git add Shared/Sources/Core/XPC/ClipboardXPCProtocol.swift \
        Shared/Sources/Core/XPC/ClipboardXPCInteracting.swift \
        Shared/Sources/Core/XPC/ClipboardXPCClient.swift \
        Shared/Sources/Platform/XPC/ClipboardXPCService.swift \
        ClipboardDaemon/ClipboardXPCServer.swift \
        Shared/Tests/PlatformTests/XPC/ClipboardXPCServiceTests.swift \
        MacAllYouNeedTests/ClipboardDock/
git commit -m "$(cat <<'EOF'
feat(xpc): add deleteItem RPC

Discovered necessary by Phase D's multi-select Delete action.
Wire-additive; idempotent on missing records (returns false).

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: `ClipboardDockModel` selection state

**Files:**
- Modify: `MacAllYouNeed/ClipboardDock/Model/ClipboardDockModel.swift`
- Test: `MacAllYouNeedTests/ClipboardDock/SelectionStateTests.swift`

- [ ] **Step 1: Failing tests**

```swift
@testable import MacAllYouNeed
import Core
import CryptoKit
import XCTest

@MainActor
final class SelectionStateTests: XCTestCase {
    final class MockClient: ClipboardXPCInteracting {
        var pasteManyArgs: (ids: [String], delim: String, plain: Bool)?
        var deletes: [String] = []
        var transformCalls: [(String, String)] = []
        var listResults: [ClipboardXPCMeta] = []
        func listItems(query: String?, pageToken: String?, limit: Int) async -> ClipboardXPCList {
            ClipboardXPCList(items: listResults, nextPageToken: nil)
        }
        func bodyText(forID id: String) async -> String? { nil }
        func paste(itemID: String, plainText: Bool) async -> String { "injected" }
        func pasteMany(itemIDs: [String], delimiter: String, plainText: Bool) async -> String {
            pasteManyArgs = (itemIDs, delimiter, plainText); return "injected"
        }
        func pasteText(text: String, plainText: Bool, saveAsNew: Bool) async -> String { "injected" }
        func transformAndCopy(itemID: String, transform: String, saveAsNew: Bool) async -> String? {
            transformCalls.append((itemID, transform)); return nil
        }
        func imageThumbnail(forID id: String, maxDim: Int) async -> Data? { nil }
        func listSnippets() async -> [SnippetXPCDTO] { [] }
        func deleteItem(id: String) async -> Bool { deletes.append(id); return true }
    }

    private var dir: URL!
    private var pinboards: PinboardStore!
    private var mock: MockClient!
    private var model: ClipboardDockModel!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Sel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let key = SymmetricKey(size: .bits256)
        let db = try Database(url: dir.appendingPathComponent("p.sqlite"),
                              migrations: PinboardStore.migrations)
        pinboards = PinboardStore(database: db, deviceKey: key)
        mock = MockClient()
        mock.listResults = (0..<5).map {
            ClipboardXPCMeta(id: "i\($0)", modified: Date(), kind: "clipboardItem", preview: "v\($0)")
        }
        model = ClipboardDockModel(
            xpc: mock,
            appIcons: AppIconResolver(),
            imageLoader: ImageBlobLoader(xpc: mock),
            pinboards: pinboards
        )
        await model.refresh()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testToggleSelectionAdds() {
        model.toggleSelection(itemID: "i0")
        XCTAssertEqual(model.selection, ["i0"])
    }

    func testToggleSelectionRemovesIfPresent() {
        model.toggleSelection(itemID: "i0")
        model.toggleSelection(itemID: "i0")
        XCTAssertTrue(model.selection.isEmpty)
    }

    func testExtendSelectionRightAddsContiguousFromFocus() {
        model.focusedIndex = 1
        model.extendSelectionRight()
        XCTAssertEqual(model.selection, ["i1", "i2"])
    }

    func testExtendSelectionLeftAddsContiguousFromFocus() {
        model.focusedIndex = 3
        model.extendSelectionLeft()
        XCTAssertEqual(model.selection, ["i3", "i2"])
    }

    func testClearSelection() {
        model.toggleSelection(itemID: "i0")
        model.toggleSelection(itemID: "i1")
        model.clearSelection()
        XCTAssertTrue(model.selection.isEmpty)
    }

    func testSelectAllCapsAt50() {
        mock.listResults = (0..<60).map {
            ClipboardXPCMeta(id: "i\($0)", modified: Date(), kind: "clipboardItem", preview: "v")
        }
        Task { await model.refresh() }
        // Synchronous wait for the refresh
        let waitExp = expectation(description: "refresh")
        Task {
            await model.refresh()
            model.selectAllVisible()
            waitExp.fulfill()
        }
        wait(for: [waitExp], timeout: 2)
        XCTAssertLessThanOrEqual(model.selection.count, 50)
    }

    func testRefreshClearsSelection() async {
        model.toggleSelection(itemID: "i0")
        await model.refresh()
        XCTAssertTrue(model.selection.isEmpty)
    }
}
```

- [ ] **Step 2: Verify it fails**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeedTests test -only-testing:MacAllYouNeedTests/SelectionStateTests 2>&1 | tail -10
```

Expected: FAIL.

- [ ] **Step 3: Extend `ClipboardDockModel`**

Add to `ClipboardDockModel`:

```swift
    var selection: Set<DockItem.ID> = []
    var isQuickLooking: Bool = false
    var pendingTransform: TextTransform? = nil   // import from Platform

    func toggleSelection(itemID: String) {
        if selection.contains(itemID) { selection.remove(itemID) }
        else { selection.insert(itemID) }
    }

    func extendSelectionRight() {
        guard items.indices.contains(focusedIndex) else { return }
        selection.insert(items[focusedIndex].id)
        let nextIdx = focusedIndex + 1
        if items.indices.contains(nextIdx) {
            selection.insert(items[nextIdx].id)
            focusedIndex = nextIdx
        }
    }

    func extendSelectionLeft() {
        guard items.indices.contains(focusedIndex) else { return }
        selection.insert(items[focusedIndex].id)
        let prevIdx = focusedIndex - 1
        if items.indices.contains(prevIdx) {
            selection.insert(items[prevIdx].id)
            focusedIndex = prevIdx
        }
    }

    func clearSelection() { selection.removeAll() }

    func selectAllVisible() {
        let cap = 50
        selection = Set(items.prefix(cap).map(\.id))
    }
```

In `refresh()` (every branch's tail), after `focusedIndex = 0` add `selection.removeAll()`.

Add `import Platform` if not already present (for `TextTransform`).

- [ ] **Step 4: Run tests + commit**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeedTests test -only-testing:MacAllYouNeedTests/SelectionStateTests 2>&1 | tail -10
git add MacAllYouNeed/ClipboardDock/Model/ClipboardDockModel.swift \
        MacAllYouNeedTests/ClipboardDock/SelectionStateTests.swift
git commit -m "feat(dock): add selection state + extension shortcuts"
```

---

## Task 3: `ClipboardDockModel.pasteSelectionInOrder` + `deleteSelected`

**Files:**
- Modify: `MacAllYouNeed/ClipboardDock/Model/ClipboardDockModel.swift`
- Modify: `MacAllYouNeedTests/ClipboardDock/SelectionStateTests.swift`

- [ ] **Step 1: Append failing tests**

```swift
    func testPasteSelectionInOrderRoutesPasteMany() async {
        model.toggleSelection(itemID: "i2")
        model.toggleSelection(itemID: "i0")
        model.toggleSelection(itemID: "i1")
        await model.pasteSelectionInOrder(delimiter: "\n", plainText: true)
        XCTAssertEqual(mock.pasteManyArgs?.delim, "\n")
        XCTAssertTrue(mock.pasteManyArgs?.plain == true)
        // Order is the visible order of the carousel (items[0..]).
        XCTAssertEqual(mock.pasteManyArgs?.ids, ["i0", "i1", "i2"])
    }

    func testDeleteSelectedDeletesEachItem() async {
        model.toggleSelection(itemID: "i0")
        model.toggleSelection(itemID: "i1")
        await model.deleteSelected()
        XCTAssertEqual(Set(mock.deletes), ["i0", "i1"])
        XCTAssertTrue(model.selection.isEmpty)
    }
```

- [ ] **Step 2: Implement**

```swift
    func pasteSelectionInOrder(delimiter: String, plainText: Bool) async {
        let orderedIDs = items.map(\.id).filter { selection.contains($0) }
        guard !orderedIDs.isEmpty else { return }
        _ = await xpc.pasteMany(itemIDs: orderedIDs, delimiter: delimiter, plainText: plainText)
    }

    func deleteSelected() async {
        for id in selection {
            _ = await xpc.deleteItem(id: id)
        }
        clearSelection()
        await refresh()
    }
```

- [ ] **Step 3: Run + commit**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeedTests test -only-testing:MacAllYouNeedTests/SelectionStateTests 2>&1 | tail -10
git add MacAllYouNeed/ClipboardDock/Model/ClipboardDockModel.swift \
        MacAllYouNeedTests/ClipboardDock/SelectionStateTests.swift
git commit -m "feat(dock): add pasteSelectionInOrder + deleteSelected"
```

---

## Task 4: `ClipboardDockModel.applyTransform`

**Files:**
- Modify: `MacAllYouNeed/ClipboardDock/Model/ClipboardDockModel.swift`
- Modify: `MacAllYouNeedTests/ClipboardDock/SelectionStateTests.swift`

- [ ] **Step 1: Append test**

```swift
    func testApplyTransformRoutesEachSelectedItem() async {
        model.toggleSelection(itemID: "i0")
        model.toggleSelection(itemID: "i2")
        await model.applyTransform(.uppercase, saveAsNew: true)
        XCTAssertEqual(Set(mock.transformCalls.map(\.0)), ["i0", "i2"])
        XCTAssertTrue(mock.transformCalls.allSatisfy { $0.1 == "uppercase" })
    }

    func testApplyTransformOnlyToFocusedWhenNoSelection() async {
        model.focusedIndex = 1
        await model.applyTransform(.lowercase, saveAsNew: false)
        XCTAssertEqual(mock.transformCalls.first?.0, "i1")
    }
```

- [ ] **Step 2: Implement**

```swift
import Platform   // for TextTransform

    func applyTransform(_ transform: TextTransform, saveAsNew: Bool) async {
        let targets: [String]
        if !selection.isEmpty {
            targets = items.map(\.id).filter { selection.contains($0) }
        } else if items.indices.contains(focusedIndex) {
            targets = [items[focusedIndex].id]
        } else { return }
        for id in targets {
            _ = await xpc.transformAndCopy(
                itemID: id, transform: transform.rawValue, saveAsNew: saveAsNew
            )
        }
        await refresh()
    }
```

- [ ] **Step 3: Run + commit**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeedTests test -only-testing:MacAllYouNeedTests/SelectionStateTests 2>&1 | tail -10
git add MacAllYouNeed/ClipboardDock/Model/ClipboardDockModel.swift \
        MacAllYouNeedTests/ClipboardDock/SelectionStateTests.swift
git commit -m "feat(dock): add applyTransform routing through transformAndCopy XPC"
```

---

## Task 5: `MultiSelectBar` view

**Files:**
- Create: `MacAllYouNeed/ClipboardDock/Views/MultiSelect/MultiSelectBar.swift`

- [ ] **Step 1: Implement**

```bash
mkdir -p MacAllYouNeed/ClipboardDock/Views/MultiSelect
```

```swift
import SwiftUI
import Platform

struct MultiSelectBar: View {
    @Bindable var model: ClipboardDockModel
    let onPin: () -> Void
    let onAddToList: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("\(model.selection.count) selected").font(.callout)
            Spacer()
            Button("Paste") {
                Task { await model.pasteSelectionInOrder(delimiter: "\n", plainText: false) }
            }
            Button("Paste plain") {
                Task { await model.pasteSelectionInOrder(delimiter: "\n", plainText: true) }
            }
            Button("Pin", action: onPin)
            Button("Add to list…", action: onAddToList)
            Menu("Transform") {
                ForEach(TextTransform.allCases, id: \.self) { kind in
                    Button(label(for: kind)) {
                        Task { await model.applyTransform(kind, saveAsNew: true) }
                    }
                }
            }
            Button("Delete", role: .destructive) {
                Task { await model.deleteSelected() }
            }
            Button {
                model.clearSelection()
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(.ultraThinMaterial)
    }

    private func label(for kind: TextTransform) -> String {
        switch kind {
        case .lowercase:    return "Lowercase"
        case .uppercase:    return "Uppercase"
        case .titleCase:    return "Title Case"
        case .trim:         return "Trim"
        case .stripHTML:    return "Strip HTML"
        case .prettyJSON:   return "Pretty JSON"
        case .minifyJSON:   return "Minify JSON"
        case .base64Encode: return "Base64 Encode"
        case .base64Decode: return "Base64 Decode"
        case .urlEncode:    return "URL Encode"
        case .urlDecode:    return "URL Decode"
        case .sortLines:    return "Sort Lines"
        case .dedupeLines:  return "Dedupe Lines"
        }
    }
}
```

- [ ] **Step 2: Build + commit**

```bash
xcodegen generate
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build 2>&1 | tail -5
git add MacAllYouNeed/ClipboardDock/Views/MultiSelect/MultiSelectBar.swift MacAllYouNeed.xcodeproj
git commit -m "feat(dock): add MultiSelectBar view"
```

---

## Task 6: Wire MultiSelectBar into `DockRootView`

**Files:**
- Modify: `MacAllYouNeed/ClipboardDock/Views/DockRootView.swift`

- [ ] **Step 1: Add `MultiSelectBar` conditional render**

```swift
        VStack(spacing: 0) {
            DockTopBar(model: model, openSettings: openSettings)
            Divider()
            ClipCarousel(
                model: model, favicons: favicons, registry: registry,
                onPaste: onPaste
            )
            .frame(maxHeight: .infinity)
            if !model.selection.isEmpty {
                MultiSelectBar(
                    model: model,
                    onPin: {
                        Task {
                            for id in model.selection { await model.togglePin(itemID: id) }
                            model.clearSelection()
                        }
                    },
                    onAddToList: {
                        // Phase D minimal: pick the first available list silently.
                        // Full picker UI lands as a small follow-up if we discover need.
                        if let board = model.availableLists.first {
                            Task {
                                await model.addToPinboard(
                                    itemIDs: Array(model.selection), boardID: board.id
                                )
                                model.clearSelection()
                            }
                        }
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.18), value: model.selection.isEmpty)
```

The "Add to list" picker is intentionally minimal in Phase D — picks the first available list. A full popover picker is deferred unless smoke-testing reveals it's needed.

- [ ] **Step 2: Build + commit**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build 2>&1 | tail -5
git add MacAllYouNeed/ClipboardDock/Views/DockRootView.swift
git commit -m "feat(dock): show MultiSelectBar when selection non-empty"
```

---

## Task 7: Click-to-multi-select wiring

**Files:**
- Modify: `MacAllYouNeed/ClipboardDock/Views/Carousel/ClipCarousel.swift`
- Modify: `MacAllYouNeed/ClipboardDock/Views/Carousel/CardSlot.swift`

⌘+click toggles selection; ⇧+click extends. Plain click pastes (existing).

- [ ] **Step 1: Update tap handling in `ClipCarousel`**

Replace the `.onTapGesture { onPaste(idx, false) }` modifier with a `simultaneousGesture` that inspects modifiers:

```swift
                        .modifier(CardClickModifier(
                            index: idx, model: model,
                            onPaste: { onPaste(idx, false) }
                        ))
```

Define the modifier:

```swift
private struct CardClickModifier: ViewModifier {
    let index: Int
    @Bindable var model: ClipboardDockModel
    let onPaste: () -> Void

    func body(content: Content) -> some View {
        content.gesture(
            TapGesture().modifiers(.command).onEnded {
                guard model.items.indices.contains(index) else { return }
                model.toggleSelection(itemID: model.items[index].id)
            }
        )
        .gesture(
            TapGesture().modifiers(.shift).onEnded {
                guard model.items.indices.contains(index) else { return }
                model.focusedIndex = index
                model.extendSelectionRight()
                model.selection.insert(model.items[index].id)
            }
        )
        .onTapGesture {
            // Plain click: paste; Phase B behavior.
            if model.selection.isEmpty { onPaste() }
            else { model.toggleSelection(itemID: model.items[index].id) }
        }
    }
}
```

- [ ] **Step 2: Add multi-select checkmark to `CardSlot`**

```swift
            .overlay(alignment: .topLeading) {
                if model.selection.contains(item.id) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .background(Circle().fill(.background))
                        .padding(6)
                }
            }
```

Add `@Bindable var model: ClipboardDockModel` to `CardSlot`'s init so selection state is observable. Update `ClipCarousel` to pass `model` through.

- [ ] **Step 3: Build + commit**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build 2>&1 | tail -5
git add MacAllYouNeed/ClipboardDock/Views/Carousel/ClipCarousel.swift \
        MacAllYouNeed/ClipboardDock/Views/Carousel/CardSlot.swift
git commit -m "feat(dock): ⌘-click toggles selection; ⇧-click extends"
```

---

## Task 8: `QuickLookOverlay` shell + spacebar toggle

**Files:**
- Create: `MacAllYouNeed/ClipboardDock/Views/QuickLook/QuickLookOverlay.swift`
- Create: `MacAllYouNeed/ClipboardDock/Views/QuickLook/QuickLookContent.swift`
- Modify: `MacAllYouNeed/ClipboardDock/Views/DockRootView.swift`
- Modify: `MacAllYouNeed/ClipboardDock/Window/DockWindowController.swift`

- [ ] **Step 1: Implement overlay shell**

```bash
mkdir -p MacAllYouNeed/ClipboardDock/Views/QuickLook
```

```swift
import SwiftUI

struct QuickLookOverlay: View {
    @Bindable var model: ClipboardDockModel

    var body: some View {
        let item: DockItem? = model.items.indices.contains(model.focusedIndex)
            ? model.items[model.focusedIndex] : nil
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            if let item {
                VStack(spacing: 12) {
                    QuickLookContent(item: item, loader: model.imageLoader)
                        .frame(maxWidth: 800, maxHeight: 480)
                    HStack {
                        Text(item.preview).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        Text(item.modified, style: .relative).font(.caption2).foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 12)
                }
                .padding(20)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .transition(.opacity)
    }
}
```

- [ ] **Step 2: Wire into `DockRootView`**

```swift
        .overlay {
            if model.isQuickLooking {
                QuickLookOverlay(model: model)
                    .animation(.easeOut(duration: 0.15), value: model.isQuickLooking)
            }
        }
```

- [ ] **Step 3: Hook spacebar in `DockWindowController.startKeyMonitor`**

```swift
            if registry.matches(event: event, .quickLook) {
                Task { @MainActor in model.isQuickLooking.toggle() }
                return nil
            }
```

If `.dismiss` fires while `model.isQuickLooking`, dismiss only the overlay:

```swift
            if registry.matches(event: event, .dismiss) {
                if model.isQuickLooking {
                    Task { @MainActor in model.isQuickLooking = false }
                } else {
                    hide()
                }
                return nil
            }
```

(Update the existing `.dismiss` handler.)

- [ ] **Step 4: Build + commit**

```bash
xcodegen generate
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build 2>&1 | tail -5
git add MacAllYouNeed/ClipboardDock/Views/QuickLook/QuickLookOverlay.swift \
        MacAllYouNeed/ClipboardDock/Views/DockRootView.swift \
        MacAllYouNeed/ClipboardDock/Window/DockWindowController.swift \
        MacAllYouNeed.xcodeproj
git commit -m "feat(dock): add QuickLookOverlay with spacebar toggle"
```

---

## Task 9: `QuickLookContent` per-kind

**Files:**
- Create: `MacAllYouNeed/ClipboardDock/Views/QuickLook/QuickLookContent.swift`

- [ ] **Step 1: Implement**

```swift
import AppKit
import SwiftUI

struct QuickLookContent: View {
    let item: DockItem
    let loader: ImageBlobLoader

    var body: some View {
        Group {
            switch item.kind {
            case .text, .rtf, .code:
                ScrollView {
                    Text(item.preview)
                        .font(.system(.body, design: kindIsCode ? .monospaced : .default))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .textSelection(.enabled)
                }
            case .image:
                FullImageView(recordID: item.id, loader: loader)
            case .file:
                ScrollView {
                    Text(item.preview).padding(12).textSelection(.enabled)
                }
            case .link:
                if case let .link(url) = item.kind {
                    VStack(spacing: 8) {
                        Text(url.host ?? "").font(.headline).foregroundStyle(.secondary)
                        Link(url.absoluteString, destination: url).font(.body)
                    }
                    .padding(12)
                }
            case .color:
                if case .color = item.kind {
                    let nsColor = NSColor(named: NSColor.Name(item.preview)) ?? NSColor.gray
                    VStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(nsColor))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        Text(item.preview).font(.system(.title3, design: .monospaced))
                    }
                }
            }
        }
    }

    private var kindIsCode: Bool {
        if case .code = item.kind { return true } else { return false }
    }
}

private struct FullImageView: View {
    let recordID: String
    let loader: ImageBlobLoader
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                ProgressView()
            }
        }
        .task(id: recordID) {
            image = await loader.thumbnail(recordID: recordID, maxDim: 0)
        }
    }
}
```

`maxDim: 0` returns the original (Phase A `ThumbnailRenderer.render` passthrough behavior).

- [ ] **Step 2: Build + commit**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build 2>&1 | tail -5
git add MacAllYouNeed/ClipboardDock/Views/QuickLook/QuickLookContent.swift
git commit -m "feat(dock): add QuickLookContent per-kind dispatcher"
```

---

## Task 10: `TransformMenu` view + ⌘T binding

**Files:**
- Create: `MacAllYouNeed/ClipboardDock/Views/MultiSelect/TransformMenu.swift`
- Modify: `MacAllYouNeed/ClipboardDock/Window/DockWindowController.swift`

`MultiSelectBar` already has an inline Transform menu. `TransformMenu` is a popover triggered by ⌘T from the focused card (no selection required).

- [ ] **Step 1: Implement standalone popover**

```swift
import Platform
import SwiftUI

struct TransformMenu: View {
    @Bindable var model: ClipboardDockModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(TextTransform.allCases, id: \.self) { kind in
                Button(label(for: kind)) {
                    Task {
                        await model.applyTransform(kind, saveAsNew: true)
                        isPresented = false
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8).padding(.vertical, 4)
            }
        }
        .padding(8)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func label(for kind: TextTransform) -> String {
        // Reuse from MultiSelectBar; in production this lives in a shared helper.
        switch kind {
        case .lowercase: return "Lowercase"
        case .uppercase: return "Uppercase"
        case .titleCase: return "Title Case"
        case .trim: return "Trim"
        case .stripHTML: return "Strip HTML"
        case .prettyJSON: return "Pretty JSON"
        case .minifyJSON: return "Minify JSON"
        case .base64Encode: return "Base64 Encode"
        case .base64Decode: return "Base64 Decode"
        case .urlEncode: return "URL Encode"
        case .urlDecode: return "URL Decode"
        case .sortLines: return "Sort Lines"
        case .dedupeLines: return "Dedupe Lines"
        }
    }
}
```

Move the label helper into a shared `TextTransform+Label.swift` extension if duplication grates — but per CLAUDE.md "no abstractions for single-use code", leave it duplicated for now (the second call site, MultiSelectBar, is the same code).

- [ ] **Step 2: Add ⌘T handling in `DockWindowController.startKeyMonitor`**

```swift
            if registry.matches(event: event, .transformFocused) {
                Task { @MainActor in showTransformMenu = true }
                return nil
            }
```

This requires `showTransformMenu: Bool` to be observable from the SwiftUI view tree. Add to `ClipboardDockModel`:

```swift
    var showTransformMenu: Bool = false
```

`DockRootView` overlays the menu:

```swift
        .overlay(alignment: .center) {
            if model.showTransformMenu {
                TransformMenu(model: model, isPresented: $model.showTransformMenu)
            }
        }
```

- [ ] **Step 3: Build + commit**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build 2>&1 | tail -5
git add MacAllYouNeed/ClipboardDock/Views/MultiSelect/TransformMenu.swift \
        MacAllYouNeed/ClipboardDock/Model/ClipboardDockModel.swift \
        MacAllYouNeed/ClipboardDock/Views/DockRootView.swift \
        MacAllYouNeed/ClipboardDock/Window/DockWindowController.swift
git commit -m "feat(dock): add TransformMenu popover with ⌘T binding"
```

---

## Task 11: Selection extension shortcuts in key monitor

**Files:**
- Modify: `MacAllYouNeed/ClipboardDock/Window/DockWindowController.swift`

- [ ] **Step 1: Extend `startKeyMonitor`**

```swift
            if registry.matches(event: event, .extendSelectionRight) {
                Task { @MainActor in model.extendSelectionRight() }
                return nil
            }
            if registry.matches(event: event, .extendSelectionLeft) {
                Task { @MainActor in model.extendSelectionLeft() }
                return nil
            }
            if registry.matches(event: event, .deleteFocused) {
                Task { @MainActor in
                    if !model.selection.isEmpty {
                        await model.deleteSelected()
                    } else if model.items.indices.contains(model.focusedIndex) {
                        let id = model.items[model.focusedIndex].id
                        _ = await model.xpc.deleteItem(id: id)
                        await model.refresh()
                    }
                }
                return nil
            }
```

- [ ] **Step 2: Build + commit**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build 2>&1 | tail -5
git add MacAllYouNeed/ClipboardDock/Window/DockWindowController.swift
git commit -m "feat(dock): wire selection-extend + delete shortcuts in key monitor"
```

---

## Task 12: `.draggable` per card type

**Files:**
- Modify: `MacAllYouNeed/ClipboardDock/Views/Cards/TextCard.swift`
- Modify: `MacAllYouNeed/ClipboardDock/Views/Cards/ImageCard.swift`
- Modify: `MacAllYouNeed/ClipboardDock/Views/Cards/FileCard.swift`
- Modify: `MacAllYouNeed/ClipboardDock/Views/Cards/LinkCard.swift`
- Modify: `MacAllYouNeed/ClipboardDock/Views/Cards/ColorCard.swift`

- [ ] **Step 1: TextCard / CodeCard**

Append `.draggable(item.preview)` to the body's outer view.

- [ ] **Step 2: ImageCard**

Replace with:

```swift
        .draggable(image ?? NSImage())
```

(Drag works only after the image is loaded; user-perceived latency is identical to the visible thumbnail load.)

- [ ] **Step 3: FileCard**

Wrap files; the `DockItem.preview` for files reads e.g. `"(2 files)"` so we don't have URLs in the UI layer. We need `bodyText`-style RPC for file URLs — add it as a small extension:

Looking at Phase A: `bodyText(forID:)` only returns text/html. For files we'd need a `bodyFileURLs(forID:reply:)` RPC. Rather than add another XPC method just for drag-out, simpler: provide the file's preview path as a transferable plain string. Drop targets that expect file URLs (Finder) won't accept it cleanly, so this is partial. Mark as known v1 limitation:

```swift
        // Drag-out for files is text-only in Phase D; full file URL drag deferred.
        .draggable(item.preview)
```

A follow-up task in Phase E or a Phase D-bis adds a `bodyFileURLs` RPC if the limitation surfaces in smoke testing.

- [ ] **Step 4: LinkCard**

```swift
        .draggable({
            if case let .link(url) = item.kind { return url } else { return URL(string: "about:blank")! }
        }())
```

- [ ] **Step 5: ColorCard**

```swift
        .draggable(item.preview)
```

- [ ] **Step 6: Build + commit**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build 2>&1 | tail -5
git add MacAllYouNeed/ClipboardDock/Views/Cards/
git commit -m "feat(dock): add .draggable to all card types"
```

---

## Task 13: Drag-out auto-dismiss prevention

**Files:**
- Modify: `MacAllYouNeed/ClipboardDock/Window/DockWindowController.swift`

When the user starts a drag from the dock, the global mouse-down monitor (Phase B) would fire on mouse-up outside the window and dismiss the dock prematurely. Suspend the monitor for 800ms after a drag begins.

- [ ] **Step 1: Track drag-in-progress and gate the monitor**

```swift
    private var ignoreOutsideClicksUntil: Date = .distantPast

    func draggingDidStart() {
        ignoreOutsideClicksUntil = Date().addingTimeInterval(0.8)
    }

    private func startOutsideClickMonitor() {
        stopOutsideClickMonitor()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            guard let self else { return }
            if Date() < ignoreOutsideClicksUntil { return }
            Task { @MainActor in self.hide() }
        }
    }
```

Call `draggingDidStart` from the cards' `.draggable` via `onDrag` — but SwiftUI doesn't expose a callback on `.draggable`. Workaround: use the older `.onDrag { ... }` modifier instead of `.draggable(_:)`:

```swift
    .onDrag {
        AppController.shared?.dock.draggingDidStart()
        return NSItemProvider(object: item.preview as NSString)
    }
```

`AppController.shared` requires adding a static reference:

```swift
@MainActor @Observable
final class AppController {
    static var shared: AppController?
    init() throws { … ; Self.shared = self }
    …
}
```

Acceptable: there's already exactly one AppController.

- [ ] **Step 2: Update card drag modifiers to use `.onDrag`**

Replace each `.draggable(...)` with:

```swift
    .onDrag {
        AppController.shared?.dock.draggingDidStart()
        return NSItemProvider(object: <typed-content> as NSObject)
    }
```

For `URL`: `NSItemProvider(item: url as NSURL, typeIdentifier: UTType.url.identifier)`.
For `NSImage`: `NSItemProvider(object: image)`.
For `String`: `NSItemProvider(object: text as NSString)`.

- [ ] **Step 3: Build + commit**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build 2>&1 | tail -5
git add MacAllYouNeed/App/AppController.swift \
        MacAllYouNeed/ClipboardDock/Window/DockWindowController.swift \
        MacAllYouNeed/ClipboardDock/Views/Cards/
git commit -m "feat(dock): suspend outside-click dismiss for 800ms during drag"
```

---

## Task 14: ColorCard color-picker integration

**Files:**
- Create: `MacAllYouNeed/ClipboardDock/Services/ColorPickerCoordinator.swift`
- Modify: `MacAllYouNeed/ClipboardDock/Views/Cards/ColorCard.swift`

- [ ] **Step 1: Implement coordinator**

```swift
import AppKit

@MainActor
final class ColorPickerCoordinator: NSObject {
    var onColorChosen: ((NSColor) -> Void)?

    func present(initial: NSColor) {
        let panel = NSColorPanel.shared
        panel.color = initial
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func colorChanged(_ sender: NSColorPanel) {
        onColorChosen?(sender.color)
    }
}
```

- [ ] **Step 2: Wire into `ColorCard`**

```swift
import AppKit
import SwiftUI
import UI

struct ColorCard: View {
    let item: DockItem
    @Environment(ClipboardDockModel.self) private var model
    @State private var picker = ColorPickerCoordinator()
    @State private var formatIndex = 0
    private let formats = ["hex", "rgb", "hsl"]

    private var nsColor: NSColor {
        if case let .color(c) = PreviewDetection.detect(item.preview) { return c }
        return .gray
    }

    var body: some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor))
                .frame(maxWidth: .infinity, minHeight: 100, maxHeight: .infinity)
            Text(formattedColor())
                .font(.system(.callout, design: .monospaced))
                .onTapGesture { formatIndex = (formatIndex + 1) % formats.count }
        }
        .padding(10)
        .contextMenu {
            Button("Open in Color Picker") {
                picker.onColorChosen = { c in
                    let hex = c.hexString
                    Task { _ = await model.xpc.pasteText(text: hex, plainText: true, saveAsNew: true) }
                }
                picker.present(initial: nsColor)
            }
        }
        .onDrag {
            AppController.shared?.dock.draggingDidStart()
            return NSItemProvider(object: formattedColor() as NSString)
        }
    }

    private func formattedColor() -> String {
        switch formats[formatIndex] {
        case "rgb":
            let c = nsColor.usingColorSpace(.sRGB) ?? nsColor
            return String(format: "rgb(%d, %d, %d)",
                          Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
        case "hsl":
            let c = nsColor.usingColorSpace(.sRGB) ?? nsColor
            return String(format: "hsl(%.0f, %.0f%%, %.0f%%)",
                          c.hueComponent * 360, c.saturationComponent * 100, c.brightnessComponent * 100)
        default:
            return nsColor.hexString
        }
    }
}

private extension NSColor {
    var hexString: String {
        let c = usingColorSpace(.sRGB) ?? self
        return String(format: "#%02X%02X%02X",
                      Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }
}
```

- [ ] **Step 2: Pass `model` via environment**

In `DockRootView` body, attach `.environment(model)` to the carousel.

- [ ] **Step 3: Build + commit**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build 2>&1 | tail -5
git add MacAllYouNeed/ClipboardDock/Services/ColorPickerCoordinator.swift \
        MacAllYouNeed/ClipboardDock/Views/Cards/ColorCard.swift \
        MacAllYouNeed/ClipboardDock/Views/DockRootView.swift
git commit -m "feat(dock): ColorCard format cycling + Open in Color Picker"
```

---

## Task 15: `CheatsheetOverlay`

**Files:**
- Create: `MacAllYouNeed/ClipboardDock/Views/Cheatsheet/CheatsheetOverlay.swift`
- Modify: `MacAllYouNeed/ClipboardDock/Window/DockWindowController.swift` (⌘? toggle)
- Modify: `MacAllYouNeed/ClipboardDock/Views/DockRootView.swift` (overlay)

- [ ] **Step 1: Implement**

```bash
mkdir -p MacAllYouNeed/ClipboardDock/Views/Cheatsheet
```

```swift
import SwiftUI

struct CheatsheetOverlay: View {
    let registry: ShortcutRegistry

    var body: some View {
        let columns = [GridItem(.flexible()), GridItem(.fixed(120))]
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 8) {
                Text("Keyboard Shortcuts").font(.title2).bold()
                LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                    ForEach(ShortcutAction.allCases) { action in
                        Text(action.label).font(.callout)
                        Text(registry.bindings(for: action).map { $0.display() }.joined(separator: " · "))
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(24)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .frame(maxWidth: 520)
        }
        .transition(.opacity)
    }
}
```

- [ ] **Step 2: Add toggle state and ⌘? handling**

In `ClipboardDockModel`:

```swift
    var showCheatsheet: Bool = false
```

In `DockWindowController.startKeyMonitor`:

```swift
            if registry.matches(event: event, .toggleCheatsheet) {
                Task { @MainActor in model.showCheatsheet.toggle() }
                return nil
            }
```

In `DockRootView`:

```swift
        .overlay {
            if model.showCheatsheet {
                CheatsheetOverlay(registry: registry)
                    .animation(.easeOut(duration: 0.15), value: model.showCheatsheet)
            }
        }
```

- [ ] **Step 3: Build + commit**

```bash
xcodegen generate
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build 2>&1 | tail -5
git add MacAllYouNeed/ClipboardDock/Views/Cheatsheet/CheatsheetOverlay.swift \
        MacAllYouNeed/ClipboardDock/Model/ClipboardDockModel.swift \
        MacAllYouNeed/ClipboardDock/Views/DockRootView.swift \
        MacAllYouNeed/ClipboardDock/Window/DockWindowController.swift \
        MacAllYouNeed.xcodeproj
git commit -m "feat(dock): add CheatsheetOverlay with ⌘? toggle"
```

---

## Task 16: Phase D smoke + regression

- [ ] **Step 1: All tests**

```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeedTests test 2>&1 | tail -20
```

- [ ] **Step 2: Manual smoke (subset of spec §12.6)**

9. Multi-select 3 items, click Paste → joined output with newline delimiter.
10. Image card + Space → Quick Look full-size; arrow keys cycle while overlay open.
11. Right-click text → Transform → Pretty JSON → new clip at front.
12. Drag card into TextEdit → drop works; dock stays open during drag.
13. ⌘T on focused text card → TransformMenu popover shows.
14. ⌘? → cheatsheet overlay shows; ⌘? again hides.
15. ⌘⌫ on focused card → card disappears; another ⌘⌫ on selected items → all selected vanish.

---

## Phase D — Done

End-state of Phase D:

- Multi-select with extend-left/right shortcuts and ⌘+click/⇧+click.
- MultiSelectBar with Paste/Pin/Add to list/Transform/Delete.
- Quick Look overlay per kind.
- TransformMenu popover with ⌘T.
- Drag-out for every card type (text-only for files, deferred to follow-up if friction).
- Drag-aware auto-dismiss prevention.
- ColorCard format cycling + NSColorPanel integration.
- CheatsheetOverlay reading live from `ShortcutRegistry`.
- New `deleteItem` RPC in Phase A pattern.

---

## What comes next

- **Phase E** — Maccy improvements: ignored apps, regex blocklist, storage caps, fuzzy search, sort-by-frequency, suspend-capture, auto-paste behavior.
- **Phase F** — Snippets surfacing.
