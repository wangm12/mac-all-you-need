# Window Control Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. This plan is mostly sequential after Chunk 1; use subagents only for tasks explicitly marked parallel-safe. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a MAYN-native Window Control tool that supports configurable window action hotkeys, configurable gesture modifiers, native-feeling drag-anywhere movement, edge snapping, restore behavior, and app ignores without copying GPL AnyDrag source or cloning Rectangle's UI.

**Architecture:** Add pure geometry/settings models under `Shared/Sources/Core/WindowControl`, macOS AX/event-tap behavior under `Shared/Sources/Platform/WindowControl`, and feature coordination plus SwiftUI/AppKit UI under `MacAllYouNeed/WindowControl`. `WindowControlCoordinator` mirrors `VoiceCoordinator`'s `@MainActor @Observable` lifecycle, `AppController` owns it, and the existing MAYN settings/hotkey infrastructure remains the source of truth for user configuration. The feature depends on the main app remaining non-sandboxed because it requires an active CGEvent tap.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit, ApplicationServices AX APIs, CGEvent taps, App Group `UserDefaults`, existing MAYN design system primitives, XCTest.

---

## File Map

**Create**
- `Shared/Sources/Core/WindowControl/WindowAction.swift` - keyboard-triggered action enum and metadata.
- `Shared/Sources/Core/WindowControl/WindowControlSettings.swift` - persisted settings value model and defaults.
- `Shared/Sources/Core/WindowControl/WindowGestureModifier.swift` - gesture modifier option set and display helpers.
- `Shared/Sources/Core/WindowControl/WindowGeometryCalculator.swift` - pure rect calculations for MVP actions.
- `Shared/Sources/Core/WindowControl/WindowRestoreHistory.swift` - in-memory restore rect tracking and `WindowIdentity`.
- `Shared/Sources/Core/WindowControl/WindowSnapZone.swift` - edge/corner snap-zone model.
- `Shared/Tests/CoreTests/WindowActionTests.swift`
- `Shared/Tests/CoreTests/WindowControlSettingsTests.swift`
- `Shared/Tests/CoreTests/WindowGeometryCalculatorTests.swift`
- `Shared/Tests/CoreTests/WindowRestoreHistoryTests.swift`
- `MacAllYouNeed/WindowControl/WindowControlCoordinator.swift` - main app feature lifecycle.
- `MacAllYouNeed/WindowControl/WindowControlSettingsStore.swift` - Codable App Group settings store.
- `MacAllYouNeed/WindowControl/WindowControlAccessibilityTrustMonitor.swift` - feature-local AX trust refresh.
- `MacAllYouNeed/WindowControl/WindowControlMainPage.swift` - `Windows` product page.
- `MacAllYouNeed/WindowControl/WindowControlSettingsView.swift` - settings sections.
- `MacAllYouNeed/WindowControl/WindowGestureModifierPicker.swift` - MAYN-native modifier picker.
- `MacAllYouNeed/WindowControl/WindowSnapOverlayPanel.swift` - snap preview panel.
- `MacAllYouNeed/WindowControl/WindowControlDiagnosticsView.swift` - diagnostics UI.
- `MacAllYouNeedTests/WindowControl/WindowControlPresentationTests.swift`
- `MacAllYouNeedTests/WindowControl/WindowControlSettingsStoreTests.swift`
- `MacAllYouNeedTests/WindowControl/WindowControlAccessibilityTrustMonitorTests.swift`

**Create in Platform**
- `Shared/Sources/Platform/WindowControl/WindowAccessibilityElement.swift` - AX wrapper for window frame, role, resizable, fullscreen, sheets, enhanced UI.
- `Shared/Sources/Platform/WindowControl/WindowScreenDetector.swift` - screen, visible-frame, and next/previous-display detection.
- `Shared/Sources/Platform/WindowControl/WindowMover.swift` - size-position-size AX movement.
- `Shared/Sources/Platform/WindowControl/WindowTargetResolver.swift` - CGWindow/AX target lookup.
- `Shared/Sources/Platform/WindowControl/WindowEventTap.swift` - event tap lifecycle and callback routing.
- `Shared/Sources/Platform/WindowControl/NativeTitleBarDragStrategy.swift` - clean-room drag-anywhere behavior.
- `Shared/Tests/PlatformTests/WindowControl/WindowTargetResolverTests.swift` where practical with seams/mocks.
- `Shared/Tests/PlatformTests/WindowControl/WindowMoverTests.swift`
- `Shared/Tests/PlatformTests/WindowControl/WindowScreenDetectorTests.swift`
- `Shared/Tests/PlatformTests/WindowControl/WindowEventTapStateTests.swift`
- `Shared/Tests/PlatformTests/WindowControl/NativeTitleBarDragStrategyTests.swift`

**Modify**
- `Shared/Sources/Platform/Hotkey/HotkeyDescriptor.swift` - add any needed display coverage for default window shortcuts.
- `MacAllYouNeed/Settings/HotkeyMapStore.swift` - migrate to V3 semantics, add grouped window actions, and replace single-default assumptions.
- `MacAllYouNeed/Settings/HotkeysSettingsView.swift` - group hotkeys by feature and support disabled actions.
- `MacAllYouNeed/App/HotkeyRegistry.swift` - register enabled window actions and preserve conflict validation.
- `MacAllYouNeed/App/AppController.swift` - own/suspend/resume `WindowControlCoordinator`.
- `MacAllYouNeed/App/MainAppDestination.swift` - add `windows` and update title/subtitle/symbol/sidebar order switches.
- `MacAllYouNeed/App/MainWindowRoot.swift` - route `.windows` to `WindowControlMainPage`, update dashboard tile rendering as needed.
- `MacAllYouNeed/App/FunctionTabs.swift` - add `WindowControlFunctionTab`; update dashboard tiles, sidebar badges, settings routes, and main shortcut presentation.
- `MacAllYouNeed/Settings/PermissionsSettingsView.swift` - update Accessibility copy.
- `MacAllYouNeedTests/HotkeyMapStoreMigrationTests.swift` - V3 migration and disabled shortcut semantics.
- `MacAllYouNeedTests/Settings/HotkeysSettingsViewPresentationTests.swift` - grouped hotkey UI contract if existing tests do not cover it.
- `MacAllYouNeedTests/App/MainAppDestinationTests.swift`
- `MacAllYouNeedTests/App/FunctionTabsTests.swift`

## Chunk 1: Core Models And Geometry

### Task 1: Add Window Action Model

**Files:**
- Create: `Shared/Sources/Core/WindowControl/WindowAction.swift`
- Test: `Shared/Tests/CoreTests/WindowActionTests.swift`

- [ ] **Step 1: Write failing tests**

Add assertions:

```swift
XCTAssertEqual(WindowAction.leftHalf.title, "Left half")
XCTAssertEqual(WindowAction.restore.symbolName, "arrow.uturn.backward")
XCTAssertTrue(WindowAction.mvpActions.contains(.maximize))
XCTAssertFalse(WindowAction.mvpActions.contains { $0.rawValue == "tileAll" })
```

- [ ] **Step 2: Run RED**

Run:

```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter WindowActionTests
```

Expected: compile fails because `WindowAction` does not exist.

- [ ] **Step 3: Implement minimal action enum**

Create MVP cases:

```swift
public enum WindowAction: String, CaseIterable, Codable, Sendable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case maximize, almostMaximize, center, restore
    case nextDisplay, previousDisplay
}
```

Expose `title`, `symbolName`, and `mvpActions`. Do not define deferred actions such as `tileAll` in this enum yet.

- [ ] **Step 4: Run GREEN**

Run the same `swift test --filter WindowActionTests`. Expected: pass.

### Task 2: Add Gesture Modifier Settings Model

**Files:**
- Create: `Shared/Sources/Core/WindowControl/WindowGestureModifier.swift`
- Create: `Shared/Sources/Core/WindowControl/WindowControlSettings.swift`
- Test: `Shared/Tests/CoreTests/WindowControlSettingsTests.swift`

- [ ] **Step 1: Write failing tests**

Cover:

```swift
XCTAssertFalse(WindowControlSettings.default.enabled)
XCTAssertEqual(WindowControlSettings.default.dragModifier.display, "Option")
XCTAssertEqual(WindowGestureModifier.option.eventFlagsDisplay, "Option")
XCTAssertTrue(WindowGestureModifier([.control, .option]).display.contains("Control"))
```

- [ ] **Step 2: Run RED**

```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter WindowControlSettingsTests
```

Expected: compile fails.

- [ ] **Step 3: Implement settings and modifier model**

Model required settings:

- `enabled`
- `dragAnywhereEnabled`
- `dragModifier`
- `edgeSnapEnabled`
- `edgeSnapRequiresModifier`
- `edgeSnapModifier`
- `doubleClickEnabled`
- `doubleClickModifier`
- `ignoredBundleIDs`
- `titleBarYOffset`
- `debugLoggingEnabled`
- `showSyntheticClickMarker`

Keep default `enabled = false`.

- [ ] **Step 4: Run GREEN**

Run the same test command. Expected: pass.

### Task 2A: Add Window Control Settings Store

**Files:**
- Create: `MacAllYouNeed/WindowControl/WindowControlSettingsStore.swift`
- Test: `MacAllYouNeedTests/WindowControl/WindowControlSettingsStoreTests.swift`

- [ ] **Step 1: Write failing tests**

Cover:

```swift
XCTAssertEqual(WindowControlSettingsStore.load(from: defaults), .default)
var settings = WindowControlSettings.default
settings.enabled = true
WindowControlSettingsStore.save(settings, to: defaults)
XCTAssertEqual(WindowControlSettingsStore.load(from: defaults).enabled, true)
XCTAssertEqual(WindowControlSettingsStore.key, "windowControl.settings.v1")
```

- [ ] **Step 2: Run RED**

```bash
xcodebuild test -quiet -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -configuration Debug -destination 'platform=macOS,arch=arm64' -only-testing:MacAllYouNeedTests/WindowControlSettingsStoreTests
```

Expected: compile fails.

- [ ] **Step 3: Implement store**

Mirror `VoiceActivationSettingsStore` and `VoiceASRSettingsStore`:

- Store one Codable `WindowControlSettings` payload under `windowControl.settings.v1`.
- Expose static `load(from:)` and `save(_:to:)`.
- Save through `AppGroupSettings.defaults` by default.
- Post `com.macallyouneed.settings-changed` after save using the same Darwin notification pattern as existing settings that affect long-running observers.
- Do not scatter raw `AppGroupSettings.defaults.bool(forKey:)` reads through the codebase.

- [ ] **Step 4: Run GREEN**

Run the same test command. Expected: pass.

### Task 3: Add Pure Geometry Calculator

**Files:**
- Create: `Shared/Sources/Core/WindowControl/WindowGeometryCalculator.swift`
- Create: `Shared/Sources/Core/WindowControl/WindowSnapZone.swift`
- Test: `Shared/Tests/CoreTests/WindowGeometryCalculatorTests.swift`

- [ ] **Step 1: Write failing tests**

Use a visible frame:

```swift
let frame = CGRect(x: 0, y: 0, width: 1440, height: 900)
XCTAssertEqual(calc.rect(for: .leftHalf, visibleFrame: frame), CGRect(x: 0, y: 0, width: 720, height: 900))
XCTAssertEqual(calc.rect(for: .topRight, visibleFrame: frame), CGRect(x: 720, y: 0, width: 720, height: 450))
XCTAssertEqual(calc.rect(for: .center, visibleFrame: frame, currentSize: CGSize(width: 800, height: 500))?.origin, CGPoint(x: 320, y: 200))
```

- [ ] **Step 2: Run RED**

```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter WindowGeometryCalculatorTests
```

Expected: compile fails.

- [ ] **Step 3: Implement calculator**

Keep it pure. No AX, no `NSScreen`, no event tap.

Behavior:

- Halves divide visible frame.
- Corners divide visible frame into quarters.
- Maximize returns visible frame.
- Almost maximize returns 90 percent width/height centered.
- Center preserves current size.
- Next/previous display use a separate display-aware API:

```swift
func rectForMovingDisplay(
    currentFrame: CGRect,
    sourceVisibleFrame: CGRect,
    targetVisibleFrame: CGRect
) -> CGRect
```

The function preserves normalized origin and size from source visible frame to target visible frame, then clamps to the target visible frame.

- [ ] **Step 4: Run GREEN**

Run the same test command. Expected: pass.

### Task 3A: Add Restore History

**Files:**
- Create: `Shared/Sources/Core/WindowControl/WindowRestoreHistory.swift`
- Test: `Shared/Tests/CoreTests/WindowRestoreHistoryTests.swift`

- [ ] **Step 1: Write failing tests**

Cover:

```swift
let id = WindowIdentity(pid: 123, cgWindowID: 456, titleHash: nil)
history.store(CGRect(x: 20, y: 20, width: 800, height: 600), for: id)
XCTAssertEqual(history.restoreFrame(for: id), CGRect(x: 20, y: 20, width: 800, height: 600))
XCTAssertNil(history.restoreFrame(for: WindowIdentity(pid: 123, cgWindowID: 999, titleHash: nil)))
```

- [ ] **Step 2: Run RED**

```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter WindowRestoreHistoryTests
```

Expected: compile fails.

- [ ] **Step 3: Implement in-memory history**

Rules:

- key by `WindowIdentity(pid:cgWindowID:titleHash:)`.
- prefer CG window ID when available.
- fallback to PID + title hash + frame only when CG window ID is unavailable.
- keep the store in memory only; clear on app quit.
- cap entries to avoid unbounded growth.

- [ ] **Step 4: Run GREEN**

Run the same test command. Expected: pass.

## Chunk 2: V3 Hotkey Model With Disabled Shortcuts

### Task 4: Migrate HotkeyMapStore To V3

**Files:**
- Modify: `MacAllYouNeed/Settings/HotkeyMapStore.swift`
- Modify: `MacAllYouNeedTests/HotkeyMapStoreMigrationTests.swift`

- [ ] **Step 1: Write failing tests**

Add tests for the new semantics:

```swift
defaults.set(try JSONEncoder().encode(["clipboard": [HotkeyDescriptor]()] ), forKey: HotkeyMapStore.v3Key)
let map = HotkeyMapStore.load(from: defaults)
XCTAssertEqual(map[.clipboard], [])
```

Add migration tests:

- V2 missing key still loads defaults for legacy actions.
- V2 entry with `[]` for `.clipboard` becomes `[.defaultClipboard]` in V3, not disabled.
- V2 entry with `[]` for `.browseFolder` becomes `[.defaultFolder]` in V3, not disabled.
- V3 empty array means disabled for all actions.
- Unknown keys are ignored.
- Existing clipboard/folder hotkeys survive migration.

- [ ] **Step 2: Run RED**

```bash
xcodebuild test -quiet -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -configuration Debug -destination 'platform=macOS,arch=arm64' -only-testing:MacAllYouNeedTests/HotkeyMapStoreMigrationTests
```

Expected: tests fail because V3 does not exist.

- [ ] **Step 3: Implement V3 store**

Add:

- `static let v3Key = "hotkeyMapV3"`
- keep the existing V2 key readable as `hotkeyMapV2`; rename `key` to `v2Key` or leave an alias so tests can seed V2 data explicitly.
- V3 decode path.
- V2 migration path.
- `defaultMap` entries for window actions.
- one-shot persistence of migrated V3 data and deletion of the old V2 key after a successful migration.

Important:

```text
V2 missing action key -> default descriptors
V2 present empty array -> default descriptors for existing V2 actions
V3 missing action key -> default descriptors
V3 present empty array -> disabled
V3 present descriptors -> explicit descriptors
```

- [ ] **Step 4: Run GREEN**

Run the same test command. Expected: pass.

### Task 5: Add Window Hotkey Actions

**Files:**
- Modify: `MacAllYouNeed/Settings/HotkeyMapStore.swift` - `HotkeyAction`, default descriptors, V3 store, and `HotkeyValidation`
- Modify: `MacAllYouNeed/App/HotkeyRegistry.swift`
- Modify: `Shared/Sources/Platform/Hotkey/HotkeyDescriptor.swift`
- Modify: `MacAllYouNeed/App/FunctionTabs.swift`
- Modify: `MacAllYouNeed/Settings/HotkeysSettingsView.swift`
- Test: `MacAllYouNeedTests/HotkeyMapStoreMigrationTests.swift`
- Test: `MacAllYouNeedTests/Settings/HotkeyRecorderTests.swift`
- Test: `MacAllYouNeedTests/App/FunctionTabsTests.swift`
- Test: `MacAllYouNeedTests/Settings/HotkeysSettingsViewPresentationTests.swift` if added in the file map

- [ ] **Step 1: Write failing tests**

Assert labels and defaults:

```swift
XCTAssertEqual(HotkeyAction.windowLeftHalf.label, "Window left half")
XCTAssertEqual(HotkeyAction.windowLeftHalf.defaultDescriptors.count, 1)
XCTAssertEqual(HotkeyAction.windowRestore.defaultDescriptors.count, 1)
XCTAssertEqual(HotkeyAction.windowTopLeft.defaultDescriptors, [])
```

Use conservative defaults but avoid fake required shortcuts. Replace `defaultDescriptor` with:

```swift
var defaultDescriptors: [HotkeyDescriptor]
var primaryDefaultDescriptor: HotkeyDescriptor? { defaultDescriptors.first }
```

Legacy call sites that need a single default should use `primaryDefaultDescriptor` and handle `nil` by showing `Off` or disabling the reset action.

- [ ] **Step 2: Run RED**

Run:

```bash
xcodebuild test -quiet -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -configuration Debug -destination 'platform=macOS,arch=arm64' -only-testing:MacAllYouNeedTests/HotkeyMapStoreMigrationTests -only-testing:MacAllYouNeedTests/HotkeyRecorderTests
```

Expected: compile/test failure.

- [ ] **Step 3: Implement actions**

Add `HotkeyAction` cases:

- `windowLeftHalf`
- `windowRightHalf`
- `windowTopHalf`
- `windowBottomHalf`
- `windowTopLeft`
- `windowTopRight`
- `windowBottomLeft`
- `windowBottomRight`
- `windowMaximize`
- `windowAlmostMaximize`
- `windowCenter`
- `windowRestore`
- `windowNextDisplay`
- `windowPreviousDisplay`

Register them through `HotkeyRegistry` by calling `controller.performHotkeyAction`.

Default descriptors:

- `.clipboard`: `[.defaultClipboard]`
- `.browseFolder`: `[.defaultFolder]`
- `.windowLeftHalf`: Control + Option + Left Arrow
- `.windowRightHalf`: Control + Option + Right Arrow
- `.windowTopHalf`: Control + Option + Up Arrow
- `.windowBottomHalf`: Control + Option + Down Arrow
- `.windowMaximize`: Control + Option + Return
- `.windowCenter`: Control + Option + C
- `.windowRestore`: Control + Option + R
- all other window actions: `[]`

Add arrow key display coverage in `HotkeyDescriptor.keyDisplay` for `kVK_LeftArrow`, `kVK_RightArrow`, `kVK_UpArrow`, and `kVK_DownArrow`.

- [ ] **Step 4: Extend controller dispatch seam**

Add cases to `AppController.performHotkeyAction(_:)` that delegate to `windowControl.perform(action:)`.

Do not register window action hotkeys while `WindowControlSettings.enabled == false`; a disabled feature must not capture global shortcuts. When the feature is enabled or disabled, re-apply the active hotkey registration map.

- [ ] **Step 5: Update validation and presentation fanout**

Update:

- `HotkeyValidation.firstIssue` and duplicate checking to handle empty descriptors as disabled.
- conflict strings to use grouped labels such as `Window Control: Left half`.
- `MainHotkeyPresentation.display(for:)` to handle disabled actions without force-unwrapping a default.
- dashboard tile shortcut presentation so Windows does not render fourteen shortcut chips.
- `HotkeysSettingsView` to group actions by feature and avoid a single flat list of all app commands.
- cache `SystemHotkeyConflictDetector.currentEnabledSymbolicHotkeys()` once per validation/apply pass and pass it into validation helpers instead of letting each call refetch CFPreferences.

- [ ] **Step 6: Run GREEN**

Run the same test command. Expected: pass.

## Chunk 3: MAYN Navigation And UI Shell

### Task 6: Add Windows Destination And Tabs

**Files:**
- Modify: `MacAllYouNeed/App/MainAppDestination.swift`
- Modify: `MacAllYouNeed/App/FunctionTabs.swift`
- Modify: `MacAllYouNeed/App/MainWindowRoot.swift`
- Test: `MacAllYouNeedTests/App/MainAppDestinationTests.swift`
- Test: `MacAllYouNeedTests/App/FunctionTabsTests.swift`

- [ ] **Step 1: Write failing tests**

Assert:

```swift
XCTAssertEqual(
    MainAppDestination.primarySidebarDestinations,
    [.dashboard, .clipboard, .voice, .downloads, .folderPreview, .snippets, .windows]
)
XCTAssertEqual(MainAppDestination.windows.title, "Windows")
XCTAssertEqual(MainAppDestination.windows.subtitle, "Move, snap, and restore windows")
XCTAssertEqual(MainAppDestination.windows.symbolName, "rectangle.3.group")
XCTAssertEqual(WindowControlFunctionTab.storedSelection(nil), .overview)
XCTAssertEqual(WindowControlFunctionTab.storedSelection("gestures"), .gestures)
XCTAssertEqual(DashboardToolSettingsNavigation.route(for: .windows).tabRawValue, WindowControlFunctionTab.settings.rawValue)
let tiles = DashboardToolTilePresentation.dashboardTiles(
    clipboardCount: 0,
    downloadsQueueCount: 0,
    hotkeys: HotkeyMapStore.defaultMap,
    voiceSettings: .default
)
XCTAssertTrue(tiles.contains { $0.destination == .windows })
```

- [ ] **Step 2: Run RED**

```bash
xcodebuild test -quiet -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -configuration Debug -destination 'platform=macOS,arch=arm64' -only-testing:MacAllYouNeedTests/MainAppDestinationTests -only-testing:MacAllYouNeedTests/FunctionTabsTests
```

Expected: compile/test failure.

- [ ] **Step 3: Implement destination and tab enum**

Add `.windows` to `MainAppDestination`.

Update every exhaustive site immediately:

- `MainAppDestination.title`
- `MainAppDestination.subtitle`
- `MainAppDestination.symbolName`
- `MainAppDestination.primarySidebarDestinations`
- `MainWindowRoot.detailView`
- `MainToolHeaderShortcutModel.display(for:)`
- `MainToolHeaderShortcutModel.isEditable(for:)`
- `MainToolHeaderShortcutModel.issue(for:)`
- `DashboardToolTilePresentation.dashboardTiles(...)`
- `DashboardToolSettingsNavigation.route(for:)`
- `MainSidebarBadgePresentation.badgeText(for:)`
- any dashboard tile accent/symbol switch in `MainWindowRoot`

Add:

```swift
enum WindowControlFunctionTab: String, FunctionTabDestination {
    case overview
    case actions
    case gestures
    case settings
}
```

Use shared segmented style only.

- [ ] **Step 4: Route page**

Add `.windows` case to `MainWindowRoot.detailView` and dashboard tile data. Dashboard tile shortcut display should show a compact summary such as `6 active` or the primary shortcut, not a row for every window action.

Discoverability:

- Dashboard must include a Windows tile for existing users.
- Tile copy should announce the new capability without a marketing block, for example `Move, snap, and restore app windows.`
- Tile should surface `Off` or `Needs Accessibility` when relevant and route to Windows -> Overview.

Settings IA decision:

- Do not add `SettingsDestination.windows` in the MVP.
- Do not add a new global Settings sidebar tab for Windows.
- Window Control settings live inside `WindowControlMainPage` -> `WindowControlFunctionTab.settings`.
- If a later deep link is needed, route by selecting `MainAppDestination.windows` plus `WindowControlFunctionTab.settings`.

- [ ] **Step 5: Run GREEN**

Run the same test command. Expected: pass.

### Task 7: Build WindowControlMainPage

**Files:**
- Create: `MacAllYouNeed/WindowControl/WindowControlMainPage.swift`
- Create: `MacAllYouNeed/WindowControl/WindowControlSettingsView.swift`
- Create: `MacAllYouNeed/WindowControl/WindowGestureModifierPicker.swift`
- Create: `MacAllYouNeed/WindowControl/WindowControlDiagnosticsView.swift`
- Test: `MacAllYouNeedTests/WindowControl/WindowControlPresentationTests.swift`

- [ ] **Step 1: Write presentation tests**

Assert static UI contract:

```swift
XCTAssertEqual(WindowControlPagePresentation.tabs.map(\.title), ["Overview", "Actions", "Gestures", "Settings"])
XCTAssertTrue(WindowControlPagePresentation.usesSharedSegmentedTabs)
XCTAssertFalse(WindowControlPagePresentation.usesRawSegmentedPicker)
XCTAssertEqual(WindowControlSettingsPresentation.sectionTitles, ["Shortcuts", "Behavior", "Gestures", "Ignored Apps", "Diagnostics"])
XCTAssertTrue(WindowControlSettingsPresentation.editsShortcutsInToolSettings)
```

- [ ] **Step 2: Run RED**

```bash
xcodebuild test -quiet -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -configuration Debug -destination 'platform=macOS,arch=arm64' -only-testing:MacAllYouNeedTests/WindowControlPresentationTests
```

Expected: compile fails.

- [ ] **Step 3: Implement page with MAYN components**

Use:

- `FunctionPageShell`
- `FunctionSegmentedTabStrip`
- `MAYNSettingsPage`
- `MAYNSection`
- `MAYNSettingsRow`
- `MAYNDropdown`
- `HotkeyRecorderControl`
- `ShortcutChip`
- `StatusPill`
- `MAYNButton`

Do not add nested cards. Keep rows dense and native.

Shortcut editing rules:

- `Actions` tab can display actions and current shortcuts.
- `Actions` tab edit buttons route to the `Settings` tab's `Shortcuts` section.
- `Settings` tab owns `HotkeyRecorderControl` rows for window actions.
- Global Settings -> Hotkeys can show a grouped secondary editor, but the Windows tool must remain the primary shortcut-editing surface for Window Control.

- [ ] **Step 4: Build**

```bash
xcodebuild build -quiet -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -configuration Debug -destination 'platform=macOS,arch=arm64'
```

Expected: build exits 0.

## Chunk 4: Platform AX Movement

### Task 8: Add AX Window Wrapper And Mover

**Files:**
- Create: `Shared/Sources/Platform/WindowControl/WindowAccessibilityElement.swift`
- Create: `Shared/Sources/Platform/WindowControl/WindowMover.swift`
- Create: `Shared/Sources/Platform/WindowControl/WindowScreenDetector.swift`
- Test: `Shared/Tests/PlatformTests/WindowControl/WindowMoverTests.swift`
- Test: `Shared/Tests/PlatformTests/WindowControl/WindowScreenDetectorTests.swift`

- [ ] **Step 1: Add testable seams**

Create protocols for AX get/set frame operations so movement order can be tested without moving real windows.

- [ ] **Step 2: Write failing tests**

Verify:

- `WindowMover` writes size, position, size for resizable windows.
- Fixed-size windows avoid impossible resize when action requires resizing.
- Enhanced UI is disabled and restored around movement when available.
- Keyboard actions use the target window's current display visible frame.
- Next/previous display preserves normalized frame in the target display visible frame.

- [ ] **Step 3: Run RED**

```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter WindowMoverTests
```

Expected: compile fails.

- [ ] **Step 4: Implement wrapper and mover**

Follow Rectangle-compatible behavior conceptually:

- AX frame = position + size.
- Set size before position, then size again.
- Detect sheet/fullscreen/system dialog where practical.
- Return a movement result with proposed and resulting rect.
- Use `WindowScreenDetector` to select the display for keyboard actions from the current window frame, not cursor position.
- Implement next/previous display in `WindowScreenDetector` plus `WindowGeometryCalculator.rectForMovingDisplay(...)`.

- [ ] **Step 5: Run GREEN**

Run the same test command. Expected: pass.

### Task 9: Add Target Resolver

**Files:**
- Create: `Shared/Sources/Platform/WindowControl/WindowTargetResolver.swift`
- Test: `Shared/Tests/PlatformTests/WindowControl/WindowTargetResolverTests.swift`

- [ ] **Step 1: Write pure matching tests**

Test matching CGWindow metadata to AX candidates by PID and frame tolerance.

- [ ] **Step 2: Run RED**

```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter WindowTargetResolverTests
```

Expected: compile fails.

- [ ] **Step 3: Implement resolver**

Behavior:

- Ignore desktop elements and non-layer-0 windows.
- Ignore MAYN overlay/panel windows.
- Ignore menu bar zone.
- Prefer topmost normal window under cursor.
- Return `nil` when uncertain.

- [ ] **Step 4: Run GREEN**

Run the same test command. Expected: pass.

## Chunk 5: Event Tap And Drag Strategy

### Task 10: Add Event Tap Lifecycle

**Files:**
- Create: `Shared/Sources/Platform/WindowControl/WindowEventTap.swift`
- Test: `Shared/Tests/PlatformTests/WindowControl/WindowEventTapStateTests.swift`

- [ ] **Step 1: Write state-machine tests**

Test state transitions without installing a real tap:

- disabled -> start requested without AX -> needs permission.
- active -> tap disabled by timeout -> suspended/retry requested.
- active -> AX revoke -> stopped and pass-through.
- active -> stop -> stopped.
- active -> mouseDown without the configured modifier -> pass-through.
- active -> mouseDown with modifier but no resolved target -> pass-through.
- active -> mouseDown with modifier and ignored frontmost app -> pass-through.

- [ ] **Step 2: Run RED**

```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter WindowEventTapStateTests
```

Expected: compile fails.

- [ ] **Step 3: Implement lifecycle shell**

Add a testable state machine first. Keep actual `CGEvent.tapCreate` behind a small adapter.

Safety rules:

- This must be an active/default tap because drag-anywhere may suppress events. Do not model it on `SnippetExpander`, which uses `.listenOnly`.
- Follow `HotkeyRecorder` for active tap lifecycle: `CGEvent.tapCreate`, `CFRunLoopAddSource`, `CGEvent.tapEnable`, and immediate re-enable on `tapDisabledByTimeout` / `tapDisabledByUserInput`.
- Pass through on uncertainty.
- Suppress only when this predicate is true at mouse-down time:
  `enabled && axTrusted && coordinatorActive && !recordingHotkey && modifierHeld && targetIsNormalNonMAYNWindow && !frontAppIgnored`.
- Returning `nil` swallows the event. In implementation, put the suppress decision behind one named predicate such as `shouldSuppressMouseDown(...)`.
- Handle `tapDisabledByTimeout` and `tapDisabledByUserInput` by moving to `Recovering` or `Error`, surfacing diagnostics, and scheduling a bounded main-actor retry with exponential backoff.
- Do not call AX writes inside hot callback except where explicitly safe.
- Do not block inside the callback on AX writes, locks, disk I/O, settings loads, or expensive allocation.

- [ ] **Step 4: Run GREEN**

Run the same test command. Expected: pass.

### Task 11: Add Clean-Room Native Drag Strategy

**Files:**
- Create: `Shared/Sources/Platform/WindowControl/NativeTitleBarDragStrategy.swift`
- Test: `Shared/Tests/PlatformTests/WindowControl/NativeTitleBarDragStrategyTests.swift`

- [ ] **Step 1: Write observable behavior tests**

Use fake windows, fake event snapshots, and a fake event sink. Assert observable behavior, not the exact AnyDrag event rewrite algorithm:

- Modifier drag on a normal window moves the window origin by the cursor delta.
- Click without drag does not move the window and does not swallow the click.
- Releasing the mouse exits drag state and leaves subsequent events pass-through.
- Losing Accessibility trust during a gesture cancels drag and passes subsequent events through.
- Title-bar offset is configurable and only affects the synthetic drag target abstraction, not public tests.

- [ ] **Step 2: Run RED**

```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter NativeTitleBarDragStrategyTests
```

Expected: compile fails.

- [ ] **Step 3: Implement clean-room strategy**

Implement from behavior, not AnyDrag code. The strategy should receive simple event abstractions where possible so logic stays testable. Do not copy source, comments, method names, or algorithm-specific tests from AnyDrag.

- [ ] **Step 4: Run GREEN**

Run the same test command. Expected: pass.

## Chunk 6: Coordinator Integration

### Task 12: Add WindowControlCoordinator

**Files:**
- Create: `MacAllYouNeed/WindowControl/WindowControlCoordinator.swift`
- Create: `MacAllYouNeed/WindowControl/WindowControlAccessibilityTrustMonitor.swift`
- Modify: `MacAllYouNeed/App/AppController.swift`
- Test: `MacAllYouNeedTests/WindowControl/WindowControlCoordinatorTests.swift`
- Test: `MacAllYouNeedTests/WindowControl/WindowControlAccessibilityTrustMonitorTests.swift`

- [ ] **Step 1: Write coordinator tests**

Use fake tap/mover/settings store:

- starts only when enabled and AX trusted.
- stops when disabled.
- suspends during hotkey recording.
- suppresses actions for ignored app.
- delegates keyboard action to mover.
- stores previous frame before keyboard and snap actions.
- restarts after Accessibility trust changes from denied to granted.
- unregisters or ignores window hotkeys while Window Control is disabled.
- `suspendForHotkeyRecording()` tears down the active tap.
- repeated suspend/resume calls are idempotent.
- keyboard action dispatch starts movement within the latency budget by avoiding storage loads or expensive work on every hotkey fire.

- [ ] **Step 2: Run RED**

```bash
xcodebuild test -quiet -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -configuration Debug -destination 'platform=macOS,arch=arm64' -only-testing:MacAllYouNeedTests/WindowControlCoordinatorTests
```

Expected: compile fails.

- [ ] **Step 3: Implement coordinator**

Mirror `VoiceCoordinator`:

- `@MainActor`
- `@Observable`
- owned by `AppController`
- exposes state for SwiftUI Overview without polling timers
- owns the active tap lifecycle and settings application

Add:

- `start()`
- `stop()`
- `reloadSettings()`
- `suspendForHotkeyRecording()`
- `resumeAfterHotkeyRecording()`
- `perform(action: WindowAction)`
- `refreshAccessibilityTrust()`

Suspension rules:

- `suspendForHotkeyRecording()` is idempotent and tears down the active event tap.
- `resumeAfterHotkeyRecording()` is idempotent and reinstalls the tap only if settings are enabled and AX is trusted.
- The coordinator must not maintain its own recorder counter; `AppController.activeHotkeyRecorderCount` remains the single gate.

Latency budget:

- Hotkey-triggered window movement should start within roughly 50 ms on normal hardware.
- Do not load settings from UserDefaults, fetch symbolic hotkeys, or do AX target discovery work until the action is actually invoked.
- Keep the action dispatch path bounded; rapid repeated actions should not accumulate avoidable main-actor work.

- [ ] **Step 4: Wire AppController**

`AppController` should:

- create `windowControl`
- start it after onboarding/settings load
- route window hotkey actions
- call `windowControl.suspendForHotkeyRecording()` only when `suspendShortcutTriggersForHotkeyRecording()` increments `activeHotkeyRecorderCount` from 0 to 1.
- call `windowControl.resumeAfterHotkeyRecording()` only when `resumeShortcutTriggersAfterHotkeyRecording()` decrements `activeHotkeyRecorderCount` to 0.
- call `windowControl.refreshAccessibilityTrust()` from a feature-local `WindowControlAccessibilityTrustMonitor` after app activation/settings return and while the feature is enabled in Needs Accessibility or Active states.
- re-apply hotkey registration when Window Control enabled state changes so window hotkeys are registered only while the feature is enabled.

Use the existing hotkey recorder observer integration points in `AppController`:

- `hotkeyRecorderStartObserver`
- `hotkeyRecorderStopObserver`
- `suspendShortcutTriggersForHotkeyRecording()`
- `resumeShortcutTriggersAfterHotkeyRecording()`

- [ ] **Step 5: Run GREEN**

Run the same test command. Expected: pass.

## Chunk 7: Snap Overlay And Gesture UX

### Task 13: Add Snap Overlay Panel

**Files:**
- Create: `MacAllYouNeed/WindowControl/WindowSnapOverlayPanel.swift`
- Test: `MacAllYouNeedTests/WindowControl/WindowControlPresentationTests.swift`

- [ ] **Step 1: Write presentation contract tests**

Assert constants:

```swift
XCTAssertEqual(WindowSnapOverlayPresentation.cornerRadius, MAYNControlMetrics.panelRadius)
XCTAssertTrue(WindowSnapOverlayPresentation.respectsReduceMotion)
XCTAssertFalse(WindowSnapOverlayPresentation.usesGlow)
```

- [ ] **Step 2: Run RED**

Run `WindowControlPresentationTests`. Expected: fail.

- [ ] **Step 3: Implement overlay**

Reuse the local floating HUD pattern from `MiniVoiceHUD`, `CopyHUD`, and `FloatingHUDWindowLayering` rather than inventing a new panel stack. Use:

- Borderless non-activating `NSPanel`.
- `ignoresMouseEvents = true`.
- `FloatingHUDWindowLayering.configure(panel, acceptsMouseEvents: false)` where possible.
- `MAYNTheme.progress.opacity(...)`.
- `MAYNMotionBridge` for timing.
- No heavy shadows/glows.

- [ ] **Step 4: Build**

Run the Debug build. Expected: build exits 0.

### Task 14: Wire Snap Gesture

**Files:**
- Modify: `Shared/Sources/Platform/WindowControl/WindowEventTap.swift`
- Modify: `MacAllYouNeed/WindowControl/WindowControlCoordinator.swift`
- Modify: `MacAllYouNeed/WindowControl/WindowSnapOverlayPanel.swift`

- [ ] **Step 1: Add test coverage for snap-zone selection**

Use pure `WindowSnapZone` tests for cursor-to-zone mapping:

- left edge -> left half
- right edge -> right half
- top edge -> maximize
- corners -> quarter actions
- inside safe area -> nil

- [ ] **Step 2: Implement gesture flow**

On drag:

- Resolve target once.
- Track current cursor screen.
- Show overlay when in snap zone.
- Hide overlay outside zone.
- On mouse up in zone, call mover with calculated rect.
- On cancel or no zone, hide overlay and allow drag completion.

- [ ] **Step 3: Manual check**

Build and run. Verify overlay follows zones and does not steal focus.

## Chunk 8: Permissions, Ignored Apps, And Diagnostics

### Task 15: Update Permissions Copy

**Files:**
- Modify: `MacAllYouNeed/Settings/PermissionsSettingsView.swift`
- Test: `MacAllYouNeedTests/Settings/PermissionStatusDisplayTests.swift`

- [ ] **Step 1: Update tests**

Assert Accessibility reason mentions window control in addition to paste/snippets/voice.

- [ ] **Step 2: Run RED**

Run permission display tests. Expected: fail until copy is updated.

- [ ] **Step 3: Update copy**

Keep concise:

```text
Allows pasteback, snippet expansion, voice insertion, and window control in other apps.
```

- [ ] **Step 4: Run GREEN**

Run permission display tests. Expected: pass.

### Task 16: Add Ignored Apps UI

**Files:**
- Modify: `MacAllYouNeed/WindowControl/WindowControlSettingsView.swift`
- Reuse patterns from: `MacAllYouNeed/Settings/SettingsExclusionEditor.swift`
- Test: `MacAllYouNeedTests/Settings/SettingsExclusionListTests.swift`

- [ ] **Step 1: Reuse existing exclusion normalization**

Do not create a new unrelated app-list parser. Use `SettingsExclusionList.normalizedBundleIDs`.

- [ ] **Step 2: Add settings section**

Section title: `Ignored Apps`

Behavior:

- Add running app or app bundle.
- Remove app.
- Show friendly app name.
- Suppress both keyboard window actions and gestures when frontmost app is ignored.

- [ ] **Step 3: Build**

Run Debug build. Expected: build exits 0.

### Task 17: Add Diagnostics

**Files:**
- Modify: `MacAllYouNeed/WindowControl/WindowControlDiagnosticsView.swift`
- Modify: `MacAllYouNeed/WindowControl/WindowControlCoordinator.swift`
- Modify: any logging call sites in Window Control files only

- [ ] **Step 1: Add diagnostics values**

Expose:

- Event tap status.
- Last event-tap failure.
- Last action.
- Proposed rect.
- Resulting rect.
- Title-bar Y offset.
- Debug logging toggle.
- Synthetic click marker toggle.
- Retry count and next retry delay after `tapDisabledByTimeout`.

- [ ] **Step 2: Keep diagnostics isolated**

Do not show diagnostics on Overview unless there is an error. Keep advanced controls in Settings -> Diagnostics.

Use the existing logging utility:

```swift
private let log = Logging.logger(for: "window-control", category: "coordinator")
```

Respect privacy: log bundle IDs, action names, state transitions, and error codes; do not log window titles or user document paths unless the debug toggle is enabled and the value is already visible in the diagnostics UI.

- [ ] **Step 3: Manual check**

Verify diagnostics update after a keyboard action and after a failed gesture.

## Chunk 9: Final Verification

### Task 18: Run Targeted Tests

**Files:** all touched files

- [ ] **Step 1: Shared tests**

Run:

```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test
```

Expected: all tests pass.

- [ ] **Step 2: App targeted tests**

Run:

```bash
xcodebuild test -quiet -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -configuration Debug -destination 'platform=macOS,arch=arm64' -only-testing:MacAllYouNeedTests/HotkeyMapStoreMigrationTests -only-testing:MacAllYouNeedTests/HotkeyRecorderTests -only-testing:MacAllYouNeedTests/FunctionTabsTests -only-testing:MacAllYouNeedTests/MainAppDestinationTests -only-testing:MacAllYouNeedTests/WindowControlPresentationTests -only-testing:MacAllYouNeedTests/WindowControlCoordinatorTests -only-testing:MacAllYouNeedTests/WindowControlSettingsStoreTests -only-testing:MacAllYouNeedTests/WindowControlAccessibilityTrustMonitorTests
```

Expected: all selected tests pass.

- [ ] **Step 3: Full build**

Run:

```bash
./scripts/ci-build.sh
```

Expected: exits 0.

### Task 19: Manual QA Matrix

**Files:** no code edits unless bugs are found

- [ ] **Single display**

Verify:

- Feature off by default.
- Enable requires Accessibility when missing.
- Granting Accessibility after enable starts the coordinator without restarting the app.
- Enabling Window Control activates the default main shortcuts without registering them while the feature is off.
- Drag-anywhere moves Finder, Safari, Chrome, and a SwiftUI app.
- Keyboard actions move the frontmost window.
- Keyboard actions begin movement within roughly 50 ms on normal hardware.
- Empty shortcut arrays disable actions.
- Existing V2 empty arrays for clipboard/folder migrate back to defaults, not disabled.

- [ ] **Multiple displays**

Verify:

- Window action uses the window's current display unless cursor-screen setting is later added.
- Next/previous display preserves visible-frame constraints.
- Display above primary does not get mistaken for menu bar.

- [ ] **System behavior**

Verify:

- Hotkey recording suspends gestures.
- Voice hold-to-talk still works.
- Snippet expansion still works.
- Clipboard popup hotkey still works.
- AX revoke immediately disables Window Control without freezing input.
- Regrant recovers after settings refresh/restart path.

- [ ] **App ignore behavior**

Verify:

- Add ignored app.
- Bring ignored app frontmost.
- Keyboard window actions do nothing.
- Gestures pass through.
- Removing ignored app restores behavior.

### Task 20: Final Review

- [ ] **Diff review**

Confirm:

- No AnyDrag GPL source copied.
- Rectangle-derived code, if any, has MIT attribution.
- No raw segmented pickers introduced for product-owned tabs/settings choices.
- No hardcoded-only hotkeys.
- No unrelated voice/clipboard/downloader refactors.
- Event tap code has pass-through-first behavior.
- Clean-room drag tests assert observable behavior and do not encode AnyDrag's source-level event rewrite sequence.
- `MacAllYouNeed.entitlements` remains non-sandboxed; any sandboxing change is a blocker for this feature until active event tap feasibility is re-evaluated.

- [ ] **Production confidence check**

Ask:

```text
As a responsible senior staff software engineer, am I confident enough to ship this to production with minimal to no bugs?
```

If the answer is not yes, fix the gaps before handoff.
