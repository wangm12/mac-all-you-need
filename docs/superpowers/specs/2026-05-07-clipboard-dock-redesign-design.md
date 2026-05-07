# Clipboard Dock Redesign — Design Spec

**Date:** 2026-05-07
**Status:** Draft for review
**Owner:** Mingjie Wang
**Supersedes (UI portion of):** `2026-05-05-mac-all-you-need-design.md` §6 (Clipboard subsystem UI)

## 1. Summary

Replace the existing centered floating popup (`MacAllYouNeed/Clipboard/ClipboardPopup*`) with a Paste-style bottom-anchored dock that slides up from the bottom of the screen on `⌘⇧V`. Adds image previews, source-app indicator with diagonal gradient mask, Pinboards/lists, multi-select & merge-paste, Quick Look, transformations, drag-out, color-picker integration, snippets surfacing, and Maccy-inspired functional improvements (ignored apps, concealed-type respect, regex blocklist, storage caps, fuzzy search, sort-by-frequency, suspend-capture).

Reuses existing infrastructure end-to-end: `PinboardStore`, `SnippetStore`, `BlobStore`, `SearchStore` (FTS5), `GlobalHotkey`, `ExclusionRules`, `PasteboardObserver`, the daemon's encrypted XPC pipeline, and `PreviewDetection` (relocated to `Shared/`). Adds one new module (`MacAllYouNeed/ClipboardDock/`), one new shortcut subsystem, three new XPC methods, three new wire fields on `ClipboardXPCMeta`, and two additive storage migrations.

## 2. Goals & non-goals

### Goals

- Distinct, polished UI on par with Paste's visual language, native to macOS.
- Image previews, source-app indication, and multi-format card rendering.
- All keyboard shortcuts (global triggers + in-dock) user-configurable, multiple bindings per action.
- Privacy-first capture: ignored apps, concealed types, regex blocklist, suspend-capture toggle.
- Bounded storage: max items, max age, max image-blob size, with pinned/listed exemptions.
- View-model-based architecture so each new feature lands as a small focused diff.
- Backward-compatible XPC: a stale daemon does not crash a new app.

### Non-goals (v1 of this redesign)

- Cross-device sync of dock state (Pinboards already serialize via storage; live sync deferred to overall app sync work).
- Snippet rich edit/format (snippets surface as read-list with simple New/Edit/Delete sheet; full editor deferred).
- Shareable Pinboards (Paste's social feature — non-goal in parent spec).
- System-wide color picker (sample any pixel) — defer to v2 of this redesign.
- Syntax-tinted code highlighting in cards / Quick Look — defer to v2.
- Snapshot tests for SwiftUI views.
- Localization beyond English.
- VoiceOver/accessibility audit beyond basic labels and reduced-motion respect.

## 3. Decisions log

| # | Decision | Rationale |
|---|---|---|
| 1 | Maximalist Paste-clone scope (Pinboards + filters + Quick Look + multi-select + transformations + snippets in same UI + drag-out + color picker + Maccy improvements) | Confirmed by user. Phased delivery (§9) makes it tractable. |
| 2 | Full-width bottom-anchored bar, slide-up animation | Confirmed by user. Anchored to screen with cursor (Spotlight heuristic), above macOS Dock, top corners rounded. |
| 3 | Decomposed module + dedicated `@Observable` view-model (`ClipboardDockModel`) | `AppDependencies` is becoming a kitchen sink. A dock-only view-model keeps each sub-feature diff small (CLAUDE.md "minimum code, surgical changes"). |
| 4 | Source-app icon top-right with diagonal gradient mask fading content toward bottom-left | User-specified. Gradient using card-background color (not real `.mask()`) so text reflows naturally and never visually clips. |
| 5 | `⌘⇧V` default trigger, user can add additional triggers/key combos via Settings → Shortcuts | User-specified. Backed by new `ShortcutRegistry` shared by global hotkeys and in-dock shortcuts. |
| 6 | Follow macOS system appearance (no forced dark mode) | User-specified. `NSVisualEffectView` with `.popover` material respects system theme. |
| 7 | New XPC fields on `ClipboardXPCMeta` (sourceAppBundleID, imageWidth/Height, imageBlobID); new XPC methods (imageThumbnail, pasteMany, transformAndCopy) | All wire-additive. Old daemon decoders return nil for new fields; new RPCs degrade gracefully app-side. |
| 8 | Daemon does image thumbnail decrypt + resize + JPEG encode (not the app) | Avoids shipping multi-MB encrypted blob bytes over XPC. Cached daemon-side by `(blobID, maxDim)`. |
| 9 | Pinboards reused for "lists" UI; built-in tabs for History / Pinned / Snippets always present | Existing `PinboardStore` already models named ordered groups. Adds `color: String?` field for tab dot color (additive migration). |
| 10 | Privacy defaults: skip `org.nspasteboard.ConcealedType` and `org.nspasteboard.TransientType`; pre-populated ignored bundle IDs for password managers | Maccy convention. Cheap to add via existing `ExclusionRules`. |
| 11 | Storage caps default OFF for "forever" → defaults set to max items 1000 / max age 30d / max image storage 200 MB; pinned and Pinboard-membership items always exempt | Bounded storage prevents the SQLite DB and blob directory from growing unbounded; exemptions match Maccy semantics. |
| 12 | Auto-paste behavior remains default (current behavior); user can switch to "copy only" or "copy then delayed paste" in Settings | Avoids breaking the existing user habit. Maccy default differs but switching defaults silently would be hostile. |
| 13 | No SwiftUI snapshot tests in v1 | Project has no snapshot infra today; introducing it is unrelated to this redesign and violates "surgical changes". Manual smoke checklist (§8.2) covers visual verification. |
| 14 | Old `MacAllYouNeed/Clipboard/ClipboardPopup*.swift` files deleted (not soft-deprecated) | Single-developer project, no external consumers. CLAUDE.md "no half-finished implementations" — clean replacement. |

## 4. Module structure

### 4.1 New module

```
MacAllYouNeed/ClipboardDock/
├── ClipboardDock.swift                  # Entry point; wires Window + RootView + Model
├── Window/
│   ├── BottomDockWindow.swift           # NSPanel subclass: bottom-anchored, full-width, slide-up
│   └── DockWindowController.swift       # Show/hide lifecycle, outside-click monitor
├── Model/
│   ├── ClipboardDockModel.swift         # @Observable view-model
│   ├── DockItem.swift                   # UI-layer item type
│   └── DockListSelector.swift           # enum: .history | .pinned | .pinboard(RecordID) | .snippets
├── Views/
│   ├── DockRootView.swift               # SwiftUI root: top bar + carousel + multi-select bar
│   ├── DockTopBar/
│   │   ├── DockTopBar.swift
│   │   ├── DockSearchField.swift
│   │   ├── DockListTabs.swift
│   │   └── DockMoreMenu.swift
│   ├── Carousel/
│   │   ├── ClipCarousel.swift
│   │   └── CardSlot.swift
│   ├── Cards/
│   │   ├── ClipCard.swift               # Polymorphic dispatcher
│   │   ├── TextCard.swift
│   │   ├── ImageCard.swift
│   │   ├── FileCard.swift
│   │   ├── LinkCard.swift
│   │   ├── ColorCard.swift
│   │   ├── CodeCard.swift
│   │   └── SourceAppBadge.swift
│   ├── QuickLook/
│   │   └── QuickLookOverlay.swift
│   ├── MultiSelect/
│   │   ├── MultiSelectBar.swift
│   │   └── TransformMenu.swift
│   └── Snippets/
│       └── SnippetsListView.swift
├── Shortcuts/
│   ├── ShortcutAction.swift             # enum of all action IDs
│   ├── ShortcutBinding.swift            # struct: keyEquivalent + modifierFlags
│   ├── ShortcutRegistry.swift           # @Observable: action → [bindings]
│   ├── ShortcutDefaults.swift           # default binding per action
│   └── ShortcutRecorder.swift           # SwiftUI control for capturing a key combo
└── Services/
    ├── AppIconResolver.swift            # bundleID → NSImage (cached)
    ├── ImageBlobLoader.swift            # XPC imageThumbnail → cached NSImage
    ├── DockAnimator.swift               # NSPanel position/alpha animation helpers
    └── DockPasteCoordinator.swift       # Single & multi-paste via XPC
```

### 4.2 Modified existing files

- `Shared/Sources/Core/XPC/ClipboardXPCProtocol.swift` — new fields on `ClipboardXPCMeta`; new methods on `ClipboardXPCProtocol`.
- `Shared/Sources/Core/Storage/Migrations.swift` — add migration 002 (frequency tracking columns).
- `Shared/Sources/Core/Models/Pinboard.swift` — add `var color: String?`.
- `Shared/Sources/Core/Storage/ClipboardStore.swift` — read/write new columns; add `bumpFrequency(id:)` and `recentByFrequency(...)` methods.
- `Shared/Sources/Platform/Pasteboard/ExclusionRules.swift` — extend with user-configurable bundle ID set, regex patterns, concealed/transient type checks.
- `Shared/Sources/UI/PreviewDetection.swift` — new file (extracted from `MacAllYouNeed/Clipboard/PasteboardPreview.swift`).
- `ClipboardDaemon/ClipboardXPCServer.swift` — implement `imageThumbnail`, `pasteMany`, `transformAndCopy`; populate new `ClipboardXPCMeta` fields.
- `ClipboardDaemon/DaemonContainer.swift` — read settings (max items, max age, image cap, ignored apps, regex patterns, suspend-until) from app group `UserDefaults`; nightly retention task.
- `MacAllYouNeed/App/AppDependencies.swift` — shrink: drop `recentItems` and `activeQuery`; expose `dockModel`, `pinboardStore`, `snippetStore`.
- `MacAllYouNeed/App/AppController.swift` — instantiate `DockWindowController` instead of `ClipboardPopupController`.
- `MacAllYouNeed/Settings/...` — new Settings tabs: Shortcuts, Privacy, Storage, Appearance (menu icon, dock height).

### 4.3 Deleted files

- `MacAllYouNeed/Clipboard/ClipboardPopupController.swift`
- `MacAllYouNeed/Clipboard/ClipboardPopupView.swift`
- `MacAllYouNeed/Clipboard/ClipboardItemRow.swift`
- `MacAllYouNeed/Clipboard/PasteboardPreview.swift` (logic relocated to `Shared/Sources/UI/PreviewDetection.swift`)
- `MacAllYouNeed/Clipboard/HotkeyController.swift` survives (rebound through `ShortcutRegistry` for `.openDock`).

## 5. Window: shape, anchoring, animation

- `BottomDockWindow: NSPanel` with `canBecomeKey = true`, `canBecomeMain = false`.
- Style mask: `[.borderless, .nonactivatingPanel, .fullSizeContentView]` — non-activating preserves frontmost-app focus so subsequent paste lands in the original target.
- Anchored to bottom edge of the screen the **mouse cursor is on** (multi-monitor: `NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }` with `NSScreen.main` fallback).
- Geometry: full `screen.visibleFrame.width` × `dockHeight` (default 360pt, range 300–500pt in Settings) at `screen.visibleFrame.minY` (above macOS Dock).
- Top corners rounded 12pt (`layer.maskedCorners`); bottom corners square.
- Background: `NSVisualEffectView` material `.popover`, blending `.behindWindow`, state `.active` — respects system appearance.
- Window level `.floating`; `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`.
- Slide-up: 0.22s ease-out (`CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)`), origin.y from `screen.visibleFrame.minY - dockHeight` to `.minY`, alpha 0 → 1. Search field gains focus on completion.
- Slide-down: 0.18s ease-in, reverse. `orderOut` on completion.
- Reduced-motion: `accessibilityDisplayShouldReduceMotion` collapses animations to instant alpha cross-fade.
- Re-trigger while open: dismiss (toggle).
- Dismissal triggers: `Esc` (after clearing search), outside click, re-press of trigger, after successful single paste, `NSWorkspace.willSleepNotification`.

## 6. State model & data flow

### 6.1 `ClipboardDockModel`

```swift
@MainActor @Observable
final class ClipboardDockModel {
    let xpc: ClipboardXPCInteracting       // protocol; mockable in tests
    let pinboardStore: PinboardStore
    let snippetStore: SnippetStore
    let appIcons: AppIconResolver
    let imageLoader: ImageBlobLoader

    var activeList: DockListSelector = .history
    var availableLists: [Pinboard] = []
    var search: String = ""
    var items: [DockItem] = []
    var focusedIndex: Int = 0
    var selection: Set<DockItem.ID> = []
    var isQuickLooking: Bool = false
    var pendingTransform: TransformKind? = nil

    func refresh() async                                    // debounced 100ms
    func paste(_ id: DockItem.ID, plainText: Bool) async
    func pasteSelectionInOrder(delimiter: String, plainText: Bool) async
    func togglePin(_ id: DockItem.ID) async
    func delete(_ ids: Set<DockItem.ID>) async
    func addToPinboard(_ ids: Set<DockItem.ID>, board: RecordID) async
    func applyTransform(_ kind: TransformKind, to ids: Set<DockItem.ID>) async
    func startDrag(_ id: DockItem.ID, providerOnto pasteboard: NSPasteboard)
}
```

### 6.2 `DockItem`

```swift
struct DockItem: Identifiable, Hashable {
    let id: String
    let modified: Date
    let kind: DockItemKind        // .text|.image(w,h,blobID)|.file([URL])|.link(URL)|.color(NSColor)|.code(lang)|.rtf
    let preview: String
    let sourceApp: SourceApp?
    let isPinned: Bool
}

struct SourceApp: Hashable {
    let bundleID: String
    let displayName: String
    let icon: NSImage?            // 32×32 cached
}
```

`DockItemKind` derived from `ClipboardXPCMeta.kind` + `PreviewDetection`.

### 6.3 XPC protocol additions

```swift
@objc public class ClipboardXPCMeta: NSObject, NSSecureCoding {
    @objc public let id, kind, preview: String
    @objc public let modified: Date
    @objc public let sourceAppBundleID: String?    // NEW
    @objc public let imageWidth: Int               // NEW (0 if non-image)
    @objc public let imageHeight: Int              // NEW
    @objc public let imageBlobID: String?          // NEW
}

@objc public protocol ClipboardXPCProtocol {
    // Existing methods unchanged…

    func imageThumbnail(forID id: String, maxDim: Int, reply: @escaping (Data?) -> Void)
    func pasteMany(itemIDs: [String], delimiter: String, plainText: Bool,
                   reply: @escaping (String) -> Void)
    func transformAndCopy(itemID: String, transform: String,
                          saveAsNew: Bool, reply: @escaping (String?) -> Void)
    func pasteText(text: String, plainText: Bool, saveAsNew: Bool,
                   reply: @escaping (String) -> Void)
}
```

`pasteText` serves two callers that don't have a clipboard-record ID: snippet pasting (snippet body → pasteboard → ⌘V) and transformation pasting where the user picked "Apply" without "Save as new clip". `saveAsNew=true` round-trips through `ClipboardStore.append` so the action shows up in history.

For testability, the existing `ClipboardXPCClient` is extracted to a protocol `ClipboardXPCInteracting` covering exactly the methods `ClipboardDockModel` calls (no breaking signature changes; same protocol the daemon already implements). The model holds `let xpc: any ClipboardXPCInteracting` and unit tests pass a `MockXPCClient` conforming to it.

### 6.4 `AppDependencies` shrinkage

Drops `recentItems`, `activeQuery`, `refresh*`, `clearRememberedQuery`. Keeps XPC client; gains `dockModel`, `pinboardStore`, `snippetStore`. `itemsInvalidated()` callback proxies to `dockModel.refresh()`.

### 6.5 Single-paste flow

```
⌘⇧V → HotkeyController → DockWindowController.show()
  → BottomDockWindow becomes key, slides up
  → ClipboardDockModel.refresh()
User selects → Enter
  → DockWindowController.hide() (slide down begins)
  → DockPasteCoordinator → xpc.paste(itemID:plainText:reply:)
  → daemon writes pasteboard, runs PasteInjector ⌘V
```

Source app of the paste **target** is preserved because the dock is non-activating.

## 7. Card system & source-app gradient

### 7.1 Card geometry

- 220×240pt default (Settings: 180–280pt height).
- Header strip 24pt: kind chip ("Text"/"Image"/"1 file"/"Link") + modified-relative ("2 minutes ago").
- Footer strip 28pt: char count or file size + ⌘N shortcut hint + format-toggle hint (`A→A`).
- Rounded corners 10pt; selection ring 2pt accent stroke; multi-select checkmark badge top-left.

### 7.2 Polymorphic dispatcher

`ClipCard` switches on `item.kind` to one of TextCard / ImageCard / FileCard / LinkCard / ColorCard / CodeCard. RTF reuses TextCard with an "RTF" chip.

### 7.3 Per-kind behaviors

- **TextCard**: `Text(preview).lineLimit(8)`, monospace if `PreviewDetection` flags code.
- **ImageCard**: `ImageBlobLoader.thumbnail(blobID, maxDim: 220)` async; skeleton shimmer placeholder; broken-image SF symbol on error; NSCache 50 entries.
- **FileCard**: Finder icon for first file; filename middle-truncated; "+ N more" if `urls.count > 1`; size async if `< 100MB`.
- **LinkCard**: favicon (16pt) + host + truncated URL. `FaviconCache` does HEAD `https://{host}/favicon.ico` with `NSURLCache` 24h TTL; fallback `link` SF symbol.
- **ColorCard**: 140×120 swatch + monospace hex.
- **CodeCard**: monospace, language tag in header chip; single-color render in v1.

### 7.4 `SourceAppBadge` — top-right icon with diagonal gradient mask

```swift
struct SourceAppBadge: View {
    let app: SourceApp?
    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Diagonal gradient: card-background color fades in toward top-right
            // so underlying text fades into the card instead of clipping.
            LinearGradient(
                stops: [
                    .init(color: .clear,                       location: 0.0),
                    .init(color: cardBackground.opacity(0.0),  location: 0.5),
                    .init(color: cardBackground.opacity(0.85), location: 0.85),
                    .init(color: cardBackground,               location: 1.0),
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

Rationale: a real `.mask()` erases pixels and reads as broken; a gradient overlay using card-background color fades text into the card so it never clips and reflows on resize.

### 7.5 `AppIconResolver`

Per-session in-memory cache `[bundleID: NSImage]`. Resolves via `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)` then `NSWorkspace.shared.icon(forFile:)`. Display name via `Bundle.object(forInfoDictionaryKey:)`. No eviction (bounded by ~30 unique apps in typical use).

## 8. Top bar

### 8.1 `DockSearchField`

- Collapsed magnifying-glass icon (28×28) at leading edge; expands to 320pt rounded text field on click or `⌘F`.
- Auto-collapses when empty and unfocused.
- Backed by `model.search`; debounced 120ms; scoped to active list.
- Placeholder reflects active list ("Search Clipboard History…", etc.).
- `Esc`: clears query first, then dismisses dock on second press.

### 8.2 `DockListTabs`

- Built-in tabs always present, in order: `Clipboard History` (default), `Pinned`, `Snippets`.
- User Pinboards rendered after built-ins, each with colored dot (from `Pinboard.color`). Reorderable via drag.
- Trailing `+` opens inline rename popover with color swatch grid → `pinboardStore.create(name:color:)`.
- Right-click context menu: Rename, Change Color, Delete, Move Left/Right, Set as Default.
- Active tab: filled background; inactive: text + hover-fill.
- Switching tab clears search, resets focus to 0.

### 8.3 `DockMoreMenu` (⋯)

Items (disabled when not applicable, never hidden):

- Open Settings… (`⌘,`)
- Pin Selected (`⌘P`)
- Add Selected to List ▶ (existing Pinboards + "+ New List…")
- Transform ▶ (Lowercase, Uppercase, Title Case, Trim, Pretty/Minify JSON, Strip HTML, Base64 ±, URL-encode ±, Sort lines, Dedupe lines, Count stats)
- Copy as Plain Text (`⌥` on paste)
- Quick Look (`Space`)
- Drag Out
- Privacy ▶ (Ignored Apps…, Clear All History, Clear Older Than… 1d/7d/30d/90d)
- Snippets ▶ (New Snippet…, Manage Snippets…)
- About Mac All You Need

### 8.4 Default in-dock shortcut bindings

All overridable via `ShortcutRegistry` (§9).

| Action | Default |
|---|---|
| `.focusSearch` | `⌘F` |
| `.pasteAtIndex(N)` | `⌘1`–`⌘9` |
| `.switchListAtIndex(N)` | `⌘⇧1`–`⌘⇧9` |
| `.togglePin` | `⌘P` |
| `.addToList` | `⌘L` |
| `.deleteFocused` | `⌘⌫` |
| `.quickLook` | `Space` |
| `.cycleFocus` | `Tab` |
| `.dismiss` | `Esc` |
| `.paste` | `Enter` |
| `.pastePlain` | `⌥+Enter` |
| `.extendSelectionLeft/Right` | `⇧+←/→` |
| `.jumpToFirst/Last` | `⌘+←/→` |
| `.toggleCheatsheet` | `⌘?` |
| `.transformFocused` | `⌘T` |

## 9. `ShortcutRegistry`

Two scopes, one registry. Global triggers go to `Shared/Sources/Platform/Hotkey/GlobalHotkey.swift`; in-dock shortcuts attach via SwiftUI `.keyboardShortcut(_:)` where possible, or `.onKeyPress { registry.matches(event, .actionID) }` for combos SwiftUI can't model.

- One action → many bindings (user can add additional triggers).
- Persistence: `UserDefaults(suiteName: AppGroup.identifier)` keyed `"shortcut.<actionID>"` with JSON-encoded `[ShortcutBinding]`. App group so daemon reads trigger bindings without IPC.
- Reset restores `ShortcutDefaults`.
- Settings UI: "Shortcuts" tab, two sections (Global Triggers, In-Dock Shortcuts); each row has action name, current bindings, `+` to add, `⌫` to remove, `Reset`. `ShortcutRecorder` captures keypress and validates non-conflict before assignment.
- Conflict policy: in-dock shortcuts cannot be `Esc`/`Enter`/`Tab`/plain `Space`/plain arrows. Global triggers cannot duplicate macOS system combos (best-effort warning, allow override).

## 10. Power-user features

### 10.1 Multi-select

- `⇧+←/→` extends contiguous range.
- `⌘+click` toggles single item.
- `⇧+click` extends to clicked item.
- `⌘A` selects all visible (cap 50).
- Selection clears on list/search/dismiss change.

`MultiSelectBar` slides up from bottom of dock when `selection.count >= 1` (44pt, 50ms ease-out): "N selected · [Paste] [Paste plain] [Pin] [Add to list ▾] [Transform ▾] [Delete] [✕]".

`pasteMany` daemon-side: reads each item's plain-text representation (image kind skipped with warning), joins with delimiter, writes once to pasteboard, single `PasteInjector.paste`. Default delimiter `\n`; Settings configurable.

### 10.2 Quick Look

In-dock overlay (not separate window) on `Space`. 0.15s fade. Top bar remains visible.

- Text/Code/RTF: scrollable `NSTextView`, monospace if code, char/line counts in footer.
- Image: full-resolution via `imageThumbnail(maxDim: 0)` (0 = original); pinch + scroll-to-zoom; dimensions and file size in footer.
- File(s): scrollable list of paths; double-click opens in Finder via `NSWorkspace.shared.activateFileViewerSelecting`.
- Link: favicon + host + URL, click opens in default browser. OG image fetch deferred.
- Color: full-card swatch + hex/RGB/HSL.

`Space`/`Esc` dismisses overlay (Esc otherwise dismisses dock — overlay intercepts when active). Arrow keys cycle through items while overlay stays open.

### 10.3 Transformations

v1 transforms (text-only, no-op on non-text): Lowercase, Uppercase, Title Case, Trim, Strip HTML, Pretty/Minify JSON, Base64 ±, URL-encode ±, Sort lines, Dedupe lines, Count stats (popover only).

Per-action toggle: "Apply" (replaces pasteboard write) vs "Save as new clip". Default: paste transformed AND save as new clip with source app `com.macallyouneed.app`. Routed via `transformAndCopy` XPC.

### 10.4 Drag-out

Each card supports `.draggable(...)` returning the appropriate `Transferable`: `String` for text/code, `URL` for link, `NSImage` for image, `[URL]` for files, hex `String` for color. Dock does not auto-dismiss for 800ms during a drag (tracked via `NSDraggingSession`).

### 10.5 Color picker integration

`C` on focused color card cycles RGB → HSL → hex. Context menu "Open in Color Picker" launches `NSColorPanel` with `selectedColor` set; user-adjusted color writes back as new clip.

### 10.6 Snippets surfacing

`activeList == .snippets` renders `SnippetsListView`. Snippet cards: name title, body preview, trigger pattern in chip if set. Enter pastes body via the new `pasteText(text:plainText:saveAsNew:reply:)` XPC method (saveAsNew=true so the snippet usage shows up in history with the app as source). The existing `SnippetExpander` keeps its job (in-app trigger expansion); dock-initiated snippet paste does not go through it. "+ New Snippet" leading edge of carousel opens sheet (name + body + optional trigger). Right-click: Edit / Duplicate / Delete.

### 10.7 Cheatsheet (`⌘?`)

Translucent overlay listing every active shortcut by category, pulled live from `ShortcutRegistry`.

## 11. Maccy-inspired functional improvements

### 11.1 Ignored apps

Settings → Privacy → "Don't capture from these apps" multi-picker. Stored in app-group `UserDefaults` as `Set<String>` of bundle IDs. Read by `ExclusionRules` (already accepts `appBundleID`). Defaults pre-populate password manager bundle IDs (`com.apple.keychainaccess`, `com.1password.*`, `com.lastpass.LastPass`, `com.bitwarden.desktop`, `com.agilebits.onepassword*`, `com.dashlane.Dashlane`).

### 11.2 Concealed-type respect

`ExclusionRules` drops changes whose types include `org.nspasteboard.ConcealedType`, `org.nspasteboard.TransientType`, `com.apple.PasswordManager`. Settings toggle (default ON).

### 11.3 Regex blocklist

Settings → Privacy → "Don't capture text matching" — list of user regex patterns. Pre-populated suggestions (off by default): credit card shape, JWT shape, AWS access key shape, Bearer token shape. Bad regex caught at edit time via `try NSRegularExpression`. Evaluated daemon-side post-read, pre-persist.

### 11.4 Storage caps

Defaults: max items 1000 (range 100–10 000), max age 30d (forever / 7d / 30d / 90d / 365d), max image storage 200 MB. Eviction transactional in batches of 50 oldest non-pinned/non-listed items. Nightly `DispatchSourceTimer` in daemon for max-age. Pinned and Pinboard-membership items always exempt.

### 11.5 Sort by frequency

Additive migration adds `frequency: Int (default 0)` and `last_accessed: Int?` columns. `paste()` increments frequency and sets `last_accessed`. Settings "Sort history by": Recency (default) / Frequency / Recently used. Pinboards keep explicit user order; Pinned tab always sorts by recency-of-pin.

### 11.6 Fuzzy search

Settings "Search style": Exact (FTS5, default) / Fuzzy. Fuzzy builds in-memory char-trigram index over loaded items, ranks by match score. No DB schema change. Subtle ranking dot in fuzzy results.

### 11.7 Sound on capture

Settings (default OFF): "Play sound when capturing". `NSSound(named: .pop)` daemon-side.

### 11.8 Menu-bar icon

Settings → Appearance: SF Symbols (`doc.on.clipboard`, `clipboard`, `square.on.square`, `tray`) or custom monochrome PNG.

### 11.9 Suspend capture

Menu item + `.suspendCapture` shortcut (no default binding) pauses capture for 60s. Daemon reads paused-until timestamp from app-group `UserDefaults` at each tick.

### 11.10 Auto-paste behavior

Settings "When picking an item": Paste into focused app (default — current behavior) / Just copy to clipboard / Both — copy then paste after Nms (configurable delay).

## 12. Testing

### 12.1 Unit tests in `Shared/Tests/`

- `PreviewDetection` — extend existing-style tests for color/url/code/plain.
- `ExclusionRulesTests` — extend with ignored bundle IDs from settings, concealed types, regex (valid/invalid/match/non-match).
- `RetentionPolicyTests` (new) — max-items, max-age, image-cap, pinned/listed exemptions.
- `FrequencySortTests` (new) — sort-mode ordering.
- `FuzzySearchTests` (new) — char-trigram ranking stable over fixtures.

### 12.2 Unit tests in `MacAllYouNeedTests/`

- `ClipboardDockModelTests` — refresh debounce, list switching, multi-select, pasteSelectionInOrder, togglePin. Uses `ClipboardXPCInteracting` mock.
- `ShortcutRegistryTests` — round-trip persistence, conflict detection, `matches(event:action:)`, default restoration.
- `AppIconResolverTests` — caching with mock `NSWorkspace` wrapper.
- `ImageBlobLoaderTests` — caching keyed by `(blobID, maxDim)`, mock XPC.

### 12.3 XPC contract tests

Extend `Shared/Tests/CoreTests/XPC/ClipboardXPCContractTests.swift`: backward-decoding for legacy `ClipboardXPCMeta` payloads (new fields decode to nil/0). Forward-decoding for new fields.

### 12.4 Daemon integration tests

Extend `CoreIntegrationTests` pattern: `imageThumbnail` (encrypted blob → decrypt → resize → JPEG round-trip), `pasteMany` (order/join/skip-images), `transformAndCopy` (per-fixture).

### 12.5 No SwiftUI snapshot tests

Project has no snapshot infra; introducing it is unrelated to this redesign.

### 12.6 Manual smoke checklist (per phase merge)

1. ⌘⇧V opens dock with slide-up; ⌘⇧V dismisses.
2. Multi-monitor: dock follows cursor screen.
3. Reduced-motion: no slide.
4. Copy in Chrome → card shows Chrome icon top-right with gradient fade.
5. Copy image → image card renders thumbnail < 200ms.
6. Copy file in Finder → file card shows Finder icon + name.
7. Search "git" filters live across types.
8. Create Pinboard, drag card onto its tab, switch tab, verify item.
9. Multi-select 3 items, Paste → joined output with newline delimiter.
10. Image card + Space → Quick Look full-size; arrows cycle.
11. Right-click text → Transform → Pretty JSON → new clip at front.
12. Drag card into TextEdit → drop works; dock stays open during drag.
13. Settings → Privacy → ignore Chrome → copy in Chrome → no card.
14. Settings → Shortcuts → rebind Pin to ⌘B → ⌘B pins focused card.
15. Copy from Keychain Access → no card (concealed type).
16. Storage cap reached → oldest non-pinned items vanish from history.

## 13. Storage migrations

One additive migration in `Shared/Sources/Core/Storage/Migrations.swift`:

1. `Migration("002-frequency-tracking")` — `ALTER TABLE clipboard_records ADD COLUMN frequency INTEGER NOT NULL DEFAULT 0`, `ADD COLUMN last_accessed INTEGER NULL`. Required for the sort-by-frequency query (denormalized — can't read from inside encrypted envelope).

Pinboard color does NOT need a schema migration: `Pinboard.color: String?` is added to the Codable struct and stored inside the existing encrypted `envelope` blob. Default `Codable` decoding maps missing keys to `nil` for Optional types, so existing pinboards decode cleanly with `color = nil` (UI renders default dot color).

No migration for ignored-app/regex/storage-cap settings — they live in `UserDefaults` and default values apply on first read.

Storage-cap accounting: image-storage byte total is computed by summing file sizes under `BlobStore.directory` via `FileManager.default.attributesOfItem(atPath:)[.size]`, cached in-memory and recomputed on insert/delete (cheap because a typical user has < 1 000 image blobs). Eviction picks oldest-by-modified non-pinned/non-listed image clip and deletes both the row and its blob file.

## 14. XPC version skew

Daemon and main app are signed and shipped together but installed/restarted independently.

- `ClipboardXPCMeta` decoder uses `decodeObject(of: NSString.self, forKey: "sourceAppBundleID")` returning nil if missing — fine.
- New methods on `ClipboardXPCProtocol` are guarded app-side via `xpc.connection.remoteObjectProxyWithErrorHandler { _ in cont.resume(returning: <degraded>) }`. Image cards show placeholder; multi-paste falls back to single-paste of first item; transformAndCopy disabled with toast.
- After app update, `DaemonContainer.unregisterAndReregister()` (existing pattern from commit `747221c`) bounces the daemon at next launch.

## 15. Implementation phasing

Six independently shippable, bisectable phases. Each lands behind a green-light criterion (relevant manual smoke checks + tests).

- **Phase A — Plumbing.** XPC additions (`sourceAppBundleID` field, `imageThumbnail`, `pasteMany`, `transformAndCopy`), daemon implementations, contract tests. No UI changes.
- **Phase B — Visual overhaul.** New `ClipboardDock` module skeleton, `BottomDockWindow` + slide-up animation, polymorphic `ClipCard` system (Text/Image/File/Link/Color/Code), `SourceAppBadge` with gradient. Replaces old popup. ⌘⇧V works end-to-end with new UI.
- **Phase C — Top bar & Pinboards.** `DockTopBar`, `DockListTabs`, list-switching, `+` new list, `ShortcutRegistry` + Settings tab.
- **Phase D — Power features.** multi-select bar, `pasteMany` wired, Quick Look overlay, transformations menu, drag-out, color-picker actions.
- **Phase E — Maccy improvements.** ignored apps + concealed-type respect, regex patterns, storage caps, fuzzy search toggle, sort-by-frequency, suspend-capture, auto-paste behavior toggle.
- **Phase F — Snippets surfacing.** `.snippets` tab in dock, snippet CRUD sheet.

## 16. Open questions / deferred to v2

- Syntax-tinted code highlighting in CodeCard and Quick Look.
- Rich link previews (OG image fetch, embedded title).
- System-wide color sampler (any pixel on screen).
- Shareable Pinboards / cloud-shared lists.
- Snapshot tests for SwiftUI views (full infra TBD).
- Rich snippet editor (tags, variables, scripted snippets).
- Cross-device live dock state sync (uses parent spec's sync engine when implemented).
- VoiceOver / accessibility audit beyond basic labels and reduced-motion.
