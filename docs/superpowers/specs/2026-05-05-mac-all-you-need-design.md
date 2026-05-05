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
| 12 | Owned SQLite is system of record; SwiftData only for transient UI binding | Cross-process SwiftData is fragile (private schema, single-writer assumptions). The daemon ↔ main app ↔ Quick Look extension split needs concurrent reads of stable on-disk files. SwiftData is kept for SwiftUI ergonomics on in-memory snapshots only. |
| 13 | Two-key encryption: non-portable local device key + passphrase-derived sync root key | Local blobs and indexes don't need to leave the Mac, so they're protected by a Keychain-only key (`...ThisDeviceOnly`). Sync envelopes use a portable Argon2id-derived key so the user can re-establish on a new Mac with their passphrase. Lost passphrase = unrecoverable sync ciphertext, surfaced explicitly. |
| 14 | Lamport-first conflict tie-break (then `modified`, then `device_id`) | Wall-clock first would let a single Mac with a skewed clock dominate every conflict. Lamport order makes ties deterministic regardless of clock state. |

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
│   ├── search.sqlite (+ -wal, -shm)       # owned FTS5 index, not SwiftData internals
│   └── settings.plist
├── blobs/                              # encrypted images, files, video thumbnails
├── thumbnails/                         # QLThumbnailGenerator cache for FolderPreview
└── dispatch.token                      # rotating shared secret for the local HTTP server
```

## 5. Data layer, encryption, and sync

### Storage

- **Owned SQLite** is the system of record for all durable data:
  - `clipboard.sqlite` for clipboard records and blob references.
  - `downloads.sqlite` for queue, history, and crash-recovery checkpoints.
  - `search.sqlite` for FTS5 mirror tables that index clipboard text, snippet text, OCR output, and downloader metadata.
- **SwiftData** is used only for transient UI binding — view models hold in-memory snapshots loaded from owned SQLite via the storage layer, with `@Observable` for SwiftUI propagation. SwiftData's persistent store is **not** the source of truth for any record. This avoids cross-process schema fragility and lets the daemon, main app, and Quick Look extension all read the same files concurrently without depending on SwiftData internals.
- Any FTS row is derived data and can be rebuilt from the owned record stores.
- WAL files live on the App Group container so all three processes can read concurrently. The daemon is the sole writer to `clipboard.sqlite`; the main app is the sole writer to `downloads.sqlite`.
- `search.sqlite` has one logical writer service. Prefer hosting `SearchIndexWriter` in the daemon because it survives the menu-bar UI; the main app sends index mutations over XPC. If the daemon is unavailable during startup/update, producers queue durable rebuild requests and the index is reconciled later from the owned source stores.
- XPC APIs return paginated metadata and stable blob IDs, never large blobs inline. Image/file previews are loaded by ID from `blobs/` or `thumbnails/` with cancellation and backpressure.

### Encryption

- User sets a passphrase during onboarding (skippable if sync is off).
- Two key domains:
  - **Local device key:** 256-bit random key generated on first launch, stored in Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. This protects local blobs and does not migrate to other Macs.
  - **Sync root key:** 256-bit key derived from the user's sync passphrase using **Argon2id**. KDF parameters and salt are versioned in `manifest.json`. This key is portable because the user can re-enter the passphrase on a new Mac.
- Per-record payload encryption: **AES-256-GCM** with a random nonce per record. Use CryptoKit's `AES.GCM.SealedBox.combined` representation for local and sync envelopes unless a custom encoder is explicitly introduced.
- Local indexes (timestamps, app IDs, file types, and post-decryption FTS tokens) stay queryable in cleartext within the local SQLite files. This is **local payload encryption**, not full local database confidentiality.
- For sync: the entire envelope is opaque ciphertext under the sync root key; even indexes and FTS tokens are encrypted in the sync representation.
- Passphrase changes create a new sync key version and re-encrypt envelopes in the background. Old key versions remain readable until re-encryption finishes. Lost sync passphrase means existing synced ciphertext cannot be recovered on a new device.

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
└── manifest.json                   # device list, schema version, KDF params, key version
```

#### Envelope format

```
CryptoKit AES.GCM.SealedBox.combined
```

The combined representation is `nonce + ciphertext + tag`. The implementation should not hard-code a custom nonce/tag layout unless tests pin that exact encoding.

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

Last-write-wins by `lamport` clock, tie-broken by `modified` timestamp, then by `device_id` (lexicographic) as a final deterministic tie-break. Wall-clock time is useful for display and approximate recency, but Lamport order prevents a Mac with a bad clock from dominating every conflict. Loser becomes a "version" record visible in a Settings → Sync → Resolve conflicts UI. Nothing is silently overwritten.

#### File watching

- `FSEventStream` for non-iCloud folders.
- `NSMetadataQuery` for iCloud Drive (handles placeholder/dataless files).
- For iCloud, call `FileManager.startDownloadingUbiquitousItem(at:)` for placeholder records, but only through a throttled hydration queue. Cap concurrent hydrations, retry with exponential backoff, and prioritize manifest/key material before bulk clipboard blobs so "Optimize Mac Storage" cannot cause a sync stampede.

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

- Daemon publishes a Mach service whose name is derived from the App Group identifier, e.g. `group.com.macallyouneed.shared.daemon`. The exact name must be validated in a signing/provisioning spike because sandboxed extensions can only reach services allowed by their entitlements and app group.
- Main app connects on hotkey press, requests current items, subscribes to changes.
- FolderPreview may use the same service only after a prototype proves the Quick Look extension can reach it under the final entitlements. If that proof fails, Quick Look falls back to extension-local actions plus "Open in Mac All You Need".
- Daemon survives main app quit. User can `⌘Q` the menu-bar UI; capture continues.
- Service API shape:
  - `listClipboardItems(query, pageToken, limit)` → metadata page + next token.
  - `resolveBlob(blobID)` → App Group file URL for encrypted blob/thumbnail material, or a security-scoped bookmark only when the target is an external user file.
  - `paste(itemID, mode)` → daemon/main app performs paste injection into the previously-frontmost app.
  - Streaming updates use small invalidation events (`itemAdded`, `itemUpdated`, `itemDeleted`) rather than pushing full records.

## 7. FolderPreview subsystem

Two surfaces, one rendering engine:

1. **Quick Look extension** in `FolderPreview.appex`, loaded by `qlmanage`.
2. **Standalone window** in main app, opened via menu-bar entry "Browse folder…", hotkey `⌘⇧F`, or — when the optional dock icon is enabled — by dropping a folder on the dock icon.

Engine code lives in `Shared/Platform/FolderPreview`.

### Quick Look extension constraints

- Sandboxed regardless of main app sandbox state. macOS gives the extension a temporary read-only handle to the previewed file.
- "Open / copy from preview" may require acting on files outside the extension sandbox. The implementation path is:
  1. Prefer extension-local read-only actions when the temporary Quick Look file access is sufficient.
  2. For actions that need the unsandboxed main app, send a minimal request over the App Group XPC service and include a security-scoped bookmark if available.
  3. If XPC or bookmark handoff fails, show "Open in Mac All You Need" and let the standalone app request/perform the action.
- Memory cap ~120 MB; render timeout ~30 s. Means: archive enumeration must be lazy, image thumbnails must be generated on demand, never eager-load a 10k-file folder.
- Technical spike required before implementation: verify Quick Look extension → App Group XPC → login item/main app communication under the exact Developer ID signing, App Group entitlement, sandbox entitlement, and hardened runtime settings.

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
- Archive safety requirements:
  - Reject absolute paths, `..` traversal, and paths that normalize outside the extraction root.
  - Treat symlinks and hardlinks as metadata unless the user explicitly extracts; never follow links during preview enumeration.
  - Cap total enumerated entries, total uncompressed bytes, maximum nesting depth, and per-file extraction size to avoid archive bombs.
  - Extract into an app-owned temporary directory with randomized names and remove it on preview close or app relaunch cleanup.

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
- Build pipeline signs the nested executables as part of the app bundle before notarization. First launch verifies SHA-256 against the embedded signed manifest and refuses to run a mismatched binary.
- "Check for downloader update" menu entry pulls a newer `yt-dlp` package from GitHub releases (yt-dlp updates frequently to track site changes).
- Updated downloader binaries are stored outside the notarized app bundle in the App Group container:
  - Download update package and signed update manifest.
  - Verify manifest signature, expected SHA-256, executable bit, architecture, and minimum version monotonicity.
  - Strip or handle quarantine attributes intentionally after verification.
  - Keep previous working downloader as rollback.
  - Prefer appcast-style EdDSA signing for downloader updates so SHA-256 is authenticated by a key embedded in the app.

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

- Discover Chrome / Edge / Brave / Arc profiles (`Default`, `Profile 1`, `Profile 2`, etc.) and read each profile's SQLite cookie store.
- Chromium cookies are encrypted with a per-browser Keychain key ("Chrome Safe Storage" / "Brave Safe Storage" entries) — read via `SecItemCopyMatching`.
- Safari uses a binary cookie store — separate parser, with explicit unsupported/failure states if current macOS permissions or schema prevent reliable access.
- Export to Netscape-format `cookies.txt` consumed by yt-dlp via `--cookies`. Refresh on a 5-minute timer (matches v-download).
- Requires Full Disk Access for broad browser-profile access. If unavailable, the downloader still works without cookies and prompts per failed protected-site download.
- Handle locked databases by copying the cookie DB plus WAL/SHM files to a temporary read location before parsing. Treat schema changes as parser-version failures with diagnostics, not crashes.

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
- Security requirements:
  - Bind only to loopback.
  - Require `Authorization: Bearer <token>` on every request.
  - Restrict CORS to the future extension origin; reject generic browser origins in v1.
  - Reject non-JSON content types, oversized payloads, and private-file URL schemes.
  - Add request nonce/timestamp validation once an extension client exists.
- Future extension token handoff is unresolved because browser extensions cannot read the App Group container directly. v1 may run the server for local dispatch tests, but the v2 extension must define a pairing/token exchange flow before shipping.

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

Six steps, modal window with progress dots. Dismissible at any step (just-in-time prompts handle anything skipped). Re-runnable from Help menu. Permission steps are capability checks, not mandatory blockers: the feature that needs the permission remains disabled/degraded until the permission is granted.

1. **Welcome** — three-feature pitch with icons.
2. **Accessibility permission** — explain why (paste injection + snippet expansion). "Open System Settings" button. Polls `AXIsProcessTrusted()` and auto-advances on grant.
3. **Full Disk Access** — for browser cookie import and protected folder analysis. Same pattern, polls. If skipped, cookie-backed downloads and protected-folder inspection show just-in-time prompts later.
4. **Notifications** — request via `UNUserNotificationCenter`.
5. **Sync setup** — three options: "Set up sync now" (folder picker, auto-detect cloud), "Local only", "Decide later". Sets passphrase if sync is on.
6. **You're ready** — try it: "Press `⌘⇧V` to open your clipboard. Press Space on a folder in Finder to preview it."

### TCC and protected-resource behavior

- Accessibility is required for paste injection (the popup synthesizing `⌘V` into the previously-frontmost app) and for snippet `;trigger` expansion. Without it: clipboard capture, local history, search, the menu-bar popover, and the global popup window all still work; paste-back is degraded — the user manually presses `⌘V` after the popup writes the selected item to the system pasteboard, or invokes the row's "Copy" action. Snippet trigger expansion is disabled and surfaced as a banner in the Snippets tab.
- Full Disk Access is required for broad browser-cookie import and some protected-folder analysis. Basic downloads, user-picked folders, and Quick Look previews still work without it.
- Notifications are optional. Completion state is always visible in the menu-bar Downloads tab.
- Every permission-dependent action has a deterministic fallback state and a diagnostics entry; no feature should fail silently because a TCC permission is missing.

### Cross-feature integration moments

- **Clipboard → Downloader:** if a copied URL is detected as video-bearing (small allowlist of domains + async `yt-dlp --simulate`), the clipboard row gets a small download button.
- **Downloader → FolderPreview:** completed download row has "Preview folder" → opens our standalone folder window on the destination directory.
- **FolderPreview → Clipboard:** "Copy" action in folder preview pushes file URL to clipboard, which then shows up in clipboard history with a file thumbnail.

## 10. Distribution, packaging, signing

### Code signing & notarization

- Apple Developer ID certificate ($99/yr).
- Pipeline: `xcodebuild archive` → `xcodebuild -exportArchive` → `notarytool submit --wait` → `stapler staple`.
- Quick Look extension and login-item helper signed with the same Developer ID; embedded provisioning profiles configured for app group entitlement.
- Nested executables (`yt-dlp`, `ffmpeg`, and any helper shims) are signed during archive/export and included in notarization. Post-install downloader updates are verified and stored outside the app bundle as described in §8.
- **Hardened Runtime** required. Entitlements:
  - `com.apple.security.application-groups` (main app, login item, and Quick Look extension all share the App Group).
  - `com.apple.security.automation.apple-events` only if implementation uses Apple Events for target-app automation. CGEvent paste injection is primarily governed by Accessibility/TCC, not this entitlement alone.
  - `com.apple.security.cs.disable-library-validation` only if a measured dependency-loading failure requires it. It is not the default way to launch signed bundled executables.
  - `com.apple.security.cs.allow-unsigned-executable-memory` only if a measured PyInstaller/embedded-runtime issue requires it; avoid by preferring native signed helper binaries.
- Signing spike required:
  - Confirm App Group container availability for Developer ID distribution across main app, login item, and Quick Look extension.
  - Confirm the Quick Look extension can reach the intended App Group XPC service.
  - Confirm updated downloader binaries can be executed from the App Group container after signature/hash verification.

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
- **Crypto tests:** pin KDF parameter serialization, key-version upgrades, AES-GCM combined envelope compatibility, wrong-passphrase failures, passphrase rotation, and lost-key behavior.
- **Storage/search tests:** verify FTS rebuild from owned SQLite stores, WAL concurrent read behavior, pagination, blob ID lookup, and cancellation.
- **Archive security tests:** path traversal, symlink/hardlink entries, archive bombs, huge file counts, nested archives, and cleanup of temp extraction roots.
- **Downloader binary tests:** manifest signature verification, hash mismatch rejection, rollback after failed update, architecture mismatch, and execution from App Group update path.
- **Cookie import tests:** Chromium multi-profile discovery, locked DB copy including WAL/SHM, missing Keychain key, schema mismatch, and Safari parser failure mode.
- **XPC/signing manual spike tests:** Quick Look extension → App Group XPC reachability, daemon ↔ main app paging, permission-denied fallbacks, and helper persistence after main app quit.
- **UI tests (XCUITest):** onboarding wizard happy path; menu-bar popover open/close; clipboard popup paste flow.
- **Manual test matrix** documented per release:
  - macOS 14.0 / 14.6 / 15.x
  - arm64 / x86_64 (Rosetta)
  - iCloud / Google Drive / Dropbox sync verified
  - Accessibility denied/granted
  - Full Disk Access denied/granted
  - Quick Look preview from normal, iCloud placeholder, protected, and external-volume folders
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

Technical questions that must be answered by proof-of-concept spikes before implementation hardens:

- Can a Developer ID distributed main app, login item, and Quick Look extension all share the intended App Group container and XPC service under final entitlements?
- Does Quick Look → App Group XPC → main app/helper work reliably when launched by Finder/`qlmanage`, including after the main app is quit?
- What exact signing/notarization path works for bundled and post-install updated `yt-dlp` binaries?
- What is the final sync key recovery story: passphrase-only, recovery key, or no recovery?
- What TCC-denied fallbacks are acceptable for paste injection, cookie import, and protected folder analysis?
- How will the future browser extension obtain the local dispatch token if it cannot read the App Group container?
- Which license/pricing model applies before public launch, since it can affect update channels, feature gating, and downloader-update infrastructure?
