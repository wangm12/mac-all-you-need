# Clipboard Dock — Phase B: Visual Overhaul — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the centered floating popup with the new bottom-anchored dock window. Slide-up animation, polymorphic card system (Text/Image/File/Link/Color/Code), source-app gradient badge, and a minimal top bar (search field only — full top bar with Pinboard tabs lands in Phase C). After Phase B, ⌘⇧V opens the new dock with image previews and source-app icons.

**Architecture:** New `MacAllYouNeed/ClipboardDock/` module wired in via `AppController`. View-model `ClipboardDockModel` (skeleton; Phase C grows it) drives a `DockRootView` SwiftUI tree. `BottomDockWindow: NSPanel` handles geometry; `DockAnimator` does slide animations; `DockWindowController` owns lifecycle and outside-click monitoring. Old `MacAllYouNeed/Clipboard/ClipboardPopup*` files are deleted at the end of the phase.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit (`NSPanel`, `NSVisualEffectView`, `CAMediaTimingFunction`), `@Observable`, Core Image (already in Phase A via `ThumbnailRenderer`).

**Spec:** `docs/superpowers/specs/2026-05-07-clipboard-dock-redesign-design.md`

**Depends on:** Phase A (Plumbing) must be merged. Phase B uses `imageThumbnail`, `ClipboardXPCInteracting`, `ClipboardXPCMeta` new fields, `AppIconResolver` (created here), `ImageBlobLoader` (created here).

**Working directory:** `/Users/mingjie.wang/Documents/personal/mac-all-you-need`

**Test commands:**
```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build 2>&1 | tail -10
```

**xcodegen note:** `project.yml` uses `sources: - path: MacAllYouNeed` (recursive). Files added under `MacAllYouNeed/ClipboardDock/` are picked up automatically, but the Xcode project file needs `xcodegen generate` to refresh group structure. Run `xcodegen generate` once after the first new directory is added (Task 1).

---

## File Structure

### Created

| Path | Responsibility |
|---|---|
| `MacAllYouNeed/ClipboardDock/ClipboardDock.swift` | Top-level entry; wires window + view-model + root view. |
| `MacAllYouNeed/ClipboardDock/Window/BottomDockWindow.swift` | NSPanel subclass: bottom-anchored, full-width, key-but-not-main. |
| `MacAllYouNeed/ClipboardDock/Window/DockWindowController.swift` | Show/hide, outside-click monitor, screen-with-cursor anchoring. |
| `MacAllYouNeed/ClipboardDock/Model/ClipboardDockModel.swift` | `@Observable` view-model (skeleton — Phase C/D extend). |
| `MacAllYouNeed/ClipboardDock/Model/DockItem.swift` | UI-layer item type; wraps `ClipboardXPCMeta` + decoded source app. |
| `MacAllYouNeed/ClipboardDock/Model/DockListSelector.swift` | Enum (just `.history` for Phase B; Phase C adds the rest). |
| `MacAllYouNeed/ClipboardDock/Model/SourceApp.swift` | `bundleID + displayName + icon`. |
| `MacAllYouNeed/ClipboardDock/Views/DockRootView.swift` | SwiftUI root; minimal search field + carousel. |
| `MacAllYouNeed/ClipboardDock/Views/Carousel/ClipCarousel.swift` | Horizontal scroll, keyboard nav, focus state. |
| `MacAllYouNeed/ClipboardDock/Views/Carousel/CardSlot.swift` | Wraps a card with selection ring + index badge. |
| `MacAllYouNeed/ClipboardDock/Views/Cards/ClipCard.swift` | Polymorphic dispatcher on `DockItemKind`. |
| `MacAllYouNeed/ClipboardDock/Views/Cards/TextCard.swift` | Plain text rendering. |
| `MacAllYouNeed/ClipboardDock/Views/Cards/ImageCard.swift` | Async-loaded thumbnail via `ImageBlobLoader`. |
| `MacAllYouNeed/ClipboardDock/Views/Cards/FileCard.swift` | Finder icon + filename + count. |
| `MacAllYouNeed/ClipboardDock/Views/Cards/LinkCard.swift` | Favicon + host + URL. |
| `MacAllYouNeed/ClipboardDock/Views/Cards/ColorCard.swift` | Color swatch + hex. |
| `MacAllYouNeed/ClipboardDock/Views/Cards/CodeCard.swift` | Monospace + language tag. |
| `MacAllYouNeed/ClipboardDock/Views/Cards/SourceAppBadge.swift` | Top-right icon + diagonal gradient mask. |
| `MacAllYouNeed/ClipboardDock/Services/AppIconResolver.swift` | bundleID → NSImage cache. |
| `MacAllYouNeed/ClipboardDock/Services/ImageBlobLoader.swift` | XPC `imageThumbnail` → cached NSImage. |
| `MacAllYouNeed/ClipboardDock/Services/DockAnimator.swift` | NSPanel position/alpha animation helpers. |
| `MacAllYouNeed/ClipboardDock/Services/DockPasteCoordinator.swift` | Single-paste via XPC. |
| `MacAllYouNeed/ClipboardDock/Services/FaviconCache.swift` | HEAD favicon.ico → NSImage with `NSURLCache` 24h TTL. |
| `Shared/Sources/UI/PreviewDetection.swift` | Moved from `MacAllYouNeed/Clipboard/PasteboardPreview.swift` so daemon and dock can both use it. |
| `MacAllYouNeedTests/ClipboardDock/ClipboardDockModelTests.swift` | Refresh, focus advancement, list switching. |
| `MacAllYouNeedTests/ClipboardDock/AppIconResolverTests.swift` | Cache hit + fallback. |
| `MacAllYouNeedTests/ClipboardDock/ImageBlobLoaderTests.swift` | XPC mock returns thumbnail; cached on second call. |
| `MacAllYouNeedTests/ClipboardDock/DockItemTests.swift` | Kind derivation from `ClipboardXPCMeta`. |

### Modified

| Path | Change |
|---|---|
| `MacAllYouNeed/App/AppController.swift` | Construct `DockWindowController` instead of `ClipboardPopupController`. Route `.clipboard` `HotkeyAction` to dock. |
| `MacAllYouNeed/App/AppDependencies.swift` | Drop `recentItems`/`activeQuery`/`refresh*`; add `dockModel`. |
| `Shared/Sources/UI/PreviewDetection.swift` | (Created from move; old file deleted in Task 21.) |

### Deleted (Task 21)

- `MacAllYouNeed/Clipboard/ClipboardPopupController.swift`
- `MacAllYouNeed/Clipboard/ClipboardPopupView.swift`
- `MacAllYouNeed/Clipboard/ClipboardItemRow.swift`
- `MacAllYouNeed/Clipboard/PasteboardPreview.swift`

`HotkeyController.swift` survives (only its target — `popup` — gets swapped to the new controller).

---

## Task 1: Move `PasteboardPreview` → `Shared/Sources/UI/PreviewDetection.swift`

**Files:**
- Create: `Shared/Sources/UI/PreviewDetection.swift`
- Delete (later in Task 21): `MacAllYouNeed/Clipboard/PasteboardPreview.swift`
- Modify: `MacAllYouNeed/Clipboard/ClipboardItemRow.swift` to import `UI` for the moved type (transient, deleted in Task 21).

The existing `PasteboardPreview.swift` mixes pure detection logic with a SwiftUI view. We extract just the `PreviewDetection` enum to `Shared/Sources/UI/PreviewDetection.swift` so it can be reused by every new card. The SwiftUI `PasteboardPreview` view will be deleted with the old popup in Task 21 — Phase B cards render content directly per kind.

- [ ] **Step 1: Write the failing test**

Create `Shared/Tests/UITests/PreviewDetectionTests.swift`:

```swift
@testable import UI
import AppKit
import XCTest

final class PreviewDetectionTests: XCTestCase {
    func testDetectsHexColor() {
        if case .color = PreviewDetection.detect("#FF8800") { return }
        XCTFail("expected color")
    }
    func testDetectsURL() {
        if case .url = PreviewDetection.detect("https://example.com") { return }
        XCTFail("expected url")
    }
    func testDetectsCode() {
        if case .code = PreviewDetection.detect("func foo() { return 1 }") { return }
        XCTFail("expected code")
    }
    func testDetectsPlain() {
        if case .plain = PreviewDetection.detect("hello world") { return }
        XCTFail("expected plain")
    }
    func testRejectsInvalidHex() {
        if case .color = PreviewDetection.detect("#XYZ") {
            XCTFail("should not detect color"); return
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter PreviewDetectionTests
```

Expected: FAIL — `PreviewDetection` not in `UI` module.

- [ ] **Step 3: Create `Shared/Sources/UI/PreviewDetection.swift`**

```swift
import AppKit
import Foundation

public enum DetectedKind: Equatable {
    case color(NSColor)
    case url(URL)
    case code(language: String, body: String)
    case plain(String)
}

public enum PreviewDetection {
    public static func detect(_ text: String) -> DetectedKind {
        if let color = parseColor(text) { return .color(color) }
        if let url = URL(string: text), url.scheme == "http" || url.scheme == "https" {
            return .url(url)
        }
        if looksLikeCode(text) { return .code(language: guessLanguage(text), body: text) }
        return .plain(text)
    }

    private static func parseColor(_ s: String) -> NSColor? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("#") else { return nil }
        let hexStr = t.dropFirst()
        guard hexStr.count == 6, let hex = UInt64(hexStr, radix: 16) else { return nil }
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        return NSColor(red: r, green: g, blue: b, alpha: 1)
    }

    private static func looksLikeCode(_ s: String) -> Bool {
        (s.contains("{") && s.contains("}")) || s.contains(";\n") || s.split(separator: "\n").count > 2
    }

    private static func guessLanguage(_ s: String) -> String {
        if s.contains("func ") || s.contains("var ") { return "swift" }
        if s.contains("=>") || s.contains("const ") { return "javascript" }
        if s.contains("def ") { return "python" }
        return "text"
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter PreviewDetectionTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Shared/Sources/UI/PreviewDetection.swift Shared/Tests/UITests/PreviewDetectionTests.swift
git commit -m "$(cat <<'EOF'
refactor(ui): extract PreviewDetection into Shared/UI module

Pure detection logic for color/url/code/plain moves to a Shared
target so daemon and the new dock can both use it. Old SwiftUI
PasteboardPreview view in MacAllYouNeed/Clipboard/ is left in place
until the old popup is deleted in Phase B Task 21.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: `DockItem`, `DockListSelector`, `SourceApp` model types

**Files:**
- Create: `MacAllYouNeed/ClipboardDock/Model/DockItem.swift`
- Create: `MacAllYouNeed/ClipboardDock/Model/DockListSelector.swift`
- Create: `MacAllYouNeed/ClipboardDock/Model/SourceApp.swift`
- Test: `MacAllYouNeedTests/ClipboardDock/DockItemTests.swift`

`DockItem` carries everything a card needs without exposing raw XPC types. `DockItemKind` is derived from `ClipboardXPCMeta.kind` + `PreviewDetection`.

- [ ] **Step 1: Write the failing test**

Create `MacAllYouNeedTests/ClipboardDock/DockItemTests.swift`:

```swift
@testable import MacAllYouNeed
import Core
import XCTest

final class DockItemTests: XCTestCase {
    func testDeriveKindFromImageMeta() {
        let meta = ClipboardXPCMeta(
            id: "1", modified: Date(), kind: "clipboardItem", preview: "(image 32x32)",
            imageWidth: 32, imageHeight: 32, imageBlobID: "blob1"
        )
        let item = DockItem(from: meta, sourceApp: nil, isPinned: false)
        guard case let .image(w, h, blobID) = item.kind else {
            XCTFail("expected image kind"); return
        }
        XCTAssertEqual(w, 32)
        XCTAssertEqual(h, 32)
        XCTAssertEqual(blobID, "blob1")
    }

    func testDeriveKindFromTextWithURLPreview() {
        let meta = ClipboardXPCMeta(
            id: "2", modified: Date(), kind: "clipboardItem", preview: "https://example.com"
        )
        let item = DockItem(from: meta, sourceApp: nil, isPinned: false)
        guard case let .link(url) = item.kind else { XCTFail("expected link"); return }
        XCTAssertEqual(url.absoluteString, "https://example.com")
    }

    func testDeriveKindFromTextWithColorPreview() {
        let meta = ClipboardXPCMeta(
            id: "3", modified: Date(), kind: "clipboardItem", preview: "#ABCDEF"
        )
        let item = DockItem(from: meta, sourceApp: nil, isPinned: false)
        if case .color = item.kind { return }
        XCTFail("expected color")
    }

    func testDeriveKindFromTextDefaultsToText() {
        let meta = ClipboardXPCMeta(
            id: "4", modified: Date(), kind: "clipboardItem", preview: "hello world"
        )
        let item = DockItem(from: meta, sourceApp: nil, isPinned: false)
        if case .text = item.kind { return }
        XCTFail("expected text")
    }

    func testFilesPreviewYieldsFileKind() {
        let meta = ClipboardXPCMeta(
            id: "5", modified: Date(), kind: "clipboardItem", preview: "(2 files)"
        )
        let item = DockItem(from: meta, sourceApp: nil, isPinned: false)
        if case .file = item.kind { return }
        XCTFail("expected file")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeedTests test -only-testing:MacAllYouNeedTests/DockItemTests 2>&1 | tail -10
```

Expected: FAIL — `DockItem` doesn't exist.

- [ ] **Step 3: Create `Shared` for first directory**

```bash
mkdir -p MacAllYouNeed/ClipboardDock/Model
```

Create `MacAllYouNeed/ClipboardDock/Model/SourceApp.swift`:

```swift
import AppKit
import Foundation

struct SourceApp: Hashable {
    let bundleID: String
    let displayName: String
    let icon: NSImage?
}
```

Create `MacAllYouNeed/ClipboardDock/Model/DockListSelector.swift`:

```swift
import Core
import Foundation

enum DockListSelector: Hashable {
    case history
    // Phase C adds: case pinned, case pinboard(RecordID), case snippets
}
```

Create `MacAllYouNeed/ClipboardDock/Model/DockItem.swift`:

```swift
import Core
import Foundation
import UI

enum DockItemKind: Equatable {
    case text
    case image(width: Int, height: Int, blobID: String)
    case file(count: Int)
    case link(URL)
    case color
    case code(language: String)
    case rtf
}

struct DockItem: Identifiable, Hashable {
    let id: String
    let modified: Date
    let kind: DockItemKind
    let preview: String
    let sourceApp: SourceApp?
    let isPinned: Bool

    init(from meta: ClipboardXPCMeta, sourceApp: SourceApp?, isPinned: Bool) {
        id = meta.id
        modified = meta.modified
        preview = meta.preview
        self.sourceApp = sourceApp
        self.isPinned = isPinned

        if meta.imageBlobID != nil {
            kind = .image(width: meta.imageWidth, height: meta.imageHeight, blobID: meta.imageBlobID!)
        } else if meta.preview.hasPrefix("(") && meta.preview.contains("file") {
            let count = meta.preview.firstMatch(of: /\((\d+) file/)
                .flatMap { Int($0.output.1) } ?? 1
            kind = .file(count: count)
        } else if meta.preview.hasPrefix("(html)") {
            kind = .text
        } else if meta.preview == "(rich text)" {
            kind = .rtf
        } else {
            switch PreviewDetection.detect(meta.preview) {
            case .color:
                kind = .color
            case let .url(url):
                kind = .link(url)
            case let .code(language, _):
                kind = .code(language: language)
            case .plain:
                kind = .text
            }
        }
    }
}
```

`firstMatch(of:)` requires Swift 5.9 + Regex — already in deployment target.

- [ ] **Step 4: Run xcodegen and tests**

```bash
xcodegen generate
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeedTests test -only-testing:MacAllYouNeedTests/DockItemTests 2>&1 | tail -10
```

Expected: PASS — five tests green.

- [ ] **Step 5: Commit**

```bash
git add MacAllYouNeed/ClipboardDock/Model/ \
        MacAllYouNeedTests/ClipboardDock/DockItemTests.swift \
        MacAllYouNeed.xcodeproj
git commit -m "$(cat <<'EOF'
feat(dock): add DockItem, DockListSelector, SourceApp model types

DockItem wraps ClipboardXPCMeta + decoded source app + pin flag and
derives DockItemKind from XPC fields plus PreviewDetection. Phase C
extends DockListSelector to include pinned/pinboard/snippets cases.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: `AppIconResolver`

**Files:**
- Create: `MacAllYouNeed/ClipboardDock/Services/AppIconResolver.swift`
- Test: `MacAllYouNeedTests/ClipboardDock/AppIconResolverTests.swift`

Per-session in-memory cache of bundle ID → NSImage. Tests verify cache behavior with synthetic input (we cannot mock `NSWorkspace` easily, so the real test is "asks the same URL twice, hits cache the second time" using a known-installed bundle ID like `com.apple.Finder`).

- [ ] **Step 1: Write the failing test**

Create `MacAllYouNeedTests/ClipboardDock/AppIconResolverTests.swift`:

```swift
@testable import MacAllYouNeed
import AppKit
import XCTest

@MainActor
final class AppIconResolverTests: XCTestCase {
    func testReturnsIconForKnownBundleID() {
        let r = AppIconResolver()
        let icon = r.icon(for: "com.apple.Finder")
        XCTAssertNotNil(icon)
    }

    func testReturnsNilForUnknownBundleID() {
        let r = AppIconResolver()
        XCTAssertNil(r.icon(for: "com.nonexistent.example.app.\(UUID().uuidString)"))
    }

    func testCachesByBundleID() {
        let r = AppIconResolver()
        let first = r.icon(for: "com.apple.Finder")
        let second = r.icon(for: "com.apple.Finder")
        XCTAssertTrue(first === second, "icon should be returned from cache")
    }

    func testDisplayNameReturnsBundleNameForKnownApp() {
        let r = AppIconResolver()
        let name = r.displayName(for: "com.apple.Finder")
        XCTAssertEqual(name, "Finder")
    }

    func testDisplayNameFallsBackToBundleID() {
        let r = AppIconResolver()
        let bid = "com.nonexistent.\(UUID().uuidString)"
        XCTAssertEqual(r.displayName(for: bid), bid)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeedTests test -only-testing:MacAllYouNeedTests/AppIconResolverTests 2>&1 | tail -10
```

Expected: FAIL — `AppIconResolver` doesn't exist.

- [ ] **Step 3: Implement**

```bash
mkdir -p MacAllYouNeed/ClipboardDock/Services
```

Create `MacAllYouNeed/ClipboardDock/Services/AppIconResolver.swift`:

```swift
import AppKit
import Foundation

@MainActor
final class AppIconResolver {
    private var iconCache: [String: NSImage] = [:]
    private var nameCache: [String: String] = [:]

    func icon(for bundleID: String) -> NSImage? {
        if let cached = iconCache[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 32, height: 32)
        iconCache[bundleID] = icon
        return icon
    }

    func displayName(for bundleID: String) -> String {
        if let cached = nameCache[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
              let bundle = Bundle(url: url) else {
            nameCache[bundleID] = bundleID
            return bundleID
        }
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? bundleID
        nameCache[bundleID] = name
        return name
    }
}
```

- [ ] **Step 4: Run tests + xcodegen if needed**

```bash
xcodegen generate
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeedTests test -only-testing:MacAllYouNeedTests/AppIconResolverTests 2>&1 | tail -10
```

Expected: PASS — all five tests green.

- [ ] **Step 5: Commit**

```bash
git add MacAllYouNeed/ClipboardDock/Services/AppIconResolver.swift \
        MacAllYouNeedTests/ClipboardDock/AppIconResolverTests.swift \
        MacAllYouNeed.xcodeproj
git commit -m "$(cat <<'EOF'
feat(dock): add AppIconResolver with per-session bundle ID cache

NSWorkspace lookup with in-memory cache for both icon and display
name. Bounded by ~30 unique source apps in typical usage; no
eviction needed.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: `ImageBlobLoader`

**Files:**
- Create: `MacAllYouNeed/ClipboardDock/Services/ImageBlobLoader.swift`
- Test: `MacAllYouNeedTests/ClipboardDock/ImageBlobLoaderTests.swift`

Async load of a thumbnail via Phase A's `imageThumbnail` XPC method, cached as `NSImage` keyed by `(blobID, maxDim)`. NSCache with 64 MB cost cap.

- [ ] **Step 1: Write the failing test**

Create `MacAllYouNeedTests/ClipboardDock/ImageBlobLoaderTests.swift`:

```swift
@testable import MacAllYouNeed
import Core
import AppKit
import XCTest

final class ImageBlobLoaderTests: XCTestCase {
    final class MockClient: ClipboardXPCInteracting {
        var thumbnailCalls = 0
        var thumbnailToReturn: Data?
        func listItems(query: String?, pageToken: String?, limit: Int) async -> ClipboardXPCList {
            ClipboardXPCList(items: [], nextPageToken: nil)
        }
        func bodyText(forID id: String) async -> String? { nil }
        func paste(itemID: String, plainText: Bool) async -> String { "injected" }
        func pasteMany(itemIDs: [String], delimiter: String, plainText: Bool) async -> String { "injected" }
        func pasteText(text: String, plainText: Bool, saveAsNew: Bool) async -> String { "injected" }
        func transformAndCopy(itemID: String, transform: String, saveAsNew: Bool) async -> String? { nil }
        func imageThumbnail(forID id: String, maxDim: Int) async -> Data? {
            thumbnailCalls += 1
            return thumbnailToReturn
        }
        func listSnippets() async -> [SnippetXPCDTO] { [] }
    }

    func testLoadReturnsImageOnSuccess() async {
        let mock = MockClient()
        // Synthesize a JPEG.
        let img = NSImage(size: NSSize(width: 16, height: 16))
        img.lockFocus(); NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 16, height: 16).fill(); img.unlockFocus()
        let tiff = img.tiffRepresentation!
        let rep = NSBitmapImageRep(data: tiff)!
        mock.thumbnailToReturn = rep.representation(using: .jpeg, properties: [:])
        let loader = ImageBlobLoader(xpc: mock)
        let result = await loader.thumbnail(blobID: "b1", maxDim: 32)
        XCTAssertNotNil(result)
    }

    func testLoadReturnsNilWhenXPCReturnsNil() async {
        let mock = MockClient()
        mock.thumbnailToReturn = nil
        let loader = ImageBlobLoader(xpc: mock)
        XCTAssertNil(await loader.thumbnail(blobID: "b1", maxDim: 32))
    }

    func testLoadCachesByBlobIDAndMaxDim() async {
        let mock = MockClient()
        let img = NSImage(size: NSSize(width: 8, height: 8))
        img.lockFocus(); NSColor.blue.setFill()
        NSRect(x: 0, y: 0, width: 8, height: 8).fill(); img.unlockFocus()
        mock.thumbnailToReturn = NSBitmapImageRep(data: img.tiffRepresentation!)!
            .representation(using: .jpeg, properties: [:])
        let loader = ImageBlobLoader(xpc: mock)
        _ = await loader.thumbnail(blobID: "b1", maxDim: 32)
        _ = await loader.thumbnail(blobID: "b1", maxDim: 32)
        XCTAssertEqual(mock.thumbnailCalls, 1)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeedTests test -only-testing:MacAllYouNeedTests/ImageBlobLoaderTests 2>&1 | tail -10
```

Expected: FAIL — `ImageBlobLoader` doesn't exist.

- [ ] **Step 3: Implement**

Create `MacAllYouNeed/ClipboardDock/Services/ImageBlobLoader.swift`:

```swift
import AppKit
import Core
import Foundation

actor ImageBlobLoader {
    private let xpc: any ClipboardXPCInteracting
    private let cache = NSCache<NSString, NSImage>()

    init(xpc: any ClipboardXPCInteracting, totalCostLimitBytes: Int = 64 * 1024 * 1024) {
        self.xpc = xpc
        cache.totalCostLimit = totalCostLimitBytes
    }

    func thumbnail(blobID: String, maxDim: Int) async -> NSImage? {
        let key = "\(blobID)|\(maxDim)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let data = await xpc.imageThumbnail(forID: blobID, maxDim: maxDim),
              let image = NSImage(data: data) else { return nil }
        cache.setObject(image, forKey: key, cost: data.count)
        return image
    }

    func clear(blobID: String) {
        // Phase E (storage caps) calls this on blob deletion.
        // Iterate keys is not possible on NSCache; rely on cache cost-eviction instead.
    }
}
```

Note: `imageThumbnail` is keyed in the daemon by the *record* ID, not the blob ID, but the parameter is named `forID` — review Phase A Task 6 step 4. The first param is the *record* ID. The `blobID` here is what the daemon resolves internally. The loader should pass the record ID, not the blob ID.

Correction — the loader's API takes `blobID: String` but the underlying XPC call is by record ID. The actual UI flow is: card has `DockItemKind.image(width, height, blobID)` AND a record ID; loader is called with record ID. Rename param:

```swift
    func thumbnail(recordID: String, maxDim: Int) async -> NSImage? {
        let key = "\(recordID)|\(maxDim)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let data = await xpc.imageThumbnail(forID: recordID, maxDim: maxDim),
              let image = NSImage(data: data) else { return nil }
        cache.setObject(image, forKey: key, cost: data.count)
        return image
    }
```

Update test to call `thumbnail(recordID: "b1", maxDim: 32)` (semantics-only rename; existing tests still pass since the mock ignores the ID).

- [ ] **Step 4: Run tests**

```bash
xcodegen generate
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeedTests test -only-testing:MacAllYouNeedTests/ImageBlobLoaderTests 2>&1 | tail -10
```

Expected: PASS — three tests green.

- [ ] **Step 5: Commit**

```bash
git add MacAllYouNeed/ClipboardDock/Services/ImageBlobLoader.swift \
        MacAllYouNeedTests/ClipboardDock/ImageBlobLoaderTests.swift \
        MacAllYouNeed.xcodeproj
git commit -m "$(cat <<'EOF'
feat(dock): add ImageBlobLoader actor over imageThumbnail XPC

Async cached NSImage loader. NSCache 64 MB cap. Used by ImageCard
to render previews without blocking the carousel.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: `ClipboardDockModel` skeleton

**Files:**
- Create: `MacAllYouNeed/ClipboardDock/Model/ClipboardDockModel.swift`
- Test: `MacAllYouNeedTests/ClipboardDock/ClipboardDockModelTests.swift`

Phase B model: holds `items`, `search`, `focusedIndex`. Refresh debounced 100ms. Phase C extends with active list, Pinboards, multi-select; Phase D adds Quick Look + transformations.

- [ ] **Step 1: Write the failing test**

Create `MacAllYouNeedTests/ClipboardDock/ClipboardDockModelTests.swift`:

```swift
@testable import MacAllYouNeed
import Core
import XCTest

@MainActor
final class ClipboardDockModelTests: XCTestCase {
    final class MockClient: ClipboardXPCInteracting {
        var listCalls = 0
        var listResults: [ClipboardXPCMeta] = []
        func listItems(query: String?, pageToken: String?, limit: Int) async -> ClipboardXPCList {
            listCalls += 1
            return ClipboardXPCList(items: listResults, nextPageToken: nil)
        }
        func bodyText(forID id: String) async -> String? { nil }
        func paste(itemID: String, plainText: Bool) async -> String { "injected" }
        func pasteMany(itemIDs: [String], delimiter: String, plainText: Bool) async -> String { "injected" }
        func pasteText(text: String, plainText: Bool, saveAsNew: Bool) async -> String { "injected" }
        func transformAndCopy(itemID: String, transform: String, saveAsNew: Bool) async -> String? { nil }
        func imageThumbnail(forID id: String, maxDim: Int) async -> Data? { nil }
        func listSnippets() async -> [SnippetXPCDTO] { [] }
    }

    private func makeModel(_ mock: MockClient) -> ClipboardDockModel {
        ClipboardDockModel(
            xpc: mock,
            appIcons: AppIconResolver(),
            imageLoader: ImageBlobLoader(xpc: mock)
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
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeedTests test -only-testing:MacAllYouNeedTests/ClipboardDockModelTests 2>&1 | tail -10
```

Expected: FAIL — `ClipboardDockModel` doesn't exist.

- [ ] **Step 3: Implement skeleton**

Create `MacAllYouNeed/ClipboardDock/Model/ClipboardDockModel.swift`:

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

    var items: [DockItem] = []
    var search: String = ""
    var focusedIndex: Int = 0
    var activeList: DockListSelector = .history    // Phase C broadens

    init(xpc: any ClipboardXPCInteracting, appIcons: AppIconResolver, imageLoader: ImageBlobLoader) {
        self.xpc = xpc
        self.appIcons = appIcons
        self.imageLoader = imageLoader
    }

    func refresh() async {
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let query: String? = trimmed.isEmpty ? nil : trimmed
        let list = await xpc.listItems(query: query, pageToken: nil, limit: 50)
        items = list.items.map { meta in
            let app: SourceApp? = meta.sourceAppBundleID.map {
                SourceApp(
                    bundleID: $0,
                    displayName: appIcons.displayName(for: $0),
                    icon: appIcons.icon(for: $0)
                )
            }
            return DockItem(from: meta, sourceApp: app, isPinned: false)
        }
        focusedIndex = 0
    }

    func focusForward() {
        guard !items.isEmpty else { return }
        focusedIndex = min(items.count - 1, focusedIndex + 1)
    }

    func focusBackward() {
        guard !items.isEmpty else { return }
        focusedIndex = max(0, focusedIndex - 1)
    }
}
```

- [ ] **Step 4: Run tests**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeedTests test -only-testing:MacAllYouNeedTests/ClipboardDockModelTests 2>&1 | tail -10
```

Expected: PASS — five tests green.

- [ ] **Step 5: Commit**

```bash
git add MacAllYouNeed/ClipboardDock/Model/ClipboardDockModel.swift \
        MacAllYouNeedTests/ClipboardDock/ClipboardDockModelTests.swift
git commit -m "$(cat <<'EOF'
feat(dock): add ClipboardDockModel skeleton with refresh + focus

Phase B baseline: items, search, focusedIndex, refresh via XPC,
focus forward/backward with clamping. Phase C extends with active-
list switching, Pinboards, multi-select. Phase D adds Quick Look
and transformation state.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: `SourceAppBadge` view

**Files:**
- Create: `MacAllYouNeed/ClipboardDock/Views/Cards/SourceAppBadge.swift`

SwiftUI view-only; no test (per spec §12.5). Implements diagonal gradient + top-right icon as designed in spec §7.4.

- [ ] **Step 1: Implement**

```bash
mkdir -p MacAllYouNeed/ClipboardDock/Views/Cards
```

Create `MacAllYouNeed/ClipboardDock/Views/Cards/SourceAppBadge.swift`:

```swift
import SwiftUI

struct SourceAppBadge: View {
    let app: SourceApp?
    let cardBackground: Color

    var body: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(
                stops: [
                    .init(color: .clear,                       location: 0.0),
                    .init(color: cardBackground.opacity(0.0),  location: 0.5),
                    .init(color: cardBackground.opacity(0.85), location: 0.85),
                    .init(color: cardBackground,               location: 1.0)
                ],
                startPoint: .bottomLeading,
                endPoint: .topTrailing
            )
            .frame(width: 110, height: 80)
            .allowsHitTesting(false)

            if let app, let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .help(app.displayName)
                    .padding(8)
            } else {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundStyle(.tertiary)
                    .padding(8)
            }
        }
    }
}
```

- [ ] **Step 2: Verify it compiles**

```bash
xcodegen generate
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add MacAllYouNeed/ClipboardDock/Views/Cards/SourceAppBadge.swift \
        MacAllYouNeed.xcodeproj
git commit -m "$(cat <<'EOF'
feat(dock): add SourceAppBadge view with diagonal gradient mask

Top-right 20pt app icon over a card-background gradient that fades
underlying text into the card so it never clips at the icon.
Falls back to a question-mark glyph when source app unknown.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: `TextCard` view

**Files:**
- Create: `MacAllYouNeed/ClipboardDock/Views/Cards/TextCard.swift`

- [ ] **Step 1: Implement**

```swift
import SwiftUI
import UI

struct TextCard: View {
    let item: DockItem
    var body: some View {
        let isCode: Bool = {
            if case .code = item.kind { return true } else { return false }
        }()
        Text(item.preview)
            .font(isCode ? .system(.body, design: .monospaced) : .body)
            .lineLimit(8)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(10)
    }
}
```

- [ ] **Step 2: Verify build**

```bash
xcodegen generate
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add MacAllYouNeed/ClipboardDock/Views/Cards/TextCard.swift MacAllYouNeed.xcodeproj
git commit -m "feat(dock): add TextCard view"
```

---

## Task 8: `ImageCard` view

**Files:**
- Create: `MacAllYouNeed/ClipboardDock/Views/Cards/ImageCard.swift`

- [ ] **Step 1: Implement**

```swift
import SwiftUI

struct ImageCard: View {
    let item: DockItem
    let loader: ImageBlobLoader
    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if failed {
                Image(systemName: "photo")
                    .font(.system(size: 32))
                    .foregroundStyle(.tertiary)
            } else {
                Rectangle()
                    .fill(Color.secondary.opacity(0.1))
                    .overlay(ProgressView().controlSize(.small))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(10)
        .task(id: item.id) {
            let img = await loader.thumbnail(recordID: item.id, maxDim: 240)
            await MainActor.run {
                if let img { self.image = img } else { self.failed = true }
            }
        }
    }
}
```

- [ ] **Step 2: Verify build**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add MacAllYouNeed/ClipboardDock/Views/Cards/ImageCard.swift
git commit -m "feat(dock): add ImageCard view with async thumbnail load"
```

---

## Task 9: `FileCard` view

**Files:**
- Create: `MacAllYouNeed/ClipboardDock/Views/Cards/FileCard.swift`

- [ ] **Step 1: Implement**

```swift
import AppKit
import SwiftUI

struct FileCard: View {
    let item: DockItem

    var body: some View {
        let count: Int = {
            if case let .file(c) = item.kind { return c } else { return 0 }
        }()
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "doc.fill")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(item.preview)
                .font(.callout)
                .lineLimit(2)
            if count > 1 {
                Text("\(count) files").font(.caption).foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(10)
    }
}
```

- [ ] **Step 2: Build + commit**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build 2>&1 | tail -5
git add MacAllYouNeed/ClipboardDock/Views/Cards/FileCard.swift
git commit -m "feat(dock): add FileCard view"
```

---

## Task 10: `LinkCard` + `FaviconCache`

**Files:**
- Create: `MacAllYouNeed/ClipboardDock/Views/Cards/LinkCard.swift`
- Create: `MacAllYouNeed/ClipboardDock/Services/FaviconCache.swift`

- [ ] **Step 1: Implement `FaviconCache`**

```swift
import AppKit
import Foundation

actor FaviconCache {
    private var memory: [String: NSImage] = [:]
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.urlCache = URLCache(memoryCapacity: 8 * 1024 * 1024,
                                    diskCapacity: 32 * 1024 * 1024)
        config.timeoutIntervalForRequest = 5
        session = URLSession(configuration: config)
    }

    func favicon(for url: URL) async -> NSImage? {
        guard let host = url.host else { return nil }
        if let cached = memory[host] { return cached }
        guard let iconURL = URL(string: "https://\(host)/favicon.ico") else { return nil }
        do {
            let (data, response) = try await session.data(from: iconURL)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let image = NSImage(data: data) else { return nil }
            memory[host] = image
            return image
        } catch {
            return nil
        }
    }
}
```

- [ ] **Step 2: Implement `LinkCard`**

```swift
import SwiftUI

struct LinkCard: View {
    let item: DockItem
    let favicons: FaviconCache
    @State private var favicon: NSImage?

    var body: some View {
        let url: URL? = {
            if case let .link(u) = item.kind { return u } else { return nil }
        }()
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let favicon {
                    Image(nsImage: favicon).resizable().frame(width: 16, height: 16)
                } else {
                    Image(systemName: "link").foregroundStyle(.secondary)
                }
                Text(url?.host ?? "")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Text(item.preview).font(.callout).lineLimit(3)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(10)
        .task(id: item.id) {
            guard let url else { return }
            favicon = await favicons.favicon(for: url)
        }
    }
}
```

- [ ] **Step 3: Build + commit**

```bash
xcodegen generate
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build 2>&1 | tail -5
git add MacAllYouNeed/ClipboardDock/Views/Cards/LinkCard.swift \
        MacAllYouNeed/ClipboardDock/Services/FaviconCache.swift \
        MacAllYouNeed.xcodeproj
git commit -m "feat(dock): add LinkCard with FaviconCache"
```

---

## Task 11: `ColorCard` view

**Files:**
- Create: `MacAllYouNeed/ClipboardDock/Views/Cards/ColorCard.swift`

- [ ] **Step 1: Implement**

```swift
import SwiftUI
import UI

struct ColorCard: View {
    let item: DockItem
    var body: some View {
        let nsColor: NSColor = {
            if case let .color(c) = PreviewDetection.detect(item.preview) { return c }
            return .gray
        }()
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor))
                .frame(maxWidth: .infinity, minHeight: 100, maxHeight: .infinity)
            Text(item.preview)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.primary)
        }
        .padding(10)
    }
}
```

- [ ] **Step 2: Build + commit**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build 2>&1 | tail -5
git add MacAllYouNeed/ClipboardDock/Views/Cards/ColorCard.swift
git commit -m "feat(dock): add ColorCard view"
```

---

## Task 12: `CodeCard` view

**Files:**
- Create: `MacAllYouNeed/ClipboardDock/Views/Cards/CodeCard.swift`

- [ ] **Step 1: Implement**

```swift
import SwiftUI

struct CodeCard: View {
    let item: DockItem
    var body: some View {
        let language: String = {
            if case let .code(l) = item.kind { return l } else { return "text" }
        }()
        VStack(alignment: .leading, spacing: 6) {
            Text(language.uppercased())
                .font(.caption2).foregroundStyle(.tertiary)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.secondary.opacity(0.15))
                .clipShape(Capsule())
            Text(item.preview)
                .font(.system(.body, design: .monospaced))
                .lineLimit(8)
                .foregroundStyle(.primary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(10)
    }
}
```

- [ ] **Step 2: Build + commit**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build 2>&1 | tail -5
git add MacAllYouNeed/ClipboardDock/Views/Cards/CodeCard.swift
git commit -m "feat(dock): add CodeCard view"
```

---

## Task 13: `ClipCard` polymorphic dispatcher

**Files:**
- Create: `MacAllYouNeed/ClipboardDock/Views/Cards/ClipCard.swift`

- [ ] **Step 1: Implement**

```swift
import SwiftUI

struct ClipCard: View {
    let item: DockItem
    let imageLoader: ImageBlobLoader
    let favicons: FaviconCache
    let cardBackground: Color

    var body: some View {
        ZStack(alignment: .topTrailing) {
            cardContent
            SourceAppBadge(app: item.sourceApp, cardBackground: cardBackground)
        }
        .background(cardBackground)
        .cornerRadius(10)
    }

    @ViewBuilder
    private var cardContent: some View {
        switch item.kind {
        case .text, .rtf: TextCard(item: item)
        case .image:      ImageCard(item: item, loader: imageLoader)
        case .file:       FileCard(item: item)
        case .link:       LinkCard(item: item, favicons: favicons)
        case .color:      ColorCard(item: item)
        case .code:       CodeCard(item: item)
        }
    }
}
```

- [ ] **Step 2: Build + commit**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build 2>&1 | tail -5
git add MacAllYouNeed/ClipboardDock/Views/Cards/ClipCard.swift
git commit -m "feat(dock): add ClipCard polymorphic dispatcher"
```

---

## Task 14: `CardSlot` (selection ring + index badge)

**Files:**
- Create: `MacAllYouNeed/ClipboardDock/Views/Carousel/CardSlot.swift`

- [ ] **Step 1: Implement**

```bash
mkdir -p MacAllYouNeed/ClipboardDock/Views/Carousel
```

```swift
import SwiftUI

struct CardSlot: View {
    let item: DockItem
    let index: Int
    let isFocused: Bool
    let imageLoader: ImageBlobLoader
    let favicons: FaviconCache

    private var cardBackground: Color { Color(NSColor.controlBackgroundColor) }

    var body: some View {
        ClipCard(item: item, imageLoader: imageLoader, favicons: favicons,
                 cardBackground: cardBackground)
            .frame(width: 220, height: 240)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isFocused ? Color.accentColor : .clear, lineWidth: 2)
            )
            .overlay(alignment: .bottomLeading) {
                if index < 9 {
                    Text("⌘\(index + 1)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .padding(6)
                }
            }
    }
}
```

- [ ] **Step 2: Build + commit**

```bash
xcodegen generate
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build 2>&1 | tail -5
git add MacAllYouNeed/ClipboardDock/Views/Carousel/CardSlot.swift MacAllYouNeed.xcodeproj
git commit -m "feat(dock): add CardSlot with selection ring and index badge"
```

---

## Task 15: `ClipCarousel`

**Files:**
- Create: `MacAllYouNeed/ClipboardDock/Views/Carousel/ClipCarousel.swift`

- [ ] **Step 1: Implement**

```swift
import SwiftUI

struct ClipCarousel: View {
    @Bindable var model: ClipboardDockModel
    let favicons: FaviconCache
    let onPaste: (Int) -> Void

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
                        .onTapGesture { onPaste(idx) }
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
        .onKeyPress(.leftArrow) { model.focusBackward(); return .handled }
        .onKeyPress(.rightArrow) { model.focusForward(); return .handled }
        .onKeyPress(.return) { onPaste(model.focusedIndex); return .handled }
    }
}
```

- [ ] **Step 2: Build + commit**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build 2>&1 | tail -5
git add MacAllYouNeed/ClipboardDock/Views/Carousel/ClipCarousel.swift
git commit -m "feat(dock): add ClipCarousel with horizontal scroll + arrow nav"
```

---

## Task 16: `DockPasteCoordinator`

**Files:**
- Create: `MacAllYouNeed/ClipboardDock/Services/DockPasteCoordinator.swift`

- [ ] **Step 1: Implement**

```swift
import AppKit
import Core
import Foundation

@MainActor
final class DockPasteCoordinator {
    private let xpc: any ClipboardXPCInteracting
    init(xpc: any ClipboardXPCInteracting) { self.xpc = xpc }

    func paste(itemID: String, plainText: Bool, dismissWindow: @MainActor () -> Void) async {
        dismissWindow()
        try? await Task.sleep(nanoseconds: 80_000_000)
        _ = await xpc.paste(itemID: itemID, plainText: plainText)
    }
}
```

The 80ms sleep matches the existing popup behavior (`MacAllYouNeed/Clipboard/ClipboardPopupView.swift:55`) — gives the window time to slide down before the simulated ⌘V keystroke fires.

- [ ] **Step 2: Build + commit**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build 2>&1 | tail -5
git add MacAllYouNeed/ClipboardDock/Services/DockPasteCoordinator.swift
git commit -m "feat(dock): add DockPasteCoordinator for single-paste via XPC"
```

---

## Task 17: `DockAnimator`

**Files:**
- Create: `MacAllYouNeed/ClipboardDock/Services/DockAnimator.swift`

- [ ] **Step 1: Implement**

```swift
import AppKit

enum DockAnimator {
    static let showDuration: TimeInterval = 0.22
    static let hideDuration: TimeInterval = 0.18

    static func slideUp(_ window: NSWindow, finalOrigin: NSPoint, completion: @escaping () -> Void) {
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if reduce {
            window.setFrameOrigin(finalOrigin)
            window.alphaValue = 1
            completion()
            return
        }
        var startFrame = window.frame
        startFrame.origin.y = finalOrigin.y - startFrame.height
        window.setFrame(startFrame, display: false)
        window.alphaValue = 0
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = showDuration
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
            window.animator().setFrameOrigin(finalOrigin)
            window.animator().alphaValue = 1
        }, completionHandler: completion)
    }

    static func slideDown(_ window: NSWindow, completion: @escaping () -> Void) {
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if reduce {
            window.alphaValue = 0
            completion()
            return
        }
        var endFrame = window.frame
        endFrame.origin.y -= endFrame.height
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = hideDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().setFrame(endFrame, display: true)
            window.animator().alphaValue = 0
        }, completionHandler: completion)
    }
}
```

- [ ] **Step 2: Build + commit**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build 2>&1 | tail -5
git add MacAllYouNeed/ClipboardDock/Services/DockAnimator.swift
git commit -m "feat(dock): add DockAnimator with slide-up/down + reduced motion"
```

---

## Task 18: `BottomDockWindow`

**Files:**
- Create: `MacAllYouNeed/ClipboardDock/Window/BottomDockWindow.swift`

- [ ] **Step 1: Implement**

```bash
mkdir -p MacAllYouNeed/ClipboardDock/Window
```

```swift
import AppKit

final class BottomDockWindow: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = false
        isFloatingPanel = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
```

- [ ] **Step 2: Build + commit**

```bash
xcodegen generate
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build 2>&1 | tail -5
git add MacAllYouNeed/ClipboardDock/Window/BottomDockWindow.swift MacAllYouNeed.xcodeproj
git commit -m "feat(dock): add BottomDockWindow NSPanel subclass"
```

---

## Task 19: `DockRootView`

**Files:**
- Create: `MacAllYouNeed/ClipboardDock/Views/DockRootView.swift`

- [ ] **Step 1: Implement**

```bash
mkdir -p MacAllYouNeed/ClipboardDock/Views
```

```swift
import SwiftUI

struct DockRootView: View {
    @Bindable var model: ClipboardDockModel
    let favicons: FaviconCache
    let dismiss: () -> Void
    let onPaste: (Int, Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Phase B placeholder top bar (real DockTopBar lands in Phase C)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search clipboard…", text: $model.search)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(.thinMaterial)
            .onChange(of: model.search) { _, _ in Task { await model.refresh() } }

            Divider()

            ClipCarousel(
                model: model,
                favicons: favicons,
                onPaste: { idx in
                    let plainText = NSEvent.modifierFlags.contains(.option)
                    onPaste(idx, plainText)
                }
            )
            .frame(maxHeight: .infinity)
        }
        .background(
            VisualEffectBackground(material: .popover, blendingMode: .behindWindow)
        )
        .clipShape(RoundedCorners(radius: 12, corners: [.topLeft, .topRight]))
        .onKeyPress(.escape) { dismiss(); return .handled }
    }
}

private struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blendingMode
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

private struct RoundedCorners: Shape {
    var radius: CGFloat
    var corners: NSRectCorner
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let tl = corners.contains(.topLeft) ? radius : 0
        let tr = corners.contains(.topRight) ? radius : 0
        let bl = corners.contains(.bottomLeft) ? radius : 0
        let br = corners.contains(.bottomRight) ? radius : 0
        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + tr),
                          control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - br, y: rect.maxY),
                          control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - bl),
                          control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        path.addQuadCurve(to: CGPoint(x: rect.minX + tl, y: rect.minY),
                          control: CGPoint(x: rect.minX, y: rect.minY))
        return path
    }
}

private struct NSRectCorner: OptionSet {
    let rawValue: Int
    static let topLeft = NSRectCorner(rawValue: 1 << 0)
    static let topRight = NSRectCorner(rawValue: 1 << 1)
    static let bottomLeft = NSRectCorner(rawValue: 1 << 2)
    static let bottomRight = NSRectCorner(rawValue: 1 << 3)
}
```

- [ ] **Step 2: Build + commit**

```bash
xcodegen generate
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build 2>&1 | tail -5
git add MacAllYouNeed/ClipboardDock/Views/DockRootView.swift MacAllYouNeed.xcodeproj
git commit -m "feat(dock): add DockRootView with placeholder top bar + carousel"
```

---

## Task 20: `DockWindowController`

**Files:**
- Create: `MacAllYouNeed/ClipboardDock/Window/DockWindowController.swift`

- [ ] **Step 1: Implement**

```swift
import AppKit
import Core
import SwiftUI

@MainActor
final class DockWindowController {
    private let model: ClipboardDockModel
    private let pasteCoord: DockPasteCoordinator
    private let favicons: FaviconCache
    private var window: BottomDockWindow?
    private var outsideClickMonitor: Any?

    var dockHeight: CGFloat = 360

    init(model: ClipboardDockModel, pasteCoord: DockPasteCoordinator, favicons: FaviconCache) {
        self.model = model
        self.pasteCoord = pasteCoord
        self.favicons = favicons
    }

    func toggle() {
        if window?.isVisible == true { hide() } else { show() }
    }

    func show() {
        Task { await model.refresh() }
        let screen = screenWithCursor() ?? NSScreen.main!
        let frame = NSRect(
            x: screen.visibleFrame.minX,
            y: screen.visibleFrame.minY,
            width: screen.visibleFrame.width,
            height: dockHeight
        )
        let panel = window ?? BottomDockWindow(contentRect: frame)
        panel.setContentSize(NSSize(width: frame.width, height: frame.height))
        panel.contentView = NSHostingView(
            rootView: DockRootView(
                model: model,
                favicons: favicons,
                dismiss: { [weak self] in self?.hide() },
                onPaste: { [weak self] idx, plain in
                    guard let self,
                          model.items.indices.contains(idx) else { return }
                    let id = model.items[idx].id
                    Task {
                        await self.pasteCoord.paste(
                            itemID: id, plainText: plain,
                            dismissWindow: { self.hide() }
                        )
                    }
                }
            )
        )
        if window == nil { window = panel }
        DockAnimator.slideUp(panel, finalOrigin: NSPoint(x: frame.minX, y: frame.minY)) {
            panel.makeKey()
        }
        panel.orderFrontRegardless()
        startOutsideClickMonitor()
    }

    func hide() {
        stopOutsideClickMonitor()
        guard let w = window else { return }
        DockAnimator.slideDown(w) { [weak w] in w?.orderOut(nil) }
    }

    private func screenWithCursor() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
    }

    private func startOutsideClickMonitor() {
        stopOutsideClickMonitor()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
    }

    private func stopOutsideClickMonitor() {
        if let m = outsideClickMonitor {
            NSEvent.removeMonitor(m)
            outsideClickMonitor = nil
        }
    }
}
```

- [ ] **Step 2: Build + commit**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build 2>&1 | tail -5
git add MacAllYouNeed/ClipboardDock/Window/DockWindowController.swift
git commit -m "feat(dock): add DockWindowController with toggle + slide animation"
```

---

## Task 21: Wire `AppController` to use the new dock; delete old popup

**Files:**
- Modify: `MacAllYouNeed/App/AppController.swift`
- Modify: `MacAllYouNeed/App/AppDependencies.swift`
- Modify: `MacAllYouNeed/Clipboard/HotkeyController.swift` (point at new controller)
- Delete: `MacAllYouNeed/Clipboard/ClipboardPopupController.swift`
- Delete: `MacAllYouNeed/Clipboard/ClipboardPopupView.swift`
- Delete: `MacAllYouNeed/Clipboard/ClipboardItemRow.swift`
- Delete: `MacAllYouNeed/Clipboard/PasteboardPreview.swift`

- [ ] **Step 1: Shrink `AppDependencies.swift`**

Replace contents:

```swift
import Core
import Foundation
import SwiftUI

@MainActor
@Observable
final class AppDependencies: NSObject, ClipboardXPCClientCallback {
    let xpc: ClipboardXPCClient
    let appIcons = AppIconResolver()
    let imageLoader: ImageBlobLoader
    let dockModel: ClipboardDockModel

    override init() {
        let client = ClipboardXPCClient(resumesImmediately: false)
        xpc = client
        let loader = ImageBlobLoader(xpc: client)
        imageLoader = loader
        dockModel = ClipboardDockModel(xpc: client, appIcons: appIcons, imageLoader: loader)
        super.init()
        xpc.connection.exportedInterface = NSXPCInterface(with: ClipboardXPCClientCallback.self)
        xpc.connection.exportedObject = self
        xpc.resume()
        xpc.proxy()?.registerCallback { _ in }
        Task { @MainActor in
            for delay in [0.5, 1.0, 2.0, 4.0] {
                await dockModel.refresh()
                if !dockModel.items.isEmpty { return }
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    nonisolated func itemsInvalidated() {
        Task { @MainActor in await dockModel.refresh() }
    }
}
```

- [ ] **Step 2: Update `AppController.swift`**

Replace these specific lines/blocks. In init:

```swift
        let deps = AppDependencies()
        let pasteCoord = DockPasteCoordinator(xpc: deps.xpc)
        let favicons = FaviconCache()
        let dock = DockWindowController(
            model: deps.dockModel,
            pasteCoord: pasteCoord,
            favicons: favicons
        )
        self.clipboardDeps = deps
        self.dock = dock
```

Add stored property at top (replacing `let popup: ClipboardPopupController`):

```swift
    let dock: DockWindowController
```

In the fallback hotkey closure and `performHotkeyAction(.clipboard:)`, swap `popup.show()` for `dock.toggle()`:

```swift
        do {
            try hotkeyRegistry.apply(HotkeyMapStore.load(), controller: self)
        } catch {
            let hk = GlobalHotkey(descriptor: .defaultClipboard) { [weak dock] in
                Task { @MainActor in dock?.toggle() }
            }
            try? hk.register()
            fallbackHotkey = hk
        }
```

```swift
    func performHotkeyAction(_ action: HotkeyAction) {
        switch action {
        case .clipboard: dock.toggle()
        case .addDownload: NotificationCenter.default.post(name: .addDownloadRequested, object: nil)
        case .browseFolder: folder.openPanelAndBrowse()
        }
    }
```

- [ ] **Step 3: Update `HotkeyController.swift`**

Swap `popup` for `dock`:

```swift
import AppKit
import Platform

@MainActor
final class HotkeyController {
    private let dock: DockWindowController
    private var hotkey: GlobalHotkey?

    init(dock: DockWindowController) { self.dock = dock }

    func registerDefault() { try? registerHotkeyThrowing() }

    func registerHotkeyThrowing() throws {
        hotkey = GlobalHotkey(descriptor: .defaultClipboard) { [weak self] in
            Task { @MainActor in self?.dock.toggle() }
        }
        try hotkey?.register()
    }

    func unregister() {
        hotkey?.unregister()
        hotkey = nil
    }
}
```

- [ ] **Step 4: Delete old popup files**

```bash
rm MacAllYouNeed/Clipboard/ClipboardPopupController.swift \
   MacAllYouNeed/Clipboard/ClipboardPopupView.swift \
   MacAllYouNeed/Clipboard/ClipboardItemRow.swift \
   MacAllYouNeed/Clipboard/PasteboardPreview.swift
xcodegen generate
```

- [ ] **Step 5: Build + run smoke**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`. If references to deleted files remain, find and update.

- [ ] **Step 6: Manual smoke test**

Launch the app from Xcode. Press ⌘⇧V. Expected:
- Dock slides up from the bottom of the screen with cursor.
- Search field at top, horizontal carousel of cards underneath.
- Recent text/image clips render with correct content; image cards show thumbnails.
- Cards from a known app (Chrome/iTerm/Cursor) show the app icon top-right with gradient fade.
- Arrow keys move focus; Enter pastes into previously-focused app; Esc dismisses.
- ⌘⇧V again toggles dismiss.

If any step fails, fix before committing.

- [ ] **Step 7: Commit**

```bash
git add MacAllYouNeed/App/AppController.swift \
        MacAllYouNeed/App/AppDependencies.swift \
        MacAllYouNeed/Clipboard/HotkeyController.swift \
        MacAllYouNeed.xcodeproj
git rm MacAllYouNeed/Clipboard/ClipboardPopupController.swift \
       MacAllYouNeed/Clipboard/ClipboardPopupView.swift \
       MacAllYouNeed/Clipboard/ClipboardItemRow.swift \
       MacAllYouNeed/Clipboard/PasteboardPreview.swift
git commit -m "$(cat <<'EOF'
feat(dock): wire ClipboardDock as the ⌘⇧V handler; delete old popup

AppController now constructs DockWindowController, AppDependencies
exposes dockModel, HotkeyController routes to dock.toggle(). Old
ClipboardPopup* files removed; PasteboardPreview's detection logic
moved to Shared/UI in Task 1, the SwiftUI view is no longer needed.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 22: Phase B regression sweep

- [ ] **Step 1: Run full test suite**

```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeedTests test 2>&1 | tail -20
```

Expected: all green. Phase A's `ClipboardXPCServiceTests`, `ThumbnailRendererTests`, `ThumbnailCacheTests`, `TextTransformsTests`, `ClipboardXPCInteractingTests` still pass; new Phase B tests (`PreviewDetectionTests`, `DockItemTests`, `AppIconResolverTests`, `ImageBlobLoaderTests`, `ClipboardDockModelTests`) all pass.

- [ ] **Step 2: Manual smoke checklist (subset of spec §12.6)**

1. ⌘⇧V opens dock with slide-up; ⌘⇧V dismisses.
2. Multi-monitor: dock follows cursor screen.
3. Reduced-motion (System Settings → Accessibility → Display): no slide.
4. Copy in Chrome → card shows Chrome icon top-right with gradient fade.
5. Copy image → image card renders thumbnail < 200ms.
6. Copy file in Finder → file card shows Finder icon + name.
7. Search "git" filters live across types.

Items 8–16 of the spec checklist are validated in Phase C–F.

- [ ] **Step 3: No-op commit not required** — Phase B is complete. Move to the Phase C plan.

---

## Phase B — Done

End-state of Phase B:

- New `MacAllYouNeed/ClipboardDock/` module with full file layout from spec §4.1 (Phase B subset).
- Bottom-anchored slide-up dock visible on ⌘⇧V; old centered popup removed.
- Polymorphic card system (Text/Image/File/Link/Color/Code) wired to `ClipboardDockModel`.
- Source-app icons with diagonal gradient mask render correctly.
- Image thumbnails load via Phase A's `imageThumbnail` XPC.
- Search works (basic; full top bar with list tabs lands in Phase C).
- All Phase A tests still green; new Phase B model + service tests added.

---

## What comes next

- **Phase C** — Top bar (`DockSearchField` + `DockListTabs` + `DockMoreMenu`), Pinboards CRUD UI, ShortcutRegistry + Settings tab.
- **Phase D** — Multi-select bar, Quick Look, transformations menu, drag-out, color picker.
- **Phase E** — Ignored apps, regex blocklist, storage caps, fuzzy search, frequency tracking, suspend-capture, auto-paste behavior.
- **Phase F** — Snippets surfacing.
