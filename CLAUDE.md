# Mac All You Need - Developer Context

## Project

Native macOS productivity app (LSUIElement / menu-bar resident) that bundles
11 first-class tool surfaces:

- **Clipboard** - encrypted clipboard history (AES-GCM / GRDB / FTS5), local
  direct reads via `LocalClipboardReader`, `Command-Shift-V` dock/popup,
  searchable main-window history, capture rules, paste behavior, pinboards, and
  multi-select transforms.
- **Voice** - push-to-talk or toggle dictation into any app, local Qwen3-ASR via
  FluidAudio, optional Groq Whisper cloud ASR, optional LLM cleanup, transcript
  history, dictionary replacements, personalization profiles, post-edit
  learning, and a v8 mini HUD (voice-reactive Listening waveform, AI sparkle
  **Transcribing** for the whole ASR + LLM cleanup span — cleanup adds a gray-track
  black wipe; HUD dismisses after paste — no Applied/
  Copied pill) with stop button = cancel and a 5-second Cancelled + Undo
  affordance; No speech / Failed use warning terminals.
- **Downloads** - yt-dlp + ffmpeg downloader with queue/completed views, browser
  cookie import, pause/resume, browser-extension dispatch server, auto video URL
  detection from clipboard, metadata thumbnails, and Dock progress.
- **Folder Preview** - Quick Look folder/archive previews plus a Browse Folder
  window with Files / Grid / Analyze modes.
- **Snippets** - reusable text snippets, `;trigger` expansion from the main app
  CGEventTap, expansion modes (`Auto`, `Tab`, `Off`), snippet library views, and
  drag-from-clipboard creation in the dock.
- **Window Layouts** - global window move/snap/restore shortcuts, edge snapping,
  double-click maximize, restore history, and per-app ignore rules.
- **Window Grab** - modifier-drag windows from visible content areas, sharing the
  same window-control coordinator and ignore rules as Window Layouts.
- **Smart Text** - clipboard smart text transforms and detection rules
  (`clipboardSmartText`).
- **Finder History** - folder and path history tracking (`folderHistory`).
- **Voice Reminders** - voice-created reminders and follow-up actions
  (`voiceReminders`).
- **AI File Organizer** - AI-assisted file organization suggestions
  (`aiFileOrganizer`).
- **Dock Previews** - rich Dock icon previews for clipboard and file content
  (`dockPreviews`).

Built with Swift 5.9+, SwiftUI + AppKit, GRDB, libarchive, FluidAudio, and
Sparkle integration scaffolding. The composition root is `AppController`; all
subsystems share a single App Group container. Clipboard display reads the local
clipboard DB directly; XPC remains for daemon commands and paste operations.

## UI And Design System

The canonical UI specification is [`design.md`](./design.md). New SwiftUI/AppKit
work must follow it for colors, spacing, fonts, page chrome, controls, animation,
and Reduce Motion.

Important entry points:

- [`design.md`](./design.md) - normative tokens, components, application
  surfaces, accepted exceptions, and review checklist.
- [`MacAllYouNeed/CLAUDE.md`](./MacAllYouNeed/CLAUDE.md) - terse UI working
  notes auto-loaded for files under `MacAllYouNeed/`.
- `MacAllYouNeed/Settings/MAYNSettingsUI.swift` - `MAYNTheme`,
  `MAYNControlMetrics`, `MAYNMotion`, shared controls, rows, sections, cards,
  status pills, and toasts.
- `MacAllYouNeed/App/FunctionPageShell.swift` - main tool page chrome and
  `FunctionSegmentedTabStrip`.

Hard UI rules:

- Product-owned segmented choices use `FunctionSegmentedTabStrip`. Do not add
  raw `.pickerStyle(.segmented)` controls.
- Use `MAYNTheme`, `MAYNControlMetrics`, `MAYNMotion`, and
  `MAYNMotionBridge`; do not add ad-hoc colors, dimensions, animation durations,
  or springs.
- Tool pages may display shortcuts with `ShortcutChip` /
  `MAYNHotkeyDisplay`; editing belongs in Settings/tool settings via
  `HotkeyRecorder`.
- Disabled feature destinations stay visible in the main sidebar, but are dimmed
  and non-clickable. Dashboard cards show lifecycle actions instead.
- Voice's main page header shows the shortcut chip only; it does not include a
  header Start button.

## Architecture

The build produces one `MacAllYouNeed.app` that embeds two sibling targets:

- `MacAllYouNeed/` - main app bundle and composition root.
- `ClipboardDaemon/` - headless `LSUIElement + LSBackgroundOnly` helper.
  Registered as a Login Item via SMAppService and embedded at
  `Contents/Library/LoginItems/ClipboardDaemon.app`. Owns 24/7 pasteboard
  capture so clips are recorded even when the main app is quit. Talks to the
  main app over XPC for daemon-only commands; clipboard reads from the UI go
  straight to the shared App Group DB.
- `FolderPreview/` - macOS Quick Look `app-extension` target. Embedded at
  `Contents/PlugIns/FolderPreview.appex`. macOS loads it in its own sandboxed
  process; the main app cannot provide Quick Look previews directly.
- `Shared/` - SwiftPM package consumed by all three targets (`Core`,
  `Platform`, `UI`, plus the vendored `FluidAudio` checkout).

Main-app source layout:

- `MacAllYouNeed/App/AppController.swift` - composition root; owns runtime
  services, windows, hotkeys, feature runtime, migrations, and coordinators.
- `MacAllYouNeed/MacAllYouNeedApp.swift` - `@main` entry, application delegate,
  and `installMainMenu()` (App / File / Edit menus, including File > Close
  Window with Cmd+W and Quit Mac All You Need with Cmd+Q).
- `MacAllYouNeed/App/FeatureRuntime.swift` plus `Shared/Sources/FeatureCore/` -
  registry, persisted feature state, enable/disable transitions, asset state,
  and install/uninstall coordination.
- `MacAllYouNeed/App/Descriptors/` - feature descriptors for Clipboard, Voice,
  Downloader, Folder Preview, Window Layouts, and Window Grab.
- `MacAllYouNeed/App/LocalClipboardReader.swift` - direct clipboard DB reader;
  polls every 1s and deduplicates same-copy records.
- `MacAllYouNeed/ClipboardDock/` - bottom dock, pinboard tabs, snippets library,
  drag/drop, transforms, quick look, and shortcut registry.
- `MacAllYouNeed/Onboarding/` - feature-picker onboarding:
  Welcome -> Choose Features -> per-feature setup loop -> Done.
- `MacAllYouNeed/Voice/UI/Onboarding/` - 9-step voice setup:
  Welcome, Microphone, Accessibility, Speech model, AI cleanup, Shortcut,
  Languages, Try it, Done.
- `MacAllYouNeed/Voice/UI/MiniVoiceHUD.swift` - v8 floating pill (universal
  144x32, three slots: left status icon at x=20, centered label, right action
  at x=124). Happy path: Listening → Transcribing (through cleanup) then dismiss;
  Cancelled / No speech / Failed when needed.
- `MacAllYouNeed/Voice/VoiceCoordinator.swift` - dictation state machine,
  ASR/cleanup pipeline (`processCapturedAudio`), inflight + pendingUndo
  bookkeeping, global NSEvent monitor for Esc/Return/numpad-Enter dispatch.
- `MacAllYouNeed/Settings/` - shared design system and settings detail views.
  `SettingsDestination` defines 11 detail destinations; the current Settings
  entry opens the System group (General, Permissions, Storage, Advanced), while
  feature/workflow settings are exposed from their main tool pages and reused by
  `SettingsDetailContent`.
- `MacAllYouNeed/WindowControl/` - shared Window Layouts / Window Grab
  coordinator, event tap, settings, diagnostics, and overlay panel.
- `Resources/Migration/pre-install.sh` and `MacAllYouNeed/Migration/` - modular
  feature migration and What's New sheet for pre-modular upgrades.

## Platform Decisions And Fixes

### Voice HUD (v8)

- Universal 144x32 pill, three slots: status icon (left, x=20), centered label
  (x=72), action button (right, x=124). The pill does not resize between
  states.
- Listening: voice-reactive waveform driven by `audio.peakLevel`; bars react to
  amplitude with a per-bar phase stagger. **Transcribing** (entire post-commit
  span): AI sparkle with subtle 1200ms pulse (no waveform — not live mic audio).
  During LLM cleanup the same pill adds a gray **track** with a **black** fill
  wiping left→right from streamed cleanup progress (short boot sweep before the
  first token when progress stays at zero), then snaps to full black when cleanup
  completes.
- Cancelled uses X-in-circle and exposes a right-slot Undo button; No speech /
  Failed use a warning triangle (success path dismisses the HUD with no
  checkmark pill).
- Stop button always cancels — it never advances to transcribe. The hotkey
  (PTT release in `.hold`, second press in `.toggle`) is the only commit path.
- Cancelling during Listening or Transcribing always offers Undo for
  5 seconds. `processCapturedAudio(captured:presetASRResult:)` is shared
  between the live entry (`stopRecordingAndPaste`) and the undo replay
  (`undoLastCancel`); if ASR completed before the cancel, the replay skips ASR.
- Keyboard model — global + local `NSEvent.keyDown` monitor installed by
  `VoiceCoordinator.installEscKeyMonitor`:
  - Esc: stoppable -> cancel; undoable -> dismiss undo; visible terminal pill
    (No speech / Failed) -> dismiss; otherwise ignored (don't interfere with
    other apps' Esc).
  - Return / numpad Enter: undo, but only while the Cancelled pill is up. Keeps
    us from intercepting newlines in the user's editor.
- Cursor-screen lock (`targetScreen`) captured on first show; HUD stays on one
  screen for the whole Listening → Transcribing (ASR + cleanup) → dismiss (or
  Cancelled / error terminal) lifecycle.

### Main menu and window shortcuts

- `installMainMenu()` in `MacAllYouNeedApp.swift` builds the NSApp main menu:
  App (About / Settings... / Quit, Cmd+Q), File (Close Window, Cmd+W via
  `performClose:` on the first responder), Edit (Undo / Redo / Cut / Copy /
  Paste / Delete / Select All).
- `LSUIElement = YES`; closing the main window via Cmd+W or the red traffic
  light hides the window but does not quit. The app remains in the menu bar
  until the user picks Quit (Cmd+Q).
- `window.isReleasedWhenClosed = false`, so re-opening the main window via
  `MainWindowController.show()` reuses the same `NSWindow` instance.

### macOS / SwiftUI / XPC

- **AppController is a per-delegate instance property** - it is declared as a
  `let` on `MacAllYouNeedApp` (the `@main` struct) and instantiated there.
  Single-instance safety comes from the `@main` App struct lifecycle, not from a
  global static; do not promote it to a static or singleton.
- **XPC auth** - Personal Team certificate OU can differ from provisioning team
  ID. Use `NSRunningApplication(processIdentifier:).bundleIdentifier`.
- **XPC continuation safety** - use `remoteObjectProxyWithErrorHandler` so
  continuations resume on connection failure.
- **Clipboard display** - the main app reads `ClipboardStore` directly from the
  shared DB, then deduplicates records within a 0.5s same-copy window.
- **Daemon crash throttle** - unregister then register the SMAppService login
  item on app launch to reset macOS crash throttling.
- **SettingsLink** - broken inside `MenuBarExtra` on macOS 14+; use
  `@Environment(\.openSettings)` or show the main Settings destination.
- **Snippet expansion** - lives in the main app because the daemon does not have
  the main bundle's Accessibility permission.

### Folder Preview

- Quick Look extension uses
  `NSViewController + QLPreviewingController.preparePreviewOfFile(at:completionHandler:)`.
  Do not use `QLPreviewProvider` / `QLPreviewReply` on macOS 26.
- WKWebView is blocked in the sandboxed Quick Look extension. Use
  `NSTextView + NSAttributedString(html:)`.
- Folder settings include hidden files, cascade folders, and maximum entries.

### Downloader

- Pass `--no-check-certificate`; PyInstaller Python cannot locate macOS system
  CAs reliably.
- Pass `--js-runtime node:/path/to/node` for yt-dlp 2026+ JavaScript extraction.
- Node is auto-detected from `~/.nvm`, `/opt/homebrew/bin/node`,
  `/usr/local/bin/node`.
- HLS pause/resume uses SIGTERM + `--continue`, not SIGSTOP, because ffmpeg
  subprocesses continue after SIGSTOP.
- Build output templates by string concatenation; `URL.appendingPathComponent`
  strips `%` tokens.
- Chromium cookie import handles Chrome 130+'s `is_secure` column and writes a
  valid Netscape cookie file header.

### Code Signing / Native Libraries

- `disable-library-validation` is required for Homebrew libarchive and applies
  to both the main app and FolderPreview extension.
- System libarchive exists in the dyld shared cache on macOS 26; use the SwiftPM
  `systemLibrary` target with Homebrew headers.
- `AE_IFDIR` / `AE_IFREG` are C macros; use octal literals `0o040000` /
  `0o100000` in Swift.

## Working Feature State

- Clipboard capture, encryption, FTS search, retention, paste injection, capture
  rules, app exclusions, and multi-select.
- `Command-Shift-V` dock/popup with search focus, keyboard navigation,
  transforms, quick look, pinboards, and drag-reorder.
- Command Center menu-bar popover with five tabs: Clipboard, Voice, Downloads, Layouts,
  Snippets. Footer is tab-specific; Pause appears only for Clipboard.
- Snippet library powered by the local dock model, not stale XPC snippet reads.
  Snippet rows show body preview and keep the trigger visible.
- Snippet expansion modes: Auto expands on trigger + whitespace; Tab expands
  only after pressing Tab; Off keeps typed triggers literal.
- Dragging clipboard cards onto the Snippets tab creates a prefilled snippet
  draft in the in-panel snippet editor.
- Voice dictation flow, microphone/Accessibility setup, local/cloud ASR
  selection, transcript history, dictionary, personalization, and v8 mini HUD
  with voice-reactive Listening waveform, AI sparkle Transcribing through cleanup
  (then dismiss after paste), and 5-second Cancelled + Undo on every
  mid-stream cancel (stop button, Esc, or pill-body tap; Return / numpad Enter
  re-runs the undo).
- Downloader queue/completed views, cookies, metadata, pause/resume, browser
  extension dispatch, and clipboard video URL badge / enqueue flow.
- Folder Preview Quick Look extension, archive listing, Browse Folder window,
  cascade folders, hidden files, and max-entry settings.
- Window Layouts and Window Grab with shared settings, global hotkeys, edge snap,
  modifier drag, ignored apps, diagnostics, and runtime feature gates.
- Dashboard feature cards with enable/disable/install/cancel/retry/uninstall
  lifecycle actions. Redundant "Ready" status pills are intentionally omitted.
- FeatureRuntime, FeatureRegistry, pack pipeline, asset cache cleanup, migration
  report, and What's New sheet.
- Release DMG script (`make release` / `scripts/package-dmg.sh`) creates
  `dist/MacAllYouNeed.dmg`; notarization requires local Apple credentials.

## Deferred / Not Fully Wired

- Quick Look extension XPC back to the main app remains deferred because of
  sandboxed extension restrictions.
- Safari binary cookies parsing remains deferred.
- The downloader update command surface exists, but the full online updater path
  remains deferred to distribution work.
- Format picker dialog for downloads remains deferred.
- Plan 2 Sync Engine is skipped indefinitely.
- Public release automation, Sparkle appcast, GitHub Actions notarized release,
  and paid Developer ID distribution remain Plan 7 territory.

## Typeless history import

One-time migration from Typeless dictation history into MAYN voice transcripts and
training examples (`model_identifier = typeless-import`). Reads Typeless at
`~/Library/Application Support/Typeless/typeless.db` and `Recordings/*.ogg`
(not `com.typeless.macos`). Converts OGG to encrypted WAV via vendored ffmpeg.

1. Quit Mac All You Need (Cmd+Q).
2. `make bootstrap` if `Vendored/binaries/ffmpeg` is missing.
3. `./scripts/import-typeless-history.sh` or `make import-typeless` (supports
   `--dry-run`, `--skip-audio`, `--limit N`). Re-runs skip existing transcript IDs.
   The script always targets `~/Library/Group Containers/group.com.macallyouneed.shared`.
   Verify with:
   `sqlite3 ~/Library/Group\ Containers/group.com.macallyouneed.shared/databases/clipboard.sqlite \
   "SELECT COUNT(*) FROM voice_transcripts WHERE model_identifier='typeless-import';"`

Implementation: `Shared/Sources/Core/Voice/Import/`, CLI target `TypelessImport`.

## Build Requirements

- Xcode 26+, macOS 14+ target
- `brew install libarchive swiftlint swiftformat xcodegen`
- `node` for yt-dlp JavaScript extraction
- Run `scripts/fetch-binaries.sh` before the first local build
- Run `xcodegen generate` after `project.yml` changes
- Use `PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig"` for Shared
  package tests

## Testing

- `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test`
- `xcodebuild test -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -destination 'platform=macOS,arch=arm64'`
- `./scripts/ci-build.sh` for full lint + tests + app build

## Plans Status

- Plan 0 - Foundation: complete
- Plan 1 - Storage & Encryption: complete
- Plan 2 - Sync Engine: skipped indefinitely
- Plan 3 - Clipboard Subsystem: complete
- Plan 4 - Folder Preview: complete
- Plan 5 - Downloader: complete, with updater UI still deferred
- Plan 6 - UI Shell / onboarding / settings / integrations: complete
- Plan 7 - Distribution: deferred until Developer ID / notarization automation
- Plan 8 - Modular Features: complete in-app; public distribution pending Plan 7
