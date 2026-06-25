# AGENTS.md

Behavioral and project-specific guidance for agents working in this repo.

> **Note:** The coding behavioral guidelines in sections 1–5 below are derived
> from and should stay in sync with the user's global `~/.claude/CLAUDE.md`.
> That file is the canonical source. This file adds project-specific context
> (architecture, UI rules, platform decisions) on top.

## User Preferences

- Always address the user as **mingjie-father**.

## 1. Think Before Coding

Don't assume. Don't hide confusion. Surface tradeoffs.

Before implementing:

- State assumptions explicitly when they matter.
- If multiple interpretations exist, present them instead of silently picking.
- If a simpler approach exists, say so.
- If something is unclear and cannot be discovered from the repo, ask.

## 2. Simplicity First

Minimum code that solves the problem. Nothing speculative.

- No features beyond what was asked.
- No abstractions for single-use code.
- No configurability that was not requested.
- No unrelated cleanup while editing nearby code.
- If a change can be smaller and clearer, make it smaller.

## 3. Surgical Changes

Touch only what the task requires.

- Match the existing style and ownership boundaries.
- Do not refactor adjacent code unless it is required for the requested change.
- Remove only imports/variables/functions made unused by your changes.
- Do not revert unrelated dirty-worktree changes.

Every changed line should trace to the user's request.

## 4. Goal-Driven Execution

Transform tasks into verifiable goals:

1. Identify the source of truth in code/docs.
2. Make the smallest necessary change.
3. Verify with the narrowest useful command.

For multi-step work, keep a brief plan and update it as work completes.

## 5. Production Confidence Check

Before handing back, ask:

> As a responsible senior staff software engineer, am I confident enough to ship this to production with minimal to no bugs?

If the answer is not yes, identify the gap, fix it or report the exact residual
risk, then re-check.

---

# Mac All You Need - Developer Context

## Project

Native macOS productivity app built with Swift 5.9+, SwiftUI, AppKit, GRDB,
libarchive, FluidAudio, and yt-dlp/ffmpeg. The app is menu-bar resident but also
has a Dock/main-window flow.

Current first-class tool surfaces (11 total):

- **Clipboard** - encrypted clipboard history, local direct reads, searchable
  main history, `Command-Shift-V` dock/popup, capture rules, paste behavior,
  pinboards, multi-select, transforms, Quick Look, and app exclusions.
- **Voice** - dictation into any app, local Qwen3-ASR, optional Groq Whisper,
  cleanup, transcript history, dictionary, personalization profiles, post-edit
  learning, 9-step setup, and a v8 mini HUD with voice-reactive Listening,
  AI sparkle **Transcribing** through cleanup (HUD dismisses after paste),
  and 5-second Cancelled + Undo.
- **Downloads** - yt-dlp + ffmpeg queue, completed downloads, cookies,
  metadata, pause/resume, browser-extension dispatch server, Dock progress, and
  clipboard video URL detection.
- **Folder Preview** - Quick Look previews for folders/archives and a Browse
  Folder window with Files / Grid / Analyze modes.
- **Snippets** - reusable text, `;trigger` expansion, Auto/Tab/Off expansion
  modes, snippet library views, body previews in menu rows, and drag-from-clipboard
  creation in the dock.
- **Window Layouts** - global window arrangement shortcuts, edge snap, restore,
  double-click layout, ignored apps, and diagnostics.
- **Window Grab** - modifier-drag windows from visible content, sharing the
  Window Layouts coordinator and ignored apps.
- **Smart Text** - clipboard smart text transforms and detection rules
  (`clipboardSmartText`).
- **Finder History** - folder and path history tracking (`folderHistory`).
- **Voice Reminders** - voice-created reminders and follow-up actions
  (`voiceReminders`).
- **AI File Organizer** - AI-assisted file organization suggestions
  (`aiFileOrganizer`).
- **Window Hub** - search-first AX window/tab hub with cleanup and AI organize
  (`windowHub`).

## UI Rules

- The normative UI spec is [`design.md`](./design.md). Read it before adding or
  changing UI.
- New SwiftUI/AppKit UI must use the shared MAYN design system in
  `MacAllYouNeed/Settings/MAYNSettingsUI.swift`.
- Use `MAYNTheme`, `MAYNControlMetrics`, `MAYNMotion`, and
  `MAYNMotionBridge` instead of raw colors, spacing, control heights, durations,
  springs, or `NSAnimationContext` timings.
- Use shared controls first: `MAYNTextField`, `MAYNSecureField`,
  `MAYNDropdown`, `FunctionSegmentedTabStrip`, `ShortcutChip`,
  `MAYNHotkeyDisplay`, `StatusPill`, `MAYNSettingsRow`, `MAYNSection`.
- Product-owned segmented/tab choices must use `FunctionSegmentedTabStrip`.
  Do not add raw SwiftUI `Picker(...).pickerStyle(.segmented)`.
- Function pages display shortcuts only. Shortcut editing belongs in tool
  settings or Hotkeys settings via `HotkeyRecorder`.
- Reduce Motion must be respected for every spatial animation, including AppKit
  panels and Core Animation paths.
- Dashboard disabled/not-installed feature cards expose lifecycle actions.
  Main sidebar destinations remain visible when disabled but are dimmed and
  non-clickable.
- Do not add redundant "Ready" pills to Dashboard cards when no action is needed.
- Voice main page header shows the shortcut chip; do not re-add a header Start
  button.

## Architecture

The build produces one `MacAllYouNeed.app` bundling three Xcode targets:

- `MacAllYouNeed/` - main app; composition root, all SwiftUI/AppKit surfaces.
- `ClipboardDaemon/` - headless `LSUIElement + LSBackgroundOnly` helper
  registered as a Login Item via SMAppService; embedded at
  `Contents/Library/LoginItems/ClipboardDaemon.app`. Captures the pasteboard
  while the main app is closed and writes to the shared App Group DB; talks to
  the main app over XPC for daemon-only commands.
- `FolderPreview/` - macOS Quick Look extension (`app-extension` target);
  embedded at `Contents/PlugIns/FolderPreview.appex`. Required to be a
  separate sandboxed bundle by macOS; cannot be merged into the main app.
- `Shared/` - SwiftPM package (`Core`, `Platform`, `UI`, vendored
  `FluidAudio`) consumed by all three targets.
- `MacAllYouNeedTests/` - XCTest target for the main app.

Main-app source layout:

- `MacAllYouNeed/App/AppController.swift` - composition root; owns subsystems,
  windows, feature runtime, hotkeys, onboarding, migration, and coordinators.
- `MacAllYouNeed/MacAllYouNeedApp.swift` - `@main` entry, NSApplicationDelegate,
  and `installMainMenu()` (App / File / Edit menus, including File > Close
  Window with Cmd+W and Quit Mac All You Need with Cmd+Q).
- `MacAllYouNeed/App/FeatureRuntime.swift` and `Shared/Sources/FeatureCore/` -
  modular feature registry, persisted feature state, asset states, enable/
  disable transitions, and pack install/uninstall.
- `MacAllYouNeed/App/Descriptors/` - feature descriptors for Clipboard, Voice,
  Downloader, Folder Preview, Window Layouts, and Window Grab.
- `MacAllYouNeed/App/LocalClipboardReader.swift` - direct shared DB reader for
  clipboard display; polls every 1s and deduplicates same-copy records.
- `MacAllYouNeed/ClipboardDock/` - bottom dock, pinboards, snippets, drag/drop,
  transforms, search, Quick Look, and shortcut registry.
- `MacAllYouNeed/Onboarding/` - feature-picker setup flow:
  Welcome -> Choose Features -> per-feature setup -> Done.
- `MacAllYouNeed/Voice/UI/Onboarding/` - voice-specific 9-step wizard.
- `MacAllYouNeed/Voice/UI/MiniVoiceHUD.swift` - v8 floating pill (universal
  144x32, three slots: left status / center label / right action). Happy path:
  Listening, Transcribing (ASR + cleanup) then dismiss; Cancelled, No speech, Failed
  when needed.
- `MacAllYouNeed/Voice/VoiceCoordinator.swift` - dictation state machine,
  shared `processCapturedAudio(captured:presetASRResult:)` for live and undo
  replay paths, inflight + pendingUndo bookkeeping, global NSEvent monitor for
  Esc / Return / numpad-Enter dispatch.
- `MacAllYouNeed/Settings/` - design system and settings detail views.
  `SettingsDestination` supports 11 destinations; current user-facing Settings
  entry opens the System group, while feature/workflow settings live in tool
  pages and reusable detail views.
- `MacAllYouNeed/WindowControl/` - shared Window Layouts / Window Grab
  coordinator, event tap, settings view, diagnostics, and snap overlay.
- `Resources/Migration/pre-install.sh` and `MacAllYouNeed/Migration/` - modular
  feature migration and What's New sheet.

## Platform-Specific Rules

### Voice HUD (v8)

- One universal 144x32 pill with three slots: left status icon, centered label,
  right action. No state ever resizes the pill.
- Listening uses a voice-reactive waveform driven by `audio.peakLevel`.
  **Transcribing** keeps the AI sparkle (subtle 1200ms pulse, no waveform) for
  the whole ASR + cleanup span; during cleanup the pill adds a gray **track**
  with a **black** fill wiping left→right from streamed cleanup progress (short
  boot sweep before the first token when progress stays at zero), then snaps to
  full black when cleanup completes. Cancelled uses X-in-circle;
  No speech / Failed use warning triangles (success dismisses the HUD).
- Stop button always cancels. The hotkey (PTT release or toggle second-press)
  is the only commit path.
- Cancelling during Listening or Transcribing always offers Undo for
  5 seconds. `processCapturedAudio(captured:presetASRResult:)` is shared
  between the live entry and the undo replay; if ASR completed before the
  cancel, the replay skips ASR.
- Esc cancels stoppable states / dismisses the undo offer / dismisses any
  visible terminal pill; ignored otherwise. Return and numpad Enter trigger
  Undo, but only while the Cancelled pill is on screen.

### Main menu and window shortcuts

- `installMainMenu()` in `MacAllYouNeedApp.swift` installs App / File / Edit
  menus. File > Close Window (Cmd+W) calls `performClose:` on the first
  responder; App > Quit (Cmd+Q) calls `NSApplication.terminate(_:)`.
- `LSUIElement = YES`: Cmd+W hides the main window but the app remains alive
  in the menu bar. Quit is the only way to terminate.
- `window.isReleasedWhenClosed = false` so reopening reuses the NSWindow.

### macOS / SwiftUI / XPC

- `AppController` is a per-delegate instance property on `MacAllYouNeedApp` (the
  `@main` struct); single-instance safety comes from the `@main` App struct
  lifecycle. Do not promote it to a static or global singleton.
- XPC auth uses `NSRunningApplication(processIdentifier:).bundleIdentifier`;
  Personal Team certificate OU and provisioning team ID can differ.
- XPC calls must use `remoteObjectProxyWithErrorHandler` so continuations resume
  on connection failure.
- Clipboard display reads `ClipboardStore` directly from the App Group DB.
- Do not move snippet expansion to the daemon; it needs the main app's
  Accessibility permission.
- Global hotkeys register during app launch, not SwiftUI `onAppear`.
- Use `@Environment(\.openSettings)` / main-window routing instead of
  `SettingsLink` from a `MenuBarExtra`.

### Folder Preview

- Quick Look extension uses
  `NSViewController + QLPreviewingController.preparePreviewOfFile(at:completionHandler:)`.
- Do not use WKWebView inside the sandboxed Quick Look extension; use
  `NSTextView + NSAttributedString(html:)`.
- Use libarchive via the SwiftPM `systemLibrary` target and Homebrew headers.

### Downloader

- yt-dlp jobs must pass `--no-check-certificate`.
- yt-dlp 2026+ needs `--js-runtime node:/path/to/node`.
- HLS pause/resume uses SIGTERM + `--continue`, not SIGSTOP.
- URL templates must be assembled by string concatenation so `%(...)s` tokens
  survive.
- Chromium cookie import must handle `is_secure` and write a valid Netscape
  header.

### Code Signing

- `disable-library-validation` entitlement is needed for Homebrew libarchive and
  applies to the main app and FolderPreview extension.
- Release DMG creation exists through `make release` /
  `scripts/package-dmg.sh`; notarization requires local Apple credentials and is
  still part of Plan 7 distribution work.

## Working Feature State

- Clipboard capture, encryption, FTS indexing, app exclusions, retention, paste
  injection, URL detection, and history search.
- Command Center menu-bar popover with five tabs: Clipboard, Voice, Downloads, Layouts,
  Snippets. Footer actions are tab-specific; Pause is Clipboard-only.
- Bottom dock with Clipboard History, Snippets, and user pinboards; pinboards
  support card and tab reordering.
- Snippets are loaded from the local dock model, support body previews, and can
  be created by dragging clipboard items to the Snippets tab.
- Voice supports local/cloud ASR, cleanup, dictionary, transcripts,
  personalization, setup, and a v8 mini HUD with voice-reactive Listening,
  AI sparkle Transcribing through cleanup (then dismiss after paste),
  and 5-second Cancelled + Undo on every mid-stream cancel (stop button, Esc,
  or pill-body tap; Return / numpad Enter retries from the cached audio).
- Downloads support queue/completed views, metadata, cookies, pause/resume,
  browser extension dispatch, and package-managed binaries.
- Folder Preview supports Quick Look folder/archive previews, Browse Folder,
  hidden-file inclusion, cascade folders, and max entries.
- Window Layouts and Window Grab are feature-gated, share settings/diagnostics,
  and update hotkey/event-tap availability when runtime state changes.
- FeatureRuntime, FeatureRegistry, pack pipeline, migration, What's New, and
  asset cleanup are implemented.

## Deferred / Not Fully Wired

- Quick Look extension XPC to the main app is deferred.
- Safari binary cookies parsing is deferred.
- Downloader update UI exists, but the full online updater path is deferred.
- Format picker dialog for downloads is deferred.
- Sync Engine remains skipped indefinitely.
- Public Sparkle appcast, GitHub Actions release, notarized/stapled official
  distribution, and paid Developer ID signing remain Plan 7 work.

## Typeless history import

Migrates Typeless local history into MAYN `voice_transcripts` + `voice_training_examples`
in the App Group `clipboard.sqlite`. Source:
`~/Library/Application Support/Typeless/`. Run only while the main app is quit:
`make import-typeless` or `./scripts/import-typeless-history.sh` (`--dry-run` supported).

## Build Requirements

- Xcode 26+, macOS 14+ target
- `brew install libarchive swiftlint swiftformat xcodegen`
- Node.js available under `~/.nvm`, `/opt/homebrew/bin/node`, or
  `/usr/local/bin/node`
- Run `scripts/fetch-binaries.sh` before the first build
- Run `xcodegen generate` after `project.yml` changes
- Use `PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig"` for Shared
  package tests

## Testing

- `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test`
- `xcodebuild test -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -destination 'platform=macOS,arch=arm64'`
- `./scripts/ci-build.sh`

## Plans Status

- Plan 0 Foundation - complete
- Plan 1 Storage & Encryption - complete
- Plan 2 Sync Engine - skipped indefinitely
- Plan 3 Clipboard Subsystem - complete
- Plan 4 Folder Preview - complete
- Plan 5 Downloader - complete, updater path deferred
- Plan 6 UI Shell / onboarding / settings / integrations - complete
- Plan 7 Distribution - deferred until Developer ID / notarization automation
- Plan 8 Modular Features - complete in app; public delivery awaits Plan 7
