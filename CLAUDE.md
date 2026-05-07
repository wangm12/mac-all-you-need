# Mac All You Need — Developer Context

## Project
Native macOS productivity app combining clipboard manager, folder preview (Quick Look), and universal video downloader. Built with Swift 5.9+, SwiftUI, AppKit, GRDB, libarchive.

## Architecture (Plan 6 update)
- `MacAllYouNeed/App/AppController.swift` — composition root (replaces AppDelegate); owns all subsystems
- `MacAllYouNeed/App/LocalClipboardReader.swift` — reads clipboard DB directly (no XPC); polls every 1s with deduplication
- `MacAllYouNeed/Onboarding/` — 6-step first-launch wizard (Accessibility, FDA, Notifications, Sync)
- `MacAllYouNeed/Settings/` — 7-tab Settings window (General, Clipboard, Downloads, FolderPreview, Sync, Hotkeys, Advanced)

### Plan 6 Fixes (macOS 26 / XPC / SwiftUI)
- **AppController is a static let** — SwiftUI App struct can be recreated multiple times; use `private static let controller = try! AppController()` to ensure single initialization
- **XPC auth**: `SecCodeCopyGuestWithAttributes` + team-ID check fails (Personal Team cert OU ≠ provisioning ID). Use `NSRunningApplication(processIdentifier:).bundleIdentifier` only
- **XPC continuation leak**: `withCheckedContinuation` leaks if XPC callback never fires (connection drop). Always use `remoteObjectProxyWithErrorHandler` with error handler that calls `cont.resume`
- **Clipboard display**: Main app reads `ClipboardStore` directly from shared App Group DB (no XPC). Deduplicate records within 0.5s window (one copy action → multiple type records)
- **Daemon startup race**: Main app retries XPC load with exponential backoff (0.5, 1, 2, 4s)
- **Daemon crash throttle**: `SMAppService.loginItem.unregister()` then `register()` on each app launch resets the macOS crash throttle
- **SettingsLink**: Broken in `MenuBarExtra` on macOS 14+. Use `@Environment(\.openSettings)` instead
- **Snippet expansion**: Moved from daemon to main app — daemon has no Accessibility permission in its own bundle; main app requests it during onboarding

## Key Decisions & Platform-Specific Fixes

### macOS 26 Compatibility
- **Quick Look extension**: Use `NSViewController + QLPreviewingController.preparePreviewOfFile(at:completionHandler:)` NOT `QLPreviewProvider`/`QLPreviewReply` (hangs on macOS 26)
- **WKWebView in sandboxed QL extension**: Blocked (can't spawn WebContent process). Use `NSTextView + NSAttributedString(html:)` instead
- **GlobalHotkey**: Register in `AppDelegate.applicationDidFinishLaunching`, NOT in SwiftUI `onAppear` (MenuBarExtra `onAppear` fires only on first click, not launch) and NOT in `scenePhase == .active` (LSUIElement apps never become active)
- **MenuBarExtra + ObservableObject**: AppDelegate must conform to `ObservableObject` with `@Published` properties; pass AppDelegate as `@ObservedObject` to menu bar content (not as captured `let` value which snapshots nil)

### yt-dlp (PyInstaller bundle)
- Must pass `--no-check-certificate` (PyInstaller Python can't find macOS system CA)
- Must pass `--js-runtime node:/path/to/node` for yt-dlp 2026+ (JavaScript extraction required)
- `SSL_CERT_FILE` env var alone does NOT work
- Use `lipo -archs` output with `.split(whereSeparator: \.isWhitespace)` not `.split(separator: " ")` (trailing newline causes mismatch)
- Node.js auto-detected from `~/.nvm`, `/opt/homebrew/bin/node`, `/usr/local/bin/node`

### yt-dlp Pause/Resume
- SIGSTOP does NOT work for HLS downloads (ffmpeg subprocess continues)
- Use SIGTERM + `--continue` flag on resume instead
- `DownloadQueue.pauseForResume(id:)` terminates without triggering failure callback (uses `pausedIDs` set)

### URL Templates
- `URL.appendingPathComponent("%(title)s")` strips `%` characters (percent-encoding)
- Use string concatenation: `outputDir.path + "/%(title)s - %(uploader)s.%(ext)s"` instead

### XPC Auth
- Personal Team: certificate OU (`777BPJR98D`) ≠ provisioning team ID (`2N55H39FC4`)
- `SecCodeCopyGuestWithAttributes(nil, pid)` fails in production builds (requires `get-task-allow`)
- Use bundle ID check only: `NSRunningApplication(processIdentifier:).bundleIdentifier`

### Cookies (Chromium)
- Chrome 130+ renamed `secure` column to `is_secure` — detect dynamically via `conn.columns(in: "cookies")`
- Netscape cookie file: first line MUST be `# Netscape HTTP Cookie File` (yt-dlp validates this)
- `domain_specified` field MUST be `TRUE` for domains starting with `.` (Python http.cookiejar asserts this)

### Code Signing
- `disable-library-validation` entitlement needed for brew libarchive (different Team ID)
- Apply to both main app AND FolderPreview extension

### libarchive
- System libarchive IS in dyld shared cache on macOS 26 (no on-disk file at `/usr/lib/libarchive*`)
- Use `systemLibrary` SwiftPM target with brew headers (installed via `brew install libarchive`)
- `AE_IFDIR`/`AE_IFREG` are C macros not importable in Swift — use octal literals `0o040000`/`0o100000`

### Metadata Fetch
- Use `Task` (not `Task.detached`) for metadata fetch from `@MainActor` coordinator (avoids Sendable capture issues with non-Sendable `DownloadStore`)
- `Task.detached` with non-Sendable captures silently fails to update DB

### DownloadRecord Progress Bar
- HLS streams report per-fragment %, not total file %
- Use `bytesDownloaded/bytesTotal` for overall fraction
- Always return `1.0` for `.completed` state (persisted bytes may be stale fragment data)

## What's Working ✅
- Clipboard capture (400ms poll, AES-GCM encrypted, FTS5 indexed)
- ⌘⇧V popup with search, arrow navigation, paste injection
- Menu bar 3-tab popover (Clipboard / Downloads / Snippets) with icon + relative timestamp list
- Clipboard deduplication (same copy action → multiple records → one display entry)
- Quick Look folder preview (HTML table) and archive listing (libarchive)
- ⌘⇧F Browse Folder window with Files/Grid/Analyze views
- yt-dlp downloader: queue, pause/resume, concurrent fragments, cookies
- Real-time phase indicators (Connecting → Fetching info → Merging etc.)
- Video metadata (thumbnail, title, channel, duration) fetched async
- Browser cookie import (Chrome/Edge/Brave/Arc multi-profile, AES-CBC decryption)
- Cookie import error banner with "Open Chrome" button when import fails
- DispatchServer (localhost:18765) for browser extension integration
- DockProgressController (badge %) during active downloads
- Settings window (7 tabs) with persistent AppGroupSettings backing
- Onboarding wizard (6 steps) with TCC auto-advance and window-close on Done
- Hotkey rebinding (HotkeyRecorder + HotkeyRegistry with conflict detection)
- URLDetector: video URL badge on clipboard items → one-click enqueue to downloader
- "Preview folder" button on completed downloads → opens Browse Folder window
- Snippet `;trigger` expansion via CGEventTap (runs in main app with Accessibility)
- Excluded apps list wired from Settings → daemon ExclusionRules
- Download output template wired from Settings → DownloadCoordinator
- FolderPreview maxEntries + includeHidden wired from Settings → FolderEnumerator

## What's Not Working / Deferred ❌
- Quick Look extension XPC to main app (sandboxed extension restrictions)
- Safari binary cookies parsing (binarycookies format — deferred)
- yt-dlp updater (deferred to Plan 7)
- Format picker dialog for downloads (deferred)
- Xcode/GitHub Actions CI requiring `brew install libarchive` (PKG_CONFIG_PATH needed)
- Plan 2 Sync Engine (deferred indefinitely)

## Build Requirements
- Xcode 26+, macOS 14+ target
- `brew install libarchive swiftlint swiftformat xcodegen`
- `node` (any version, used for yt-dlp JS extraction)
- Run `scripts/fetch-binaries.sh` to download yt-dlp + ffmpeg before first build
- `xcodegen generate` after any `project.yml` changes
- `PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test` for Shared package

## Testing
- `cd Shared && PKG_CONFIG_PATH=... swift test` — 109+ tests
- `./scripts/ci-build.sh` — full build + lint + tests

## Plans Status
- Plan 0 ✅ Foundation (Xcode project, targets, App Group)
- Plan 1 ✅ Storage & Encryption (GRDB, AES-GCM, Argon2id, FTS5)
- Plan 2 ⏳ Sync Engine (skipped indefinitely)
- Plan 3 ✅ Clipboard Subsystem (daemon, XPC, popup, hotkey)
- Plan 4 ✅ FolderPreview (Quick Look HTML, libarchive, Browse window)
- Plan 5 ✅ Downloader (yt-dlp, metadata, cookies, queue)
- Plan 6 ✅ UI Shell (AppController, settings, onboarding, hotkey rebinding, integrations)
- Plan 7 ⏳ Distribution (Sparkle 2, notarized DMG, GitHub Actions — requires paid Developer ID cert)
