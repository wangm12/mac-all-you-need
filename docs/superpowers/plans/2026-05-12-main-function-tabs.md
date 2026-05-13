# Main Function Tabs Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure the main app window so first-level navigation is product functions, each function has child tabs, and global settings opens as a floating system surface instead of being mixed into function pages.

**Architecture:** Keep the current `MainWindowRoot` and `SettingsRoot` patterns, but add a small function-tab layer between main destinations and detail content. Move function-specific settings into local tabs. Move global system settings out of the main sidebar and into a floating settings surface opened by a sidebar footer gear, menu bar, or `Cmd+,`.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit, App Group `UserDefaults`, existing `MAYNSettingsUI` primitives, XCTest.

---

## File Map

**Create**
- `MacAllYouNeed/App/FunctionTabs.swift` - reusable child-tab enums/protocol helpers and storage keys.
- `MacAllYouNeed/App/FunctionPageShell.swift` - function header, compact tab strip, and content container.
- `MacAllYouNeedTests/App/FunctionTabsTests.swift` - tab persistence/default mapping tests.

**Modify**
- `MacAllYouNeed/App/MainAppDestination.swift` - remove `settings` from first-level destinations and preserve stored-selection fallback.
- `MacAllYouNeed/App/MainWindowRoot.swift` - add sidebar footer gear, function shells, and tabbed function pages.
- `MacAllYouNeed/App/AppController.swift` - add global settings opening helper if needed.
- `MacAllYouNeed/App/AppMenuBarContent.swift` - route settings and quick actions to main-window deep links where possible.
- `MacAllYouNeed/Settings/SettingsRoot.swift` - keep standalone settings compatible; embedded system settings becomes global-only.
- `MacAllYouNeed/Settings/SettingsDestination.swift` - keep legacy mapping, narrow global group usage where appropriate.
- `MacAllYouNeed/Voice/UI/VoiceDictionaryPage.swift` - allow dictionary page to render as an embedded child tab without a back header.
- `MacAllYouNeedTests/App/MainAppDestinationTests.swift` - update for removed `settings` destination.

## Chunk 1: Main Destination And Function Tab Model

### Task 1: Add Child Tab Persistence Types

**Files:**
- Create: `MacAllYouNeed/App/FunctionTabs.swift`
- Test: `MacAllYouNeedTests/App/FunctionTabsTests.swift`

- [ ] **Step 1: Write failing tests**

Add tests for:

```swift
XCTAssertEqual(ClipboardFunctionTab.storedSelection(nil), .history)
XCTAssertEqual(VoiceFunctionTab.storedSelection("dictionary"), .dictionary)
XCTAssertEqual(VoiceFunctionTab.storedSelection("missing"), .dictate)
XCTAssertEqual(DownloadsFunctionTab.storedSelection("settings"), .settings)
```

- [ ] **Step 2: Run RED**

Run:

```bash
xcodebuild test -quiet -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -configuration Debug -destination 'platform=macOS,arch=arm64' -only-testing:MacAllYouNeedTests/FunctionTabsTests
```

Expected: compile fails because tab types do not exist.

- [ ] **Step 3: Implement tab enums**

Create enums:

- `ClipboardFunctionTab`: `history`, `rules`, `settings`
- `VoiceFunctionTab`: `dictate`, `history`, `dictionary`, `profiles`, `settings`
- `DownloadsFunctionTab`: `queue`, `completed`, `settings`
- `FolderPreviewFunctionTab`: `browse`, `recent`, `settings`
- `SnippetsFunctionTab`: `library`, `settings`

Each enum should expose:

- `storageKey`
- `title`
- `symbolName`
- `storedSelection(_:)`

- [ ] **Step 4: Run GREEN**

Run the same `FunctionTabsTests` command. Expected: pass.

### Task 2: Remove System As A First-Level Product Destination

**Files:**
- Modify: `MacAllYouNeed/App/MainAppDestination.swift`
- Modify: `MacAllYouNeedTests/App/MainAppDestinationTests.swift`

- [ ] **Step 1: Write/update failing tests**

Assert:

```swift
XCTAssertFalse(MainAppDestination.allCases.contains(.settings))
XCTAssertEqual(MainAppDestination.storedSelection("settings"), .dashboard)
```

- [ ] **Step 2: Run RED**

Run:

```bash
xcodebuild test -quiet -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -configuration Debug -destination 'platform=macOS,arch=arm64' -only-testing:MacAllYouNeedTests/MainAppDestinationTests
```

Expected: fails while `.settings` remains a main destination.

- [ ] **Step 3: Update destination enum**

Remove `.settings` from `MainAppDestination`. Keep `storedSelection("settings")` falling back to `.dashboard` so old App Group defaults do not break app launch.

- [ ] **Step 4: Run GREEN**

Run the same test command. Expected: pass.

## Chunk 2: Reusable Function Shell

### Task 3: Add Function Page Shell

**Files:**
- Create: `MacAllYouNeed/App/FunctionPageShell.swift`
- Modify: `MacAllYouNeed/App/MainWindowRoot.swift`

- [ ] **Step 1: Add compile test through existing app build**

Use the Debug build as the compile gate because SwiftUI view rendering is type-checked at build time.

- [ ] **Step 2: Implement shell**

Add:

- `FunctionPageShell(title:subtitle:tabs:selection:toolbar:content:)`
- `FunctionTabStrip`
- `FunctionTabButton`

Keep dimensions stable:

- Tab strip height: about 34 px
- Header spacing: 24 px horizontal
- No nested cards
- Respect `accessibilityReduceMotion` using existing `MAYNMotion`

- [ ] **Step 3: Build**

Run:

```bash
xcodebuild build -quiet -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -configuration Debug -destination 'platform=macOS,arch=arm64'
```

Expected: build exits 0.

## Chunk 3: Clipboard Tabs

### Task 4: Split Clipboard Into History, Rules, Settings

**Files:**
- Modify: `MacAllYouNeed/App/MainWindowRoot.swift`

- [ ] **Step 1: Preserve existing controls**

Move current Clipboard sections:

- `Recent items` -> History
- `Open clipboard dock` -> History toolbar or top row
- `Capture` and excluded apps -> Rules
- shortcut, max items, capture sound, paste behavior -> Settings

- [ ] **Step 2: Persist child tab**

Use:

```swift
@AppStorage(ClipboardFunctionTab.storageKey, store: AppGroupSettings.defaults)
private var selectedClipboardTabRaw = ClipboardFunctionTab.history.rawValue
```

- [ ] **Step 3: Manual check**

Open main window and verify:

- Clipboard defaults to History.
- Rules shows excluded apps.
- Settings shows shortcut and paste behavior.
- Recent image previews still render.

## Chunk 4: Voice Tabs

### Task 5: Split Voice Into Dictate, History, Dictionary, Profiles, Settings

**Files:**
- Modify: `MacAllYouNeed/App/MainWindowRoot.swift`
- Modify: `MacAllYouNeed/Settings/VoiceSettingsView.swift`
- Modify: `MacAllYouNeed/Voice/UI/VoiceDictionaryPage.swift`

- [ ] **Step 1: Extract reusable Voice sections only where needed**

Avoid a broad refactor. Move only the UI needed for local tabs:

- Dictate: state, start/stop, last transcript, setup actions
- Dictionary: existing `VoiceDictionaryPage` in embedded mode
- Profiles: existing `VoiceAppProfilesSection`
- Settings: activation, language, audio, cleanup

- [ ] **Step 2: Make dictionary embeddable**

Add a lightweight initializer option to hide the back button/header if the page is used as a child tab.

- [ ] **Step 3: Keep standalone Voice settings compatible**

If `VoiceSettingsView` is still used from global settings or legacy paths, it should keep working. Prefer sharing sections over deleting the old view in this pass.

- [ ] **Step 4: Manual check**

Verify:

- Voice defaults to Dictate.
- Dictionary appears as a first-class child tab.
- Existing `海涛 -> 江涛` entry appears.
- Voice Settings still writes the same existing activation, ASR, audio, and cleanup defaults.

## Chunk 5: Downloads, Folder Preview, Snippets

### Task 6: Split Remaining Function Pages

**Files:**
- Modify: `MacAllYouNeed/App/MainWindowRoot.swift`

- [ ] **Step 1: Downloads**

Move:

- Queue -> active list and add URL actions
- Completed -> completed/failed rows
- Settings -> concurrency, save location, output template, cookie/downloader status

- [ ] **Step 2: Folder Preview**

Move:

- Browse -> browse/open actions
- Recent -> placeholder or recent folders if available
- Settings -> include hidden, max entries, default view behavior

- [ ] **Step 3: Snippets**

Move:

- Library -> existing `SnippetsListView`
- Settings -> snippet trigger and shortcut hints

- [ ] **Step 4: Build**

Run Debug build. Expected: exit 0.

## Chunk 6: Floating Global Settings

### Task 7: Move System To Floating Settings Entry

**Files:**
- Modify: `MacAllYouNeed/App/MainWindowRoot.swift`
- Modify: `MacAllYouNeed/App/AppMenuBarContent.swift`
- Modify: `MacAllYouNeed/Settings/SettingsRoot.swift`

- [ ] **Step 1: Sidebar footer gear**

Add a footer row in the main sidebar with:

- Settings gear
- optional app version/about icon later

Clicking gear opens the existing global settings scene using `openSettings()`.

- [ ] **Step 2: Keep `Cmd+,` compatible**

Do not remove `SettingsRoot`. It remains the source for `Cmd+,` and menu bar settings.

- [ ] **Step 3: Narrow embedded settings**

Remove `EmbeddedSettingsView` from the main sidebar flow. Keep it only if still needed by other callers.

- [ ] **Step 4: Manual check**

Verify:

- Main sidebar has no System item.
- Gear opens floating settings.
- Menu bar gear opens floating settings.
- `Cmd+,` opens floating settings.

## Chunk 7: Verification

### Task 8: Automated Verification

Run:

```bash
cd /Users/mingjie.wang/Documents/personal/mac-all-you-need/Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test
xcodebuild test -quiet -project /Users/mingjie.wang/Documents/personal/mac-all-you-need/MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -configuration Debug -destination 'platform=macOS,arch=arm64' -only-testing:MacAllYouNeedTests/FunctionTabsTests -only-testing:MacAllYouNeedTests/MainAppDestinationTests -only-testing:MacAllYouNeedTests/VoiceDictionaryPresentationTests
xcodebuild build -quiet -project /Users/mingjie.wang/Documents/personal/mac-all-you-need/MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -configuration Debug -destination 'platform=macOS,arch=arm64'
```

Expected: all commands exit 0. Pre-existing warning output is acceptable only if there are no new errors.

### Task 9: Manual Computer Use Verification

Check:

- Main sidebar: Dashboard, Clipboard, Voice, Downloads, Folder Preview, Snippets only.
- Sidebar gear opens global settings floating surface.
- Clipboard: History, Rules, Settings tabs.
- Voice: Dictate, History, Dictionary, Profiles, Settings tabs.
- Downloads: Queue, Completed, Settings tabs.
- Folder Preview: Browse, Recent, Settings tabs.
- Snippets: Library, Settings tabs.
- Voice Dictionary add/search/edit/delete still works.
- Clipboard image previews still render.
- Existing voice dictation, clipboard dock, downloader, folder preview, and snippets behavior remains unchanged.

