# Feature B — Finder Folder History

Date: 2026-05-30
Status: Spec in review
Parent: [`00-roadmap.md`](./00-roadmap.md)
Feature flag / descriptor: new gated `FeatureDescriptor` (`FeatureID.finderHistory`)
New permission: Automation / Apple Events (**opt-in only**, lazy)
New target: FinderSync `.appex` (`com.macallyouneed.app.finderhistory`)
Shared infra consumed: **S1 `AXObserverCoordinator`**

---

## 1. Summary

Finder Folder History silently records the folders a user opens in Finder and
lets them jump back to any of them later — including after the original Finder
window has been closed. It is, effectively, a "recently visited folders" memory
layered on top of Finder, which has no such durable list of its own.

Capture is **passive observation**, not polling of the filesystem: an
`AXObserver` is attached to the Finder process and reports focused-window and
title changes; the folder's POSIX path is read from `kAXDocumentAttribute`. This
reuses the Accessibility permission MAYN already holds (WindowControl, snippets,
CGEventTap) and adds **no new mandatory permission**. A single opt-in Apple Event
fallback resolves the path for the small set of special folders where
`kAXDocumentAttribute` is empty.

Visited folders are stored in a new encrypted GRDB `FolderHistoryStore` inside
the shared App Group container, one row per path, with visit count and
first/last-visited timestamps. Three runtime surfaces let the user act on the
history: a **global hotkey quick-switcher** (modeled on the Cmd-Shift-V
clipboard popup), a **menu-bar / Command Center dropdown**, and a **FinderSync
toolbar button** that lives inside Finder windows. Re-opening a folder reuses the
same `NSWorkspace` calls as Folder Preview's browse coordinator.

The main-window page is **configuration and guidance only** — settings,
permission status, and how-to. Browsing and management (pin / remove) happen
inline in the switcher and dropdown, not on a dedicated management page.

Because logging the folders a person visits is privacy-sensitive, the feature is
**disabled by default**, requires **explicit onboarding consent**, exposes a
**pause toggle**, and honors an **exclusion list**.

---

## 2. Goals / Non-goals

### Goals

- Capture every meaningful Finder folder navigation with no new mandatory
  permission and negligible CPU cost (event-driven, not polling).
- Persist a deduplicated, ranked folder history that survives Finder window
  closure, app quit, and reboot.
- Provide fast recall through a keyboard-first global switcher, a menu-bar
  dropdown, and an in-Finder FinderSync toolbar button.
- Re-open or reveal any remembered folder reliably, degrading gracefully when
  the path is stale or deleted.
- Treat folder-visit logging as sensitive: off by default, consented,
  pausable, and filterable via exclusions.
- Ship as a fully gated `FeatureDescriptor` consistent with the other six tools
  (dashboard card, onboarding, enable/disable through `FeatureRuntime`).

### Non-goals

- **Not** a file browser or a folder-management surface. The main page never
  lists history; it only configures the feature. (Roadmap decision §"Locked
  product decisions" #6.)
- **Not** a recents list for files — folders only.
- **Not** a Spotlight/`FSEvents` filesystem crawler. We record what the user
  actually opened in Finder, nothing else.
- **No** sync (Plan 2 is skipped indefinitely).
- **No** content indexing of folder contents.
- The Apple Events fallback is **not** required for the feature to function; the
  AX path covers the overwhelming majority of folders.

---

## 3. Full feature scope

1. **Passive capture** of Finder folder navigations via `AXObserver` on the
   Finder PID, with debounce + dedup, an exclusion list, and skip rules for
   Desktop / Trash / transient search windows.
2. **Opt-in Apple Event path resolution** for special folders where
   `kAXDocumentAttribute` is empty (e.g. some "smart"/special locations). Lazy:
   the Apple Event is only ever sent after the user explicitly enables the
   fallback, and only when AX returns no path.
3. **Durable storage** in an encrypted GRDB `FolderHistoryStore` in the App
   Group, one row per path, with visit metadata, pin state, and a lazily
   refreshed `exists` flag. Retention reuses existing `RetentionPolicy`
   machinery; pinned rows are exempt.
4. **Global hotkey quick-switcher**: a searchable borderless floating panel,
   recent-first with pinned on top, showing Finder icon + display name + path +
   relative time. `Return` opens in Finder; `Opt-Return` reveals. Inline
   pin/remove.
5. **Menu-bar dropdown / Command Center tab**: recent folders with inline
   pin/remove, mirroring the switcher data source.
6. **FinderSync toolbar button**: a "Recent Folders" button inside Finder
   windows (new sandboxed `.appex`), reading the shared store via App Group.
7. **Config/guidance main page**: retention, exclusions (via the existing
   exclusion-editor pattern), Apple-Events fallback toggle, permission status,
   pause toggle, and a how-to. No browse/management list.
8. **Privacy controls**: feature flag (off by default), onboarding consent,
   pause toggle, exclusions, and a "clear history" action.

---

## 4. Architecture & components

```
                 NSWorkspace.didActivateApplicationNotification (Finder activated)
                                  │
                                  ▼
   AXObserverCoordinator (S1) ── attaches AXObserver to Finder PID ──┐
     • kAXFocusedWindowChangedNotification                           │
     • kAXTitleChangedNotification                                   │
     • health-check timer re-subscribe (Finder rebuilds AX tree)     │
                                  │                                   │
                                  ▼                                   │
   FolderHistoryRecorder (@MainActor, main app)                      │
     • read kAXDocumentAttribute → POSIX path                        │
     • (opt-in) Apple Event fallback if path empty                   │
     • skip rules (Desktop/Trash/search) + exclusion list           │
     • debounce + 5s same-path dedup                                 │
                                  │                                   │
                                  ▼                                   │
   FolderHistoryStore (GRDB, App Group, encrypted) ◄────────────────┘
     • one row per path, upsert visitCount / lastVisited
     • RetentionPolicy enforcement (pinned exempt)
                ▲                          ▲                  ▲
                │ read                     │ read             │ read (App Group)
   ┌────────────┴───────┐   ┌─────────────┴─────┐   ┌────────┴──────────────┐
   │ Hotkey switcher    │   │ Menu-bar / Command │   │ FinderSync .appex     │
   │ (borderless NSPanel)│  │ Center dropdown    │   │ "Recent Folders" btn  │
   └────────────────────┘   └───────────────────┘   └───────────────────────┘
                │ open/reveal               │ open/reveal       │ open/reveal
                ▼                           ▼                   ▼
         NSWorkspace.shared.open(url) / activateFileViewerSelecting([url])
```

### 4.1 `FolderHistoryRecorder` (main app, `@MainActor`)

Owns capture logic. Responsibilities:

- Subscribe to `NSWorkspace.shared.notificationCenter` for
  `didActivateApplicationNotification`; when Finder becomes frontmost (and on
  feature start if Finder is already running), ensure the `AXObserver` is
  attached to the Finder PID via S1.
- Receive S1 callbacks for `kAXFocusedWindowChangedNotification` and
  `kAXTitleChangedNotification`, read the focused window element, and copy
  `kAXDocumentAttribute` (a `file://` URL string for the displayed folder).
- Apply **skip rules** (§9) and the **exclusion list** before recording.
- Apply **debounce + dedup**: a same-path visit within ~5 s coalesces into a
  `lastVisited` / `visitCount` update rather than a new conceptual visit. This
  mirrors the clipboard 0.5 s same-copy window but with a longer 5 s window
  because folder focus churns more than clipboard copies (see
  `LocalClipboardReader.deduplicate` at
  `MacAllYouNeed/App/LocalClipboardReader.swift:154`).
- On an empty `kAXDocumentAttribute`, optionally invoke the Apple Event fallback
  (§7) — only if the user enabled it.
- Respect the **pause toggle** and the **feature flag**: when paused or
  disabled, the recorder detaches the observer entirely (no observation, no
  storage writes).

This is the analogue of `LocalClipboardReader` but **event-driven instead of
polling** — there is no 1 s timer in the steady state; the only timer is S1's
health-check re-subscribe.

### 4.2 `AXObserverCoordinator` (S1, shared infra)

Built once per the roadmap (`00-roadmap.md` §S1). It owns `AXObserverCreate`, the
run-loop source, notification registration, and a periodic liveness re-subscribe
timer. The recorder uses it instead of hand-rolling AX observation. The existing
ad-hoc AX usage that S1 generalizes lives in
`MacAllYouNeed/WindowControl/WindowControlCoordinator.swift` (focused-window
resolution at `WindowControlCoordinator.swift:358-383`); S1 lifts that pattern
into a reusable type. Finder is one of the two known apps (with the Dock) that
silently rebuilds its AX tree, so the health-check re-subscribe is load-bearing
here.

The trust/permission lifecycle reuses the existing monitor shape in
`MacAllYouNeed/WindowControl/WindowControlAccessibilityTrustMonitor.swift`
(`AXIsProcessTrusted()` + `didBecomeActiveNotification` + a poll), so the feature
flips to a "needs Accessibility" state if trust is revoked, exactly like
WindowControl.

### 4.3 `FolderHistoryStore` (Shared `Core`, GRDB, App Group)

New store following the `DownloadStore` pattern
(`Shared/Sources/Core/Storage/DownloadStore.swift:5-30`): a thin class over the
shared `Database` with a static `migrations: [Migration]` array, init taking
`Database` + `SymmetricKey`. Differences from `DownloadStore`:

- **Upsert by path** (path is the unique key) instead of insert-by-UUID, so a
  re-visit increments `visitCount` and bumps `lastVisited`.
- Columns the surfaces filter/sort on (`last_visited`, `pinned`, `path`) are
  promoted to real SQL columns + an index, while the human-facing display name
  stays inside the encrypted envelope (same envelope-blob approach as
  `DownloadStore`). Path itself is sensitive but must be unique/queryable; see
  §5 and §11 for the encryption-vs-uniqueness tradeoff.

Lives in the App Group so the FinderSync `.appex` can read it. Reuses the
existing `Database` opener (`Shared/Sources/Core/Storage/Database.swift:8-28`,
WAL + `busy_timeout = 5000`, which is what makes concurrent main-app + appex
reads safe).

### 4.4 The three surfaces

- **Hotkey quick-switcher** — borderless `NSPanel` floating list, modeled on the
  Cmd-Shift-V clipboard popup and the existing borderless-panel pattern
  (`MacAllYouNeed/Settings/Hotkey/KeyboardShortcutFloatingOverlayController.swift:8`,
  `styleMask = [.borderless, .nonactivatingPanel]`). SwiftUI content inside.
- **Menu-bar dropdown / Command Center tab** — a new tab/section listing recent
  folders, supplied through the descriptor's `menuBarItemFactory`
  (`FeatureDescriptor.menuBarItemFactory`,
  `Shared/Sources/FeatureCore/FeatureDescriptor.swift:54`).
- **FinderSync `.appex`** — new sandboxed extension target (§4.5).

All three read the **same** `FolderHistoryStore` and route open/reveal through
the same `NSWorkspace` calls.

### 4.5 FinderSync `.appex`

A new `app-extension` target added to `project.yml` and regenerated with
`xcodegen generate`, modeled structurally on the existing FolderPreview
extension block (`project.yml:159-190`). Differences:

- `NSExtensionPointIdentifier`: `com.apple.FinderSync` (principal class subclasses
  `FIFinderSync`).
- Bundle ID: `com.macallyouneed.app.finderhistory`; embedded in
  `Contents/PlugIns/`.
- Entitlements: App Sandbox (FinderSync extensions are **always** sandboxed) +
  the shared App Group `group.com.macallyouneed.shared` so it can open the
  `FolderHistoryStore` read-only.
- Descriptor wiring: `osExtensionPolicy = .staticBundleExtension(...)` with
  `respectsFeatureFlag: true` (mirrors FolderPreview at
  `MacAllYouNeed/App/Descriptors/FolderPreviewDescriptor.swift:13-17`).

The extension provides a single toolbar item ("Recent Folders") via
`FIFinderSync`'s toolbar API; clicking it shows a menu of recent/pinned folders
built from the store, and selecting one opens it. See §7 for FinderSync
constraints.

### 4.6 `FinderHistoryDescriptor` + registration

New `FeatureDescriptor` factory (mirroring
`MacAllYouNeed/App/Descriptors/FolderPreviewDescriptor.swift:4-22`), registered
in `MacAllYouNeed/App/FeatureRegistryProvider.swift:6-12` alongside the other six.
Adds:

- `FeatureID.finderHistory` to
  `Shared/Sources/FeatureCore/FeatureID.swift:3-10`.
- `MainAppDestination.finderHistory` to
  `MacAllYouNeed/App/MainAppDestination.swift:3-12` (title/subtitle/symbol +
  inclusion in `primarySidebarDestinations`). Disabled state stays visible but
  inert per the hard UI rule.
- A `HotkeyDescriptor` for the switcher (e.g.
  `finderHistory.switcher`), declared on the descriptor like FolderPreview's
  browse hotkey (`FolderPreviewDescriptor.swift:12`) and surfaced through
  `HotkeyRegistry.declaredHotkeys` (`MacAllYouNeed/App/HotkeyRegistry.swift:139`).

---

## 5. Data model / storage

### 5.1 Schema

New table `folder_history` in the shared App Group database. Following
`DownloadStore`'s split of queryable columns + encrypted envelope:

| Column | Type | Notes |
|---|---|---|
| `path` | TEXT, **UNIQUE NOT NULL** | POSIX path; the natural key. Upsert target. |
| `first_visited` | INTEGER NOT NULL | ms since epoch. |
| `last_visited` | INTEGER NOT NULL | ms since epoch. Sort key. |
| `visit_count` | INTEGER NOT NULL DEFAULT 1 | Incremented on dedup coalesce. |
| `pinned` | INTEGER NOT NULL DEFAULT 0 | 0/1. Retention-exempt + sorted on top. |
| `exists_flag` | INTEGER NOT NULL DEFAULT 1 | Lazily refreshed; 0 = path missing at last check. |
| `envelope` | BLOB NOT NULL | Encrypted JSON: `displayName` and any future non-indexed fields, sealed with the device key via `Cipher.seal` exactly as `DownloadStore.insert` does (`DownloadStore.swift:33-49`). |

Index:

```
CREATE INDEX IF NOT EXISTS idx_folder_history_last_visited
    ON folder_history(last_visited);
```

`path` is `UNIQUE`, which gives an implicit index for the upsert and exclusion
lookups.

**Encryption note:** `displayName` lives inside the encrypted envelope. `path`
must be stored as plaintext-in-column because it is the uniqueness key and the
exclusion/skip filters query it; this is the same tradeoff `DownloadStore` makes
with its `state` column. The privacy mitigation is the feature gate + consent +
the fact that the DB lives in the App Group container, not the encryption of the
path itself. See §11.

### 5.2 Migration

Add `FolderHistoryStore.migrations` as a static `[Migration]` (pattern:
`DownloadStore.migrations`, `DownloadStore.swift:15-30`), e.g. identifier
`001-folder-history`, registered through the same `Database(url:migrations:)`
path used for every other store (`Database.swift:22-26`,
`DatabaseMigrator.registerMigration`). The migrator is idempotent, so re-runs are
safe.

### 5.3 Retention

Reuse the existing `RetentionPolicy` shape
(`Shared/Sources/Core/Storage/RetentionPolicy.swift:3-12`,
`maxItems` / `maxAgeSeconds`) with **pinned rows treated as protected**, exactly
like pinboard items are protected from clipboard retention
(`RetentionPolicy.protectedIDs(from:)`, `RetentionPolicy.swift:98-104`). Concretely:

- A `maxItems` cap evicts the least-recently-visited unpinned rows (tail of the
  `last_visited DESC` ordering — the same "victims at the tail" logic as
  `RetentionPolicy.enforceItemCap`, `RetentionPolicy.swift:15-31`).
- A `maxAgeSeconds` cutoff evicts unpinned rows whose `last_visited` is older
  than the cutoff (mirror of `enforceMaxAge`, `RetentionPolicy.swift:33-46`).
- `maxImageBytes` does not apply (no blobs).

If a generic `protectedIDs`-based path is awkward to reuse verbatim (it is keyed
to `ClipboardStore`/`BlobStore`/`SearchStore`), the store implements equivalent
SQL eviction directly but keeps the **same policy fields and pinned-exempt
semantics**. Either way, no new retention concept is introduced.

---

## 6. Integration seams (real `file:line` references)

| Concern | Reuse / extend | Reference |
|---|---|---|
| Focused-window AX read (S1 source pattern) | `resolveFocusedWindow()` — `AXUIElementCreateApplication(pid)` + `AXUIElementCopyAttributeValue(..., kAXFocusedWindowAttribute, ...)` | `MacAllYouNeed/WindowControl/WindowControlCoordinator.swift:358-383` |
| Accessibility trust monitoring / revocation handling | `AXIsProcessTrusted()` + `didBecomeActiveNotification` + poll | `MacAllYouNeed/WindowControl/WindowControlAccessibilityTrustMonitor.swift:18-99` |
| Open folder in Finder | `NSWorkspace.shared.open(url)` | `MacAllYouNeed/FolderPreview/BrowseFolderCoordinator.swift:9-10` |
| Reveal folder in Finder | `NSWorkspace.shared.activateFileViewerSelecting([url])` | `MacAllYouNeed/FolderPreview/BrowseFolderCoordinator.swift:14-15` |
| Debounce / dedup precedent | 0.5 s same-copy coalescing | `MacAllYouNeed/App/LocalClipboardReader.swift:154-170` |
| Store class shape + migrations + encrypted envelope | `DownloadStore` + `migrations` + `Cipher.seal` | `Shared/Sources/Core/Storage/DownloadStore.swift:5-49` |
| Migration registration | `Database(url:migrations:)` + `DatabaseMigrator` | `Shared/Sources/Core/Storage/Database.swift:8-28`; `Shared/Sources/Core/Storage/Migrations.swift:4-12` |
| Retention + pinned-exempt | `RetentionPolicy` + `protectedIDs` | `Shared/Sources/Core/Storage/RetentionPolicy.swift:15-46,98-104` |
| App Group container / DB location | `AppGroup.identifier`, `AppGroup.containerURL()` | `Shared/Sources/Core/AppGroup.swift:4,19-32` |
| FeatureDescriptor pattern + extension policy | `FolderPreviewDescriptor.descriptor()` | `MacAllYouNeed/App/Descriptors/FolderPreviewDescriptor.swift:4-22` |
| Descriptor registration | `FeatureRegistry(descriptors:[...])` | `MacAllYouNeed/App/FeatureRegistryProvider.swift:6-12` |
| FeatureID enum | add `finderHistory` | `Shared/Sources/FeatureCore/FeatureID.swift:3-10` |
| Main sidebar destination | add `finderHistory` | `MacAllYouNeed/App/MainAppDestination.swift:3-24` |
| Declared hotkey surfacing | `declaredHotkeys(from:)` | `MacAllYouNeed/App/HotkeyRegistry.swift:139` |
| `.appex` target template | FolderPreview `app-extension` block | `project.yml:159-190` |
| Borderless floating panel (switcher chrome) | `[.borderless, .nonactivatingPanel]` panel | `MacAllYouNeed/Settings/Hotkey/KeyboardShortcutFloatingOverlayController.swift:8` |
| Exclusion editor UI pattern | `BundleIDExclusionEditor` / `RegexExclusionEditor` | `MacAllYouNeed/Settings/SettingsExclusionEditor.swift:6-241` |
| Permission card / row | `AccessibilityPermissionRow` + `PermissionCard` | `MacAllYouNeed/Settings/Permissions/AccessibilityPermissionRow.swift:3-18` |
| Menu-bar item factory | `FeatureDescriptor.menuBarItemFactory` | `Shared/Sources/FeatureCore/FeatureDescriptor.swift:54` |

---

## 7. Permissions

### 7.1 Accessibility (reused, no new prompt)

Capture uses the Accessibility permission MAYN already requires for
WindowControl, snippets, and the CGEventTap. No new TCC prompt. If the user has
not granted Accessibility, the feature shows a "needs Accessibility" state and
routes to the existing Accessibility card
(`AccessibilityPermissionRow.swift:3-18`); it never hard-fails. Trust revocation
is detected by the existing monitor shape
(`WindowControlAccessibilityTrustMonitor.swift`).

### 7.2 Automation / Apple Events (opt-in, lazy)

The Apple Event fallback ("get target of front Finder window" → resolve POSIX
path) triggers the **Automation** TCC prompt the first time it runs against
Finder. Therefore:

- It is **off by default** and exposed as an explicit toggle on the config page
  ("Resolve special folders — uses Apple Events; macOS will ask permission once").
- The Apple Event is **lazy**: even with the toggle on, we only send it when
  `kAXDocumentAttribute` is empty for a window we would otherwise record.
- If the user denies the prompt, we record nothing for those special folders and
  do not re-prompt; the AX path continues unaffected.
- Requires `NSAppleEventsUsageDescription` in the main app Info.plist and the
  `com.apple.security.automation.apple-events` consideration. The main app is
  **not** sandboxed (roadmap §"Locked product decisions" #7), so this is a TCC
  prompt only, not an entitlement gate.

### 7.3 FinderSync sandbox + App Group

The FinderSync `.appex` is **always sandboxed**. It needs:

- App Sandbox entitlement (extension default).
- The shared App Group `group.com.macallyouneed.shared` to read the
  `FolderHistoryStore` from the shared container
  (`AppGroup.identifier`, `AppGroup.swift:4`).
- It does **not** write history (capture is the main app's job). It only reads
  recent/pinned rows and issues open/reveal. Pin/remove from the FinderSync menu,
  if offered, writes through the shared store — but the primary management
  surfaces are the switcher and dropdown.

FinderSync constraints to honor:

- A FinderSync extension's toolbar/menu items and "directory of interest" model
  are limited; the toolbar button is always present but its menu is built on
  demand. We do **not** rely on FinderSync's directory-monitoring for capture —
  capture is AX-based in the main app. FinderSync here is purely a **reader/launcher
  surface**.
- The extension runs in its own process; it must open the DB read-only with the
  same WAL config (`Database.swift:9-15`) to coexist with the main app's writer.

---

## 8. UI / UX

All UI complies with `design.md` and the hard rules in `CLAUDE.md`:
`MAYNTheme` / `MAYNControlMetrics` / `MAYNMotion` / `MAYNMotionBridge` only;
`FunctionSegmentedTabStrip` for any segmented choice; `ShortcutChip` /
`MAYNHotkeyDisplay` for read-only hotkeys; `HotkeyRecorder` only in settings;
`FunctionPageShell` for the tool page; borderless `NSPanel` + SwiftUI for the
floating switcher; Reduce Motion honored.

### 8.1 Hotkey quick-switcher (primary surface)

- Borderless floating `NSPanel` (`[.borderless, .nonactivatingPanel]`,
  `KeyboardShortcutFloatingOverlayController.swift:8`), centered like the
  Cmd-Shift-V popup, with a `MAYNTextField`-style search field focused on open.
- List: **pinned on top, then recent-first by `last_visited`**. Each row =
  Finder folder icon (`NSWorkspace.icon(forFile:)`) + display name + dimmed path
  (middle-truncated) + relative time (e.g. "2m ago").
- Keyboard: type to filter (substring over name + path); arrow keys to move
  selection; `Return` → `NSWorkspace.shared.open(url)`; `Opt-Return` →
  `activateFileViewerSelecting([url])`; `Esc` dismisses.
- Inline actions per row: a pin toggle and a remove (delete) control, styled with
  `MAYN*` controls. Removal deletes the row; pinning sets `pinned = 1`.
- Stale rows (`exists_flag == 0`, refreshed on open) render dimmed with a small
  "missing" affordance and an option to remove (§9).
- The global shortcut is registered through the descriptor's `HotkeyDescriptor`
  and editable in the tool's Settings via `HotkeyRecorder` (never inline on the
  page).

### 8.2 Menu-bar dropdown / Command Center tab

- A new section/tab supplied via `FeatureDescriptor.menuBarItemFactory`
  (`FeatureDescriptor.swift:54`), listing the same recent/pinned data.
- Each row supports inline pin/remove and click-to-open; modifier-click reveals.
- Mirrors the existing Command Center tab conventions (tab-specific footer; no
  Pause footer — Pause is Clipboard-only per `CLAUDE.md`). A Pause control for
  this feature lives on the config page, not the popover footer.

### 8.3 FinderSync toolbar button

- One toolbar item labeled "Recent Folders" inside Finder windows. Clicking
  builds a menu of recent + pinned folders from the shared store; selecting one
  opens it. Optional inline "Pin" on menu items writes back through the shared
  store.

### 8.4 Main-window page — configuration & guidance only

Built with `FunctionPageShell`. Contents:

- **Header**: title + a `ShortcutChip` showing the switcher hotkey (read-only).
- **Status**: permission status (Accessibility via `PermissionCard`); FinderSync
  extension enabled state; feature on/off; **Pause** toggle.
- **Settings sections** (`MAYNSettingsPage` / `MAYNSection` / `MAYNSettingsRow`):
  - Retention: max items and/or max age (`MAYNNumericStepper` / `MAYNDropdown`),
    feeding `RetentionPolicy`.
  - Exclusions: a path-based exclusion editor following the
    `SettingsExclusionEditor` pattern (`SettingsExclusionEditor.swift:6-241`) —
    choose folders to never record (with sensible defaults: home Library, system
    volumes, etc.).
  - Apple-Events fallback toggle (§7.2), clearly labeled as triggering a
    one-time macOS permission prompt.
  - "Clear history" destructive action.
  - How-to / what-this-does explanatory copy (`InstructionStrip`).
- It **never** lists captured folders. Browsing/management happens in the
  switcher and dropdown (roadmap §6).

### 8.5 Consent / onboarding

- Feature is **off by default**; the descriptor's dashboard card shows it as
  available-but-off.
- Enabling runs a short per-feature onboarding step (descriptor
  `onboardingSetupFactory`, `FeatureDescriptor.swift:53`) with an **explicit
  consent screen**: plain-language statement that MAYN will record the folders
  you open in Finder, that this stays on-device in the App Group, that you can
  pause or clear it anytime, and that nothing is sent to the cloud. The user must
  affirmatively continue. Accessibility status is shown here; the Apple-Events
  fallback is presented as optional and off.

---

## 9. Edge cases & error handling

- **Empty `kAXDocumentAttribute`**: some windows (special/smart folders, search
  results) return no document URL. With the Apple-Events fallback off, skip
  silently. With it on, send the lazy Apple Event; if that also fails or is
  denied, skip and do not re-prompt.
- **Skip rules**: never record Desktop (it is the implicit Finder root, not a
  navigation), Trash, transient Finder **search** windows (title/URL signals a
  search scope), and any path on the exclusion list. Volumes being mounted/
  unmounted should not generate phantom visits.
- **Stale / deleted paths**: `exists_flag` is refreshed lazily — when a surface
  is about to display rows and on open of a row. On open, if the URL no longer
  resolves, mark `exists_flag = 0`, show the dimmed/missing state, and offer
  remove. Never crash or silently open the wrong location. (`NSWorkspace.open`
  on a dead path just fails; we pre-check existence.)
- **AX flakiness**: Finder rebuilds its AX tree, dropping observers. S1's
  health-check timer re-subscribes; the recorder also re-attaches on the next
  `didActivateApplicationNotification` for Finder. A transient failure to read
  an attribute is logged and skipped, not retried in a tight loop.
- **Noise / dedup**: rapid focus churn (clicking around one window, sidebar
  selection) collapses via the ~5 s same-path window into `visitCount` /
  `lastVisited` updates. Different paths within the window are each recorded. This
  prevents the history from filling with one folder visited ten times in a
  minute.
- **Permission revoked mid-session**: detected by the trust monitor; the feature
  transitions to "needs Accessibility", detaches the observer, and surfaces the
  card. Re-grant re-attaches.
- **Pause / disable**: detaches the observer and stops all writes immediately; no
  buffering of paused-period visits.
- **Concurrent access (main app writer + appex reader)**: WAL +
  `busy_timeout = 5000` (`Database.swift:13-14`) handles reader/writer overlap;
  the appex opens read-only.
- **Multiple Finder windows / Spaces**: we record the **focused** window's folder
  only, so switching focus between two windows records two distinct visits
  (subject to dedup), which is the intended behavior.

---

## 10. Testing strategy

- **`FolderHistoryStore` unit tests** (Shared `CoreTests`, alongside
  `RetentionPolicyTests`): upsert increments `visitCount` and bumps
  `lastVisited`; uniqueness on `path`; pin/unpin; `exists_flag` refresh; ordering
  (pinned-first, then `last_visited DESC`); migration idempotency. Use the
  App-Group container override (`AppGroup.containerURLOverride`) for a temp DB,
  the established test pattern.
- **Retention tests**: max-items and max-age eviction with pinned rows exempt,
  mirroring `RetentionPolicyTests`.
- **Recorder logic tests** (pure, injected): given a sequence of
  (path, timestamp) signals, assert the dedup/debounce coalescing, skip rules
  (Desktop/Trash/search/exclusions), and that empty-path signals are dropped (or
  routed to fallback) per config. AX reads and Apple Events are behind injected
  seams so the state machine is testable without a live Finder — the same
  injectable-pipeline approach the voice tests use.
- **Path-resolution tests**: `file://` URL string → POSIX path normalization,
  trailing-slash handling, symlink/`/private/var` canonicalization for stable
  dedup keys.
- **Surface tests**: switcher filtering (substring over name + path), open vs
  reveal action routing (assert `open` vs `activateFileViewerSelecting` is
  chosen by modifier), stale-row rendering.
- **Manual / integration**: enable feature, navigate Finder through several real
  folders incl. a special folder (fallback on/off), confirm switcher/dropdown/
  FinderSync all reflect the history; delete a folder on disk and confirm the
  stale path is handled; revoke Accessibility and confirm graceful degradation;
  Reduce-Motion pass on the switcher.

---

## 11. Risks & mitigations

| Risk | Mitigation |
|---|---|
| **Privacy perception** — silently logging folder visits feels invasive. | Off by default; explicit consent screen; pause toggle; exclusions; clear-history; on-device only (App Group), no cloud. |
| **Path stored as plaintext column** (needed for uniqueness/queries). | Same tradeoff as `DownloadStore.state`; mitigated by feature gate + consent + container location. `displayName` stays encrypted. Documented, not hidden. |
| **AX observer drop when Finder rebuilds its tree.** | S1 health-check re-subscribe + re-attach on Finder activation; the explicit reason S1 exists. |
| **Apple Events prompt annoyance / denial.** | Fallback is opt-in and lazy; covers only empty-`kAXDocumentAttribute` special folders; denial degrades silently and never re-prompts. |
| **FinderSync extension limitations / sandbox.** | Used purely as a reader/launcher, not for capture or directory monitoring; opens the store read-only via App Group; capture stays in the non-sandboxed main app. |
| **History noise from focus churn.** | ~5 s same-path dedup window + skip rules (Desktop/Trash/search). |
| **CPU/battery from observation.** | Event-driven (no steady-state polling); only S1's low-frequency health-check timer runs. |
| **New `.appex` build/signing complexity.** | Mirror the proven FolderPreview `app-extension` block in `project.yml`; regenerate with `xcodegen generate`; entitlements limited to sandbox + App Group. |
| **Trust revocation mid-session.** | Reuse `WindowControlAccessibilityTrustMonitor` shape; transition to needs-Accessibility, detach observer. |

---

## 12. Open questions

1. **Dedup canonicalization**: should `/private/var/...` vs `/var/...` and
   symlinked paths be canonicalized to a single key, or stored as observed?
   (Leaning: canonicalize via `URL.standardizedFileURL` / resolved symlinks for a
   stable unique key.)
2. **Default retention values**: what `maxItems` / `maxAge` ship by default for
   folder history (e.g. 200 items / 90 days)? Pinned always exempt.
3. **Default exclusions**: exact starting exclusion set (home `~/Library`, system
   volumes, `node_modules`-style noise?) — needs a sensible, conservative
   default list.
4. **FinderSync pin/remove**: do we expose pin/remove inside the FinderSync menu,
   or keep that surface read+open only and reserve management for the switcher/
   dropdown? (Roadmap says management is inline in switcher/dropdown; FinderSync
   may stay launch-only for simplicity.)
5. **Search-window detection**: most reliable signal to classify a Finder window
   as a transient *search* window to skip — title heuristics vs absence of
   `kAXDocumentAttribute` vs a specific URL scheme?
6. **Display name source**: derive from the last path component, or prefer the AX
   window title (which can be localized / decorated)? Path component is more
   stable for matching; title is friendlier.
7. **Menu-bar surface placement**: a dedicated Command Center tab vs a section
   under an existing tab — depends on Command Center tab budget.
