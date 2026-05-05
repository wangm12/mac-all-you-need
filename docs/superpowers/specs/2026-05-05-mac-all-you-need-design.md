# Mac All You Need — Design Spec

**Date:** 2026-05-05
**Status:** Draft for review
**Owner:** Mingjie Wang

## 1. Summary

Mac All You Need is a native macOS app that combines three independent productivity utilities under a single menu-bar surface:

1. **Clipboard manager** — Paste-style infinite history with pinboards, snippets, search, encryption, and folder-based cross-device sync.
2. **Folder previewer** — Quick Look extension for folders and archives, modeled on FolderPreview Pro with PeekX-style folder analysis and a contact-sheet view for image-heavy folders.
3. **Universal video downloader** — yt-dlp-powered downloader matching the functional core of [v-download](https://github.com/wangm12/v-download) (a separate Electron project; this is a fresh native rewrite, not a fork).

The app is positioned as a public product — direct distribution via DMG with Sparkle updates, polished onboarding, and a paid/free model TBD.

## 2. Goals & non-goals

### Goals

- One coherent native macOS app, not three loosely-bundled tools.
- Three subsystems share a data layer, encryption, sync, and settings.
- First-class UX on macOS 14 Sonoma+ using SwiftUI with AppKit interop where SwiftUI falls short.
- Cross-device sync without building any backend — leverage whatever cloud the user already has installed (iCloud Drive, Google Drive, Dropbox, OneDrive).
- Self-contained: bundle `yt-dlp` and `ffmpeg`, no Homebrew dependency.

### Non-goals (v1)

See §13 "Future work / v2 backlog" for tracked TODOs.

- No Chrome extension.
- No native CloudKit / Google Drive API integration.
- No iOS / iPadOS apps.
- No collaborative pinboard sharing (Paste's social feature).
- No `⌘K` unified search palette.
- No localization beyond English.
- No formal accessibility audit (basic VoiceOver labels only).

## 3. Decisions log (with rationale)

| # | Decision | Rationale |
|---|---|---|
| 1 | Full native rewrite (Swift/SwiftUI), not Electron | A Quick Look extension cannot be Electron; it must be native. Forcing the entire app native gives a single codebase and avoids a hybrid seam. |
| 2 | Direct DMG distribution, unsandboxed | Clipboard injection, browser cookie reading, and "open from Quick Look" all need entitlements blocked or restricted in the Mac App Store sandbox. |
| 3 | macOS 14 Sonoma+ minimum | `MenuBarExtra` matured; `@Observable`, modern scroll APIs, refined SwiftData behavior. ~80% of active Macs. |
| 4 | SwiftUI-first with AppKit interop | Right tradeoff for a new public product. AppKit reserved for global hotkey overlay window, NSPasteboard polling, and any menu-bar polish SwiftUI can't deliver. |
| 5 | Folder-based sync (not native APIs) | Writing encrypted records to a user-chosen folder lets any installed cloud app handle the actual sync. ~80% of the value at ~10% of the effort. iCloud / Google Drive / Dropbox / OneDrive all work without writing OAuth code. |
| 6 | Last-write-wins conflict policy + visible conflicts surface | A CRDT is overkill for clipboard data, which is rarely edited after creation. Conflicts go to a "Resolve conflicts" UI; nothing is silently lost. |
| 7 | Menu-bar-first UI, no traditional dock app | The three subsystems are utility-shaped, not document-shaped. Menu bar is the home base; settings live in a separate window; clipboard popup floats over any app. |
| 8 | Bundle yt-dlp + ffmpeg in `Resources/` | Self-contained app. No `brew install` instructions for users. App-managed yt-dlp updates via "Check for downloader update". |
| 9 | Vendored libarchive for archive previews | BSD license, single C dependency, supports ZIP/RAR/7z/TAR/GZ/BZ2 in one library. |
| 10 | Local HTTP server stub on `:18765` even without v1 Chrome extension | Future-proofs for a v2 extension at near-zero v1 cost. |
| 11 | No Chrome extension in v1 | Defer to v2; keeps v1 scope tractable. URL dispatch stub still ships. |

## 4. Bundle layout & module structure

Single product with multiple bundle targets (macOS forces this — Quick Look extension and clipboard daemon run in separate processes).

```
MacAllYouNeed.app/
├── Contents/
│   ├── MacOS/
│   │   └── MacAllYouNeed                  # main app (menu bar UI, downloader UI, onboarding, sync engine, standalone folder window)
│   ├── Resources/
│   │   ├── yt-dlp                         # bundled fat binary (arm64 + x86_64)
│   │   └── ffmpeg                         # bundled fat binary
│   ├── PlugIns/
│   │   └── FolderPreview.appex/           # Quick Look extension, loaded by qlmanage
│   └── Library/LoginItems/
│       └── ClipboardDaemon.app/           # background helper for NSPasteboard observation
```

### Xcode targets

| Target | Purpose | Process |
|---|---|---|
| **MacAllYouNeed** | Menu-bar UI, onboarding wizard, downloader UI, settings, sync engine, standalone folder window | Foreground (LSUIElement = YES, no dock icon by default) |
| **ClipboardDaemon** | NSPasteboard polling, capture, encrypted store writes; XPC server for popup UI | Background helper, registered as LoginItem via `SMAppService` |
| **FolderPreview** | Quick Look extension; reads from shared App Group store | Loaded by `qlmanage` |
| **Shared** (Swift package, in-repo) | `Core` (storage, encryption, sync, models), `UI` (shared SwiftUI components), `Platform` (NSPasteboard wrappers, hotkey, archive enumeration) | Linked into all of the above |

### App Group container

All three processes share `~/Library/Group Containers/group.com.macallyouneed.shared/`. Quick Look extensions can't access arbitrary disk locations otherwise. Layout:

```
group.com.macallyouneed.shared/
├── databases/
│   ├── clipboard.sqlite (+ -wal, -shm)
│   ├── downloads.sqlite
│   └── settings.plist
├── blobs/                              # encrypted images, files, video thumbnails
├── thumbnails/                         # QLThumbnailGenerator cache for FolderPreview
└── dispatch.token                      # rotating shared secret for the local HTTP server
```

## 5. Data layer, encryption, and sync

### Storage

- **SwiftData** as the primary modeling layer (macOS 14+).
- Raw **SQLite** (via SwiftData's underlying store) used for FTS5 full-text search of clipboard content.
- WAL files live on the App Group container so all three processes can read concurrently. The daemon is the sole writer to `clipboard.sqlite`; the main app is the sole writer to `downloads.sqlite`.

### Encryption

- User sets a passphrase during onboarding (skippable if sync is off).
- Key derivation: **Argon2id** (target 100ms on M1) → 256-bit key.
- Per-record payload encryption: **AES-256-GCM** with random nonce per record. Indexes (timestamps, app IDs, post-decryption FTS tokens) stay queryable in cleartext within the SQLite file.
- Key stored in **Keychain** with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` so it never replicates to other Macs.
- For sync: the entire envelope is opaque ciphertext; even indexes are encrypted in the sync representation.

### Folder-based sync

User picks a sync folder during onboarding. If that folder is inside an installed cloud (iCloud Drive, Google Drive, Dropbox, OneDrive), that cloud's desktop app handles the actual upload/download. Mac All You Need does **not** speak to any cloud API.

```
<sync folder>/
├── records/
│   ├── 01HQ9...XYZ.envelope        # one file per record, ULID-named (no name collisions)
│   ├── 01HQ9...ABC.envelope
│   └── ...
├── tombstones/
│   └── 01HQ9...DEF.tomb            # deletion markers, expire after 30 days
└── manifest.json                   # device list, schema version, vector clock
```

#### Envelope format

```
[16-byte nonce][AES-GCM(payload)][16-byte auth tag]
```

Decrypted payload is JSON:

```json
{
  "kind": "clipboard_item" | "snippet" | "pinboard" | "settings" | "download_history",
  "id": "<ULID>",
  "created": "<RFC3339>",
  "modified": "<RFC3339>",
  "device_id": "<UUID>",
  "lamport": 42,
  "body": { /* kind-specific */ }
}
```

#### Categories synced

Per onboarding choice:

- Clipboard history (always, if sync is on)
- Snippets / pinboards (always, if sync is on)
- Settings / preferences (always, if sync is on)
- Download history (opt-in, separate toggle)

#### Conflict policy

Last-write-wins by `modified` timestamp, tie-broken first by `lamport` clock, then by `device_id` (lexicographic) as a final deterministic tie-break. Loser becomes a "version" record visible in a Settings → Sync → Resolve conflicts UI. Nothing is silently overwritten.

#### File watching

- `FSEventStream` for non-iCloud folders.
- `NSMetadataQuery` for iCloud Drive (handles placeholder/dataless files).
- For iCloud, call `NSFileManager.startDownloadingUbiquitousItem` on every record we see flagged as a placeholder so "Optimize Mac Storage" can't evict our data.

#### Real-world sync latency expectations

| Provider | Typical | Worst case |
|---|---|---|
| Dropbox | 1–3 s | ~10 s |
| Google Drive | 3–15 s | ~30 s |
| OneDrive | 10–60 s | few min |
| iCloud Drive | 30 s – several min | 10+ min (battery throttling) |
| Local folder | Instant (no sync) | — |

We auto-detect the cloud from the chosen path and show a chip in Settings: `iCloud Drive detected · ~30s sync` to set honest expectations.

## 6. Clipboard subsystem

### Capture (in `ClipboardDaemon`)

- Poll `NSPasteboard.general.changeCount` every **400 ms**. Standard pattern; cost is trivial.
- For each change, read all available representations: `public.utf8-plain-text`, `public.rtf`, `public.html`, `public.png`, `public.tiff`, `public.file-url`, plus `com.apple.finder.node` for Finder file copies.
- Honor the `org.nspasteboard.ConcealedType` UTI (1Password, Bitwarden, KeePassXC set this) — skip capture.
- Honor user-defined **app exclusion rules** by frontmost-app bundle ID.

### Storage

- Text/RTF/HTML stored inline in the SwiftData record (encrypted blob).
- Images and files stored as separate files in `App Group/blobs/<ULID>.bin`, encrypted, referenced by record. Keeps the SQLite DB small.
- Default cap: **10,000 items or 5 GB**, whichever first. LRU eviction. Configurable.

### Search

- FTS5 mirror table indexes plain text and OCR'd image text.
- OCR via **Vision framework** (`VNRecognizeTextRequest`) runs lazily on first capture, off the capture path so it never blocks. Result cached.

### Global hotkey + popup

- Hotkey registration via Carbon `RegisterEventHotKey` (only API that survives Cmd-Tab and works system-wide). Default: `⌘⇧V`. Configurable.
- Popup is an **NSPanel** with `.nonactivatingPanel` style so it appears without stealing focus — critical because it has to paste back into the previously-active app.
- Layout: horizontal carousel (Paste-style) with a search bar at top. Arrow keys navigate, `Return` pastes, `Tab` switches between History / Pinboards / Snippets, `⌘1`–`⌘9` paste recent items by position.
- Paste injection: synthesize `⌘V` to the previously-frontmost app via `CGEvent`. Requires Accessibility permission.
- Paste-as-plaintext: hold `⌥` while hitting `Return` to strip formatting on paste.

### Pinboards & snippets

- **Pinboards** = ordered groups of pinned clipboard items. Drag-and-drop in the popup to organize.
- **Snippets** = user-authored text/code, never captured from clipboard. Separate "Snippets" tab. Optional `;trigger`-style expansion via Accessibility text-injection.

### Rich-content polish (Full v1 scope)

- **Color picker:** detect hex/rgb in copied text → show swatch in row.
- **Code:** detect language by simple heuristic → syntax-highlight in preview using `Splash`.
- **Link preview:** detect URLs → fetch `<title>` + favicon asynchronously, cache. Privacy: configurable per-domain or fully off.
- **Icons / emoji search:** built-in symbol picker accessed from popup with `⌘E`.

### XPC between daemon and main app

- Daemon publishes a Mach service (`com.macallyouneed.daemon`).
- Main app connects on hotkey press, requests current items, subscribes to changes.
- Daemon survives main app quit. User can `⌘Q` the menu-bar UI; capture continues.

## 7. FolderPreview subsystem

Two surfaces, one rendering engine:

1. **Quick Look extension** in `FolderPreview.appex`, loaded by `qlmanage`.
2. **Standalone window** in main app, opened via menu-bar entry "Browse folder…", hotkey `⌘⇧F`, or — when the optional dock icon is enabled — by dropping a folder on the dock icon.

Engine code lives in `Shared/Platform/FolderPreview`.

### Quick Look extension constraints

- Sandboxed regardless of main app sandbox state. macOS gives the extension a temporary read-only handle to the previewed file.
- "Open / copy from preview" needs to act on files outside the sandbox → send XPC message to main app, which performs the action in unsandboxed context.
- Memory cap ~120 MB; render timeout ~30 s. Means: archive enumeration must be lazy, image thumbnails must be generated on demand, never eager-load a 10k-file folder.

### Folder enumeration & analysis (PeekX-inspired)

- `FileManager.enumerator` with `.skipsHiddenFiles` (configurable).
- Single pass collects: file count, subfolder count, total size, type breakdown (Images / Videos / Audio / Code / Documents / Archives / Other), 5 largest files.
- Folders >5,000 entries: enumeration on background `Task`, UI shows progress spinner, partial results stream in.

### View modes

- **Files** — sortable column list (name, size, kind, modified, dimensions, tags). Right-click column header → toggle/reorder columns. Customizable per folder via local `.macayn-view` sidecar (off by default).
- **Grid** — contact-sheet thumbnail grid for image-heavy folders. Auto-suggested when ≥40% of files are images. Thumbnails generated via `QLThumbnailGenerator`, cached in App Group container keyed by file inode + mtime.
- **Analyze** — PeekX-style breakdown: file-type pie/bar chart, largest files list.

### Archive previews

- **libarchive** (vendored, BSD license) for ZIP, RAR, 7z, TAR, GZ, BZ2.
- Archive root treated as a virtual folder. Same UI, marked with `🗄️` badge.
- Lazy extract on action: clicking a file inside an archive extracts to a temp dir, then opens. Never auto-extract whole archive.

### Open / copy actions

- Selection bar: `Open · Copy · Reveal in Finder · Quick Look`.
- "Open" → XPC to main app → `NSWorkspace.open(url)`. Works for files inside archives (extract-then-open).
- "Copy" → places file URL on `NSPasteboard`.

### Nested folder navigation

- Click any subfolder row → push navigation stack frame inside the same Quick Look window. Breadcrumb at top, ⌘← / ⌘→ navigate.
- "Expand all child folders" collapses tree into a single flat list (capped at 50,000 entries with a "Show more" pager).

### Standalone window mode

- Identical UI in a normal window. Opened via menu-bar entry "Browse folder…", hotkey `⌘⇧F` (configurable), or — when the optional dock icon is enabled — by dropping a folder on it.
- Extra capabilities vs Quick Look version: **multi-pane** (open two folders side-by-side for comparison) and **persistent window state** (reopens last folders on launch).

### Image thumbnail grid (PeekX-inspired contact sheet)

- Grid view: `QLThumbnailGenerator` thumbnails at 256×256, lazy-loaded as cells scroll into view.
- Click thumbnail → opens native Quick Look on that image.
- Supports HEIC, RAW (CR2/NEF/ARW via macOS RAW pipeline), GIF, WebP, AVIF, and standard formats.

## 8. Downloader subsystem

### Bundled binaries

- `yt-dlp` and `ffmpeg` in `Resources/`. Universal (arm64 + x86_64).
- First launch: `chmod +x` and verify SHA-256 against embedded manifest.
- "Check for downloader update" menu entry pulls latest `yt-dlp` from GitHub releases (yt-dlp updates frequently to track site changes).

### Process supervision

- One `Process` (NSTask) per download, launching `yt-dlp` with `--newline --progress --no-colors`.
- Concurrency: `TaskQueue` actor holds N concurrent slots (1–10, configurable).
- **Pause:** `SIGSTOP`. **Resume:** `SIGCONT`. **Cancel:** `SIGTERM`, fall back to `SIGKILL` after 3s. yt-dlp's `--continue` handles partial-file resume on retry.

### UI surfaces

- **Add download:** menu-bar dropdown → "Add download…" or hotkey `⌘⇧D`. Pre-fills if clipboard has a URL. Format-picker modal parses `yt-dlp --list-formats` output.
- **Active downloads view:** in menu-bar dropdown's Downloads tab. Each row: thumbnail, title, progress bar, speed, ETA, action menu.
- **History view:** completed downloads, sortable. Click row → reveal in Finder.

### Dock progress (v-download signature)

- `NSDockTile` with custom badge showing aggregate progress across all active downloads.
- `CALayer`-based progress fill (top-to-bottom) overlaid on dock icon.
- Bottom badge with current speed (e.g., `12 MB/s`), updated every 500 ms.
- All-downloads-finish: brief green checkmark animation + optional `UNUserNotificationCenter` notification.

> Note: app is LSUIElement by default (no dock icon). The user can flip "Show dock icon during downloads" in Settings to surface dock progress; otherwise progress shows in the menu-bar status icon.

### Browser cookie import

- Read Chrome / Edge / Brave / Arc cookies from each browser's SQLite cookie store (`~/Library/Application Support/<Browser>/Default/Cookies`).
- Chromium cookies are encrypted with a per-browser Keychain key ("Chrome Safe Storage" / "Brave Safe Storage" entries) — read via `SecItemCopyMatching`.
- Safari uses a binary plist at `~/Library/Cookies/Cookies.binarycookies` — separate parser.
- Export to Netscape-format `cookies.txt` consumed by yt-dlp via `--cookies`. Refresh on a 5-minute timer (matches v-download).
- Requires Full Disk Access (covered in onboarding).

### Crash recovery

- Each row in `downloads.sqlite` has a `state` column (`queued / running / paused / completed / failed`).
- On launch we scan for `running` rows and offer to **resume** them.
- Mid-download state (current bytes, current format) checkpointed every 5 seconds.

### Playlist / channel batch

- yt-dlp playlist support handles this natively via `--yes-playlist`.
- Output template: `~/Downloads/<channel>/<playlist>/<title> [<id>].<ext>` (configurable; sane defaults).
- Each item shown as a child row under the playlist parent in the UI.

### Local HTTP dispatch server stub (port 18765)

- `Network.framework` `NWListener` on `127.0.0.1:18765`.
- Endpoint `POST /dispatch` accepts `{"url": "...", "title": "..."}` and queues a download.
- Auth: shared secret in `App Group/dispatch.token`, regenerated each launch.
- v1: server runs but no extension talks to it. Lets us defer the Chrome extension while keeping the door open.

## 9. Menu-bar UI, onboarding, and integration

### Menu-bar entry

- `MenuBarExtra` (SwiftUI 14+) with custom popover content (not the default menu).
- Status icon: app glyph; subtle blue dot when a download is running or sync is in progress.
- Click → popover (~480 × 600 pt) with segmented control:

```
┌──────────────────────────────────────┐
│  Mac All You Need          ⚙  ⚡↻    │
├──────────────────────────────────────┤
│ [Clipboard] [Downloads] [Snippets]   │
├──────────────────────────────────────┤
│                                      │
│   tab content                        │
│                                      │
├──────────────────────────────────────┤
│ ⌘⇧V  Open clipboard popup            │
└──────────────────────────────────────┘
```

### Tabs

- **Clipboard** — recent items list (compact rows). Click row → paste-and-close. Same data as global popup but calmer presentation.
- **Downloads** — active + recent download rows. Add-button at top.
- **Snippets** — saved snippets, organized by pinboard.

### Settings (gear → opens separate window)

Sidebar sections:

- General
- Clipboard
- Downloads
- FolderPreview
- Sync
- Hotkeys (with conflict detection vs system shortcuts)
- Advanced (export diagnostic bundle, beta toggle, reset)

### Global hotkeys

| Default | Action |
|---|---|
| `⌘⇧V` | Open clipboard popup over current app |
| `⌘⇧D` | Open "Add download" dialog |
| `⌘⇧F` | Open standalone folder browser |
| `⌘1`–`⌘9` (in popup) | Paste recent item N |
| `⌘E` (in popup) | Open emoji / icon picker |

All rebindable.

### Onboarding wizard

Six steps, modal window with progress dots. Dismissible at any step (just-in-time prompts handle anything skipped). Re-runnable from Help menu.

1. **Welcome** — three-feature pitch with icons.
2. **Accessibility permission** — explain why (paste injection + snippet expansion). "Open System Settings" button. Polls `AXIsProcessTrusted()` and auto-advances on grant.
3. **Full Disk Access** — for cookie import + folder analysis. Same pattern, polls.
4. **Notifications** — request via `UNUserNotificationCenter`.
5. **Sync setup** — three options: "Set up sync now" (folder picker, auto-detect cloud), "Local only", "Decide later". Sets passphrase if sync is on.
6. **You're ready** — try it: "Press `⌘⇧V` to open your clipboard. Press Space on a folder in Finder to preview it."

### Cross-feature integration moments

- **Clipboard → Downloader:** if a copied URL is detected as video-bearing (small allowlist of domains + async `yt-dlp --simulate`), the clipboard row gets a small download button.
- **Downloader → FolderPreview:** completed download row has "Preview folder" → opens our standalone folder window on the destination directory.
- **FolderPreview → Clipboard:** "Copy" action in folder preview pushes file URL to clipboard, which then shows up in clipboard history with a file thumbnail.

## 10. Distribution, packaging, signing

### Code signing & notarization

- Apple Developer ID certificate ($99/yr).
- Pipeline: `xcodebuild archive` → `xcodebuild -exportArchive` → `notarytool submit --wait` → `stapler staple`.
- Quick Look extension and login-item helper signed with the same Developer ID; embedded provisioning profiles configured for app group entitlement.
- **Hardened Runtime** required. Entitlements:
  - `com.apple.security.cs.disable-library-validation` (loading vendored yt-dlp)
  - `com.apple.security.cs.allow-unsigned-executable-memory` (only if PyInstaller bundle requires)
  - `com.apple.security.application-groups` (the App Group)
  - `com.apple.security.automation.apple-events` (for paste injection target apps)

### Auto-updates

- **Sparkle 2** with EdDSA-signed appcast.
- Update channel: stable + beta. Settings toggle.
- Appcast hosted on a static site (GitHub Pages or similar — no backend needed).

### Distribution

- DMG built with `create-dmg` (background image, drag-to-Applications visual).
- Hosted on GitHub Releases for v1.

### License

Decision deferred to before public launch. Options to consider:

- MIT / Apache-2.0 (fully open)
- GPLv3 (forces forks open)
- PolyForm (gentle commercial restriction)
- Source-available + commercial license

Spec does not block on this.

## 11. Telemetry, logging, crash reporting

- **Sentry** (or self-hosted GlitchTip) for crash reports. **Opt-in only**, asked during onboarding.
- **No analytics in v1.** PostHog or similar is a potential v2 addition with full consent flow.
- Structured logs via `os.Logger`, subsystem `com.macallyouneed.<feature>`.
- "Export Diagnostic Bundle" in Settings → Advanced. Anonymized last-N-days logs.

## 12. Testing strategy

- **Unit tests (XCTest)** per Shared/Core module: storage, encryption round-trip, sync envelope encode/decode, conflict resolution, archive enumeration, cookie parser.
- **Integration tests** for sync: spin up two `Container` instances pointing at a temp folder, verify items propagate.
- **UI tests (XCUITest):** onboarding wizard happy path; menu-bar popover open/close; clipboard popup paste flow.
- **Manual test matrix** documented per release:
  - macOS 14.0 / 14.6 / 15.x
  - arm64 / x86_64 (Rosetta)
  - iCloud / Google Drive / Dropbox sync verified
- **Snapshot tests** for FolderPreview SwiftUI views (Quick Look extensions are notoriously hard to UI-test in `qlmanage`'s process).
- **CI/CD** on GitHub Actions: build, lint (SwiftLint, SwiftFormat), unit + integration tests on every PR. Release workflow on tag push: archive + notarize + upload DMG + publish appcast.

## 13. Future work / v2 backlog

Tracked TODOs for items deliberately out of scope for v1:

- [ ] **Chrome extension (Manifest V3)** — in-page video sniffing, site-specific buttons (YouTube/X/Douyin), cookie sync, URL dispatch via the v1 HTTP server stub. Single biggest v2 lift.
- [ ] **Native CloudKit sync option** — for users who want first-class iCloud without the folder-based latency. Co-exists with folder-based sync; user picks per-device.
- [ ] **Native Google Drive API sync** — alternative to folder-based for users who prefer the API path.
- [ ] **iOS / iPadOS companion app** — clipboard sync to iPhone, paste from Mac history. Requires CloudKit sync (above) or pivoting to a real backend.
- [ ] **Pinboard sharing / collaboration** — Paste's social feature. Needs a real backend or a structured share-via-link mechanism.
- [ ] **`⌘K` unified search palette** — search across clipboard, snippets, download history, recent folders.
- [ ] **Localization** — at minimum: Simplified Chinese, Japanese, German, Spanish, French.
- [ ] **Formal accessibility audit** — VoiceOver labels are present in v1, but no full audit. Required for a polished public product.
- [ ] **PostHog analytics (opt-in)** — anonymous usage stats, feature adoption funnel.
- [ ] **Three.js / 3D dock animation parity** — v-download has a Three.js loading animation; v1 uses SwiftUI animations. If users miss it, port to Metal.
- [ ] **Public website + landing page** — separate project; not in this spec.
- [ ] **Pricing model decision** — free, freemium (paid sync?), paid one-time, or subscription. Affects in-app purchase / license-key plumbing.

## 14. Open questions

None blocking. Deferred decisions noted inline (license, pricing, post-launch analytics).
