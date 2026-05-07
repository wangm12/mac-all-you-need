# Mac All You Need — Developer Context

## Project
Native macOS productivity app combining clipboard manager, folder preview (Quick Look), and universal video downloader. Built with Swift 5.9+, SwiftUI, AppKit, GRDB, libarchive.

## Architecture
- `MacAllYouNeed/` — Main app target (menu bar, UI, coordinators)
- `ClipboardDaemon/` — LoginItem helper (NSPasteboard polling, XPC server)
- `FolderPreview/` — Quick Look extension (NSViewController + WKWebView)
- `Shared/Sources/Core/` — Storage, encryption, XPC protocols, downloader logic
- `Shared/Sources/Platform/` — Pasteboard, OCR, hotkeys, cookies, archive
- `Shared/Sources/UI/` — SwiftUI views (FolderPreview, clipboard popup)

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
- Quick Look folder preview (HTML table) and archive listing (libarchive)
- ⌘⇧F Browse Folder window with Files/Grid/Analyze views
- yt-dlp downloader: queue, pause/resume, concurrent fragments, cookies
- Real-time phase indicators (Connecting → Fetching info → Merging etc.)
- Video metadata (thumbnail, title, channel, duration) fetched async
- Browser cookie import (Chrome/Edge/Brave/Arc multi-profile, AES-CBC decryption)
- DispatchServer (localhost:18765) for browser extension integration
- DockProgressController (badge %) during active downloads

## What's Not Working / Deferred ❌
- Quick Look extension XPC to main app (sandboxed extension restrictions)
- Safari binary cookies parsing (binarycookies format — deferred to Plan 6)
- yt-dlp updater (EdDSA verification scaffolded, application deferred to Plan 7)
- Format picker dialog for downloads (deferred to Plan 6)
- Snippet `;trigger` expansion via CGEventTap (implemented, manual test pending)
- Xcode/GitHub Actions CI requiring `brew install libarchive` (PKG_CONFIG_PATH needed)

## Build Requirements
- Xcode 26+, macOS 14+ target
- `brew install libarchive swiftlint swiftformat xcodegen`
- `node` (any version, used for yt-dlp JS extraction)
- Run `scripts/fetch-binaries.sh` to download yt-dlp + ffmpeg before first build
- `xcodegen generate` after any `project.yml` changes
- `PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test` for Shared package

## Testing
- `cd Shared && PKG_CONFIG_PATH=... swift test` — 113 tests
- `./scripts/ci-build.sh` — full build + lint + tests

## Bundle IDs
- Main app: `com.macallyouneed.app`
- Daemon: `com.macallyouneed.app.daemon`
- Quick Look: `com.macallyouneed.app.folderpreview`
- App Group: `group.com.macallyouneed.shared`
- Mach services: `group.com.macallyouneed.shared.daemon`, `group.com.macallyouneed.shared.folderpreview`

## Plans Status
- Plan 0 ✅ Foundation (Xcode project, targets, App Group)
- Plan 1 ✅ Storage & Encryption (GRDB, AES-GCM, Argon2id, FTS5)
- Plan 2 ⏳ Sync Engine (skipped for now)
- Plan 3 ✅ Clipboard Subsystem (daemon, XPC, popup, hotkey)
- Plan 4 ✅ FolderPreview (Quick Look HTML, libarchive, Browse window)
- Plan 5 ✅ Downloader (yt-dlp, metadata, cookies, queue)
- Plan 6 ⏳ UI Polish (pending)
- Plan 7 ⏳ Distribution (pending)
