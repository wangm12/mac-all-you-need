# Modular Features — Design Spec

- **Date:** 2026-05-15
- **Status:** Draft, awaiting user review
- **Owner:** mingjie-father
- **Related plans:** Plan 6 (UI Shell — built on), Plan 7 (Distribution — depends on)

## 1. Goal

Convert Mac All You Need from a monolithic app that bundles every feature into a small wrapper whose features are downloaded, enabled, and disabled on demand. New users start with an empty wrapper, choose what they want during onboarding, and can change their mind later from Settings. The system is built as a registry so future features slot in by adding a single descriptor — no core refactoring per feature.

### Non-goals

- Dynamic loading of Swift code at runtime (loadable frameworks). Swift code stays in the wrapper; only heavy assets are modular. Rationale: too much complexity for a few MB of binary savings.
- Sync engine work. Plan 2 remains deferred indefinitely; the Sync settings tab is removed by this design.
- App Store distribution. Distribution remains direct DMG / Sparkle (per Plan 7).

## 2. Decisions captured up front

| # | Decision | Rationale |
|---|---|---|
| D1 | **Smaller install + on-demand downloads.** Wrapper ships small; heavy assets fetched at install. | Improves first-launch experience; matches user intent. |
| D2 | **Four top-level features only.** Clipboard, Folder Preview, Video Downloader, Voice Dictation. Sub-features (snippets, browser cookies, voice personalization) bundle with their parent. | Avoids toggle overload; sub-features rarely toggled independently. |
| D3 | **Asset packs hosted on MAYN's GitHub Releases.** No separate CDN. | GH Releases is already a Fastly-backed CDN; no infra to operate; same release as the wrapper DMG. |
| D4 | **Two-stage off semantics: Disable (assets stay) vs Uninstall (assets removed).** | Fast re-enable without re-download is the common case; explicit Uninstall for users who want disk back. |
| D5 | **Onboarding picks features first, then runs per-feature setup** (download → permissions → feature-specific config). | Skips irrelevant prompts; mirrors the existing Voice setup flow. |
| D6 | **Pack versions pinned to wrapper release.** Newer packs arrive only via a wrapper update (Sparkle). | Predictable QA; one source of truth per release. |
| D7 | **Hybrid architecture.** Swift always bundled, heavy assets on-demand. | Best return-on-complexity; loadable frameworks rejected. |
| D8 | **Registry / plugin shape.** Each feature is a `FeatureDescriptor`; adding a future feature = appending one descriptor + one activator. | Future features must integrate without core changes. |

## 3. Feature model & registry

A `Feature` is defined by a single value:

```swift
struct FeatureDescriptor {
    let id: FeatureID                 // .clipboard, .folderPreview, .downloader, .voice
    let displayName: String
    let icon: String                  // SF Symbol
    let summary: String               // one-line, shown on cards
    let detailDescription: String     // longer, shown in onboarding "Learn more"
    let assetPack: AssetPack?         // nil = Swift-only, no download needed
    let requiredPermissions: [Permission]
    let activator: any FeatureActivator
}

protocol FeatureActivator {
    func activate() throws            // start workers, register hotkeys, show UI surfaces
    func deactivate() throws          // reverse of activate; do NOT touch user data or OS perms
}

enum FeatureState: Equatable {
    case notInstalled
    case downloading(progress: Double)
    case installFailed(reason: String)
    case installedDisabled
    case installedEnabled
    case uninstalling
}
```

`FeatureRegistry` is an ordered array of descriptors held by the wrapper. `FeatureManager` is a single Swift actor that owns persisted `FeatureState` per feature, drives transitions, and orchestrates activator calls. State is persisted to `AppGroupSettings` so the daemon and main app agree on what's active.

The wrapper baseline (always-on, never disableable) contains: launcher shell, menu bar host, Settings window, onboarding, hotkey registry framework, `FeatureManager`. **No feature UI surfaces** live in the baseline — every product surface (clipboard popup, browse window menu items, voice HUD, dock controller, etc.) is registered/unregistered by a feature's activator.

### Adding a future feature

1. Append a case to `FeatureID`.
2. Add a `FeatureDescriptor` to the registry.
3. Implement one `FeatureActivator`.
4. (Optional) Provide an asset pack zip and add it to the wrapper's manifest.

No edits to `FeatureManager`, onboarding flow, or settings tabs are required.

## 4. Feature pack format & distribution

### Pack contents

Each downloadable pack is one zip published as a release asset:

```
Downloader-1.0.0.zip
├── manifest.json          # version, sha256 of each binary, schema version
├── yt-dlp                 # universal binary, signed with MAYN Developer ID
└── ffmpeg                 # universal binary, signed with MAYN Developer ID
```

Today only Downloader has a pack (`assetPack != nil`). Clipboard, Folder Preview, and Voice are Swift-only (`assetPack: nil`); for them, "install" is a state flip, not a download.

### Wrapper-side manifest

The wrapper bundles `Resources/FeaturePackManifest.json`, pinned to its release version:

```json
{
  "schemaVersion": 1,
  "wrapperVersion": "2.0.0",
  "packs": {
    "downloader": {
      "version": "1.0.0",
      "url": "https://github.com/<owner>/mac-all-you-need/releases/download/v2.0.0/Downloader-1.0.0.zip",
      "sha256": "abc123…",
      "sizeBytes": 201326592
    }
  }
}
```

A new wrapper release ships a new manifest with new pack URLs/SHAs; the user receives pack updates implicitly when Sparkle delivers the wrapper update (D6).

### Download & verify pipeline

1. User taps "Install" on a feature card → `URLSession.downloadTask` writes to a `.partial` staging path inside the App Group container, with progress reported to the UI.
2. Verify SHA-256 against manifest. Mismatch → delete partial + show error.
3. Unzip into `~/Library/Application Support/MacAllYouNeed/Features/<id>/<version>/`.
4. `chmod +x` the executables and strip the `com.apple.quarantine` xattr from each binary (downloads are quarantined by macOS; required for them to execute under our hardened runtime).
5. `codesign --verify` each binary against MAYN's Developer ID.
6. Atomic rename of the version directory into the live path; `FeatureManager` transitions to `installedEnabled`; activator runs.

### Hosting

GitHub Releases. No separate CDN. Public release assets have no bandwidth quota, are served via Fastly globally, and the URL is the same release that publishes the wrapper DMG.

### Code signing

Binaries inside packs are signed with MAYN's Developer ID at release time (CI step in Plan 7). Combined with the existing `disable-library-validation` entitlement, hardened-runtime can exec them. The pack zip itself is just a container — what matters is the signature on each binary.

### Resumability & failure

- Failed downloads leave only the `.partial` staging file; the live path is untouched.
- `URLSession` resume data is persisted across app launches.
- All download/verify failures surface in the install UI with a Retry button. No silent failure.

### Side-load escape hatch

Settings → Advanced exposes "Install pack from file…" so users behind corporate proxies (Risk 3) can fetch the zip manually and install it. Same SHA + signature verification applies.

## 5. Lifecycle: install / enable / disable / uninstall

### States

| State | Meaning | Disk usage | Active in app? | Permissions held? |
|---|---|---|---|---|
| `notInstalled` | No pack on disk (or feature has no pack and was never enabled) | 0 | no | no |
| `downloading(progress)` | Pack actively being fetched | partial | no | no |
| `installFailed(reason)` | Last install attempt failed | 0 | no | no |
| `installedDisabled` | Pack on disk, code present, but inert | full | no | no UI, no hotkeys, no permission prompts |
| `installedEnabled` | Live and running | full | yes | requested as needed |
| `uninstalling` | Cleanup in progress | shrinking | no | no |

### Legal transitions

```
notInstalled       --install-->     downloading       --success-->  installedEnabled
                                                      --failure-->  installFailed
installFailed      --retry-->       downloading
installedEnabled   --disable-->     installedDisabled
installedDisabled  --enable-->      installedEnabled
installedDisabled  --uninstall-->   uninstalling      --done-->     notInstalled
installedEnabled   --uninstall-->   uninstalling      --done-->     notInstalled
                                    (auto-disable runs first)
```

`FeatureManager` rejects (or no-ops) any transition not on this list.

### `activate()` responsibilities (entering `installedEnabled`)

- Register global hotkeys this feature owns
- Add menu bar item / dock controller
- Start background workers (clipboard poller, dispatch server, voice hotkey listener, etc.)
- Mark its UI surfaces (settings tabs, browse window menu items, etc.) as visible
- Verify required permissions; trigger first-time prompts if needed
- Probe required binaries on disk; if missing, throw → state becomes `installFailed` (Risk 5)

### `deactivate()` responsibilities (leaving `installedEnabled`)

- Unregister hotkeys
- Remove menu bar items / dock controllers
- Stop background workers
- Hide the feature's UI surfaces
- Does **not** revoke OS permissions (we can't programmatically revoke; we just stop using them)
- Does **not** delete user data (clipboard history, downloaded videos, snippets) — that's the user's data

### Uninstall

Deletes `~/Library/Application Support/MacAllYouNeed/Features/<id>/<version>/` and any sibling versioned directories. The Uninstall confirmation sheet:

- Shows pack size that will be reclaimed.
- Lists the user-data path that will be **kept by default**.
- Offers an opt-in checkbox: "Also delete my <clipboard history / downloaded files / snippets>". Default unchecked.

### Failure handling

- If `activate()` throws after a successful install (e.g., hotkey conflict), state stays at `installedDisabled` with a flagged error visible in Settings. The bytes are valid; install is not reverted.
- If `deactivate()` throws, log and force-progress the state machine; never leave the user in a transitional state.

## 6. Onboarding redesign

The current 6-step wizard (Welcome / Accessibility / FDA / Notifications / Sync / Done) is replaced by a feature-driven flow. `OnboardingState` and `OnboardingWindowController` are reused; the steps inside change.

### New flow

```
1. Welcome
2. Feature Picker             ← new, replaces fixed permission steps
3. Per-feature setup          ← repeats once per chosen feature, in registry order
   3a. Download progress      (skipped if assetPack == nil)
   3b. Permission grants      (only the ones this feature actually declares)
   3c. Feature-specific config (e.g., Voice's API key + ASR provider — reuses VoiceSettingsView)
4. Done                       ← summary + "you can change this any time in Settings → Features"
```

### Feature picker step

Grid of cards, one per registry entry. Each card shows: icon, name, one-line summary, "Learn more" disclosure (revealing `detailDescription`, declared permissions, download size), and a checkbox. **All cards default to unchecked** to honor the "wrapper has no functions" framing.

A "Skip for now" button is allowed and exits onboarding with zero features enabled — a legitimate end state. The user can always return via Settings → Features.

Cards render directly from `FeatureRegistry`, so a new feature appears here automatically once its descriptor lands.

### Per-feature setup step

For each selected feature in registry order:

- If `assetPack != nil`: download-progress screen with size, progress bar, retry on failure. Stays on this screen until install completes.
- Permission prompts the feature declares. Mirrors the existing TCC auto-advance pattern.
- Feature-specific config screens if the feature provides any. Today only Voice has these; we slot in `VoiceSettingsView` verbatim.

### Done step

Lists what was installed/enabled and what was skipped. Closes with: "You can install or remove features any time from Settings → Features."

### Existing-user upgrade

Onboarding does not re-run (gated by `OnboardingState`). A separate one-time "What's new" sheet surfaces on first launch after upgrade — see § 7.

### Re-running onboarding

Settings → Advanced gains a "Re-run onboarding…" action that resets `OnboardingState`. Useful for support and for users who want to start fresh.

## 7. Migration for existing users

Triggered by a `migratedToFeatureModel: Bool` sentinel in `AppGroupSettings`, runs once on first launch after upgrade.

### Steps

1. **Detect prior usage** for each feature, in this order of confidence:
   - **Direct evidence** (state in shared DB exists): clipboard records present → Clipboard was used; download records present → Downloader was used; voice settings configured → Voice was used; folder preview extension recently invoked → FolderPreview was used.
   - **Indirect evidence**: the feature's settings tab has any non-default value.
   - **No evidence**: assume passively installed but not actively used.
2. **Mark each feature's state.**
   - **Downloader**: if `Vendored/binaries/yt-dlp` or the bundle's `Resources/yt-dlp` is present and valid, copy into `Features/downloader/<currentManifestVersion>/` (the version the wrapper's bundled `FeaturePackManifest.json` declares) and mark `installedEnabled` — **no re-download needed**. If the on-disk binary's SHA does not match the manifest, treat as a missed update and prompt to download instead of trusting the older copy.
   - **Swift-only features with usage evidence**: mark `installedEnabled`.
   - **Features with no usage evidence**: mark `installedDisabled` (conservative — inert but reversible without a download). User can disable cleanly later if they want.
3. **Show a one-time "What's new" sheet** on first launch (separate from onboarding): "Mac All You Need now lets you choose which features to use. We've kept everything you were using; you can disable anything you don't want from Settings → Features." Single button: *Open Features Settings*.
4. **Persist the sentinel** so migration never runs again.

### Edge cases

- **Corrupted detection state** (DB unreadable): assume all four features are `installedEnabled` to avoid silently breaking workflows. The user can disable from Settings.
- **Downgrade then re-upgrade**: sentinel persists; migration runs at most once per user.
- **Fresh install on a Mac that previously had MAYN** (Application Support wiped): no DB → treated as new user → onboarding runs.

## 8. Settings redesign

### Tab structure

```
General │ Features │ Hotkeys │ Advanced │ <feature tabs…>
```

- **General**, **Features**, **Hotkeys**, **Advanced** are always visible (wrapper-level).
- A per-feature tab (Clipboard / Downloads / Folder Preview / Voice) appears only when the feature is at least `installedDisabled`.
- Per-feature tabs render in `FeatureRegistry` order.
- The current **Sync** tab is removed entirely (Plan 2 deferred indefinitely).

### Features tab — the catalog/manager

Same card grid as the onboarding picker, but cards show live state and have actions:

| State | Primary control on card | Secondary actions in `⌄` menu |
|---|---|---|
| `notInstalled` | `[ Install ]` button | — |
| `downloading` | progress bar + `[ Cancel ]` | — |
| `installFailed` | `[ Retry ]` + error reason | "View log" |
| `installedDisabled` | `[ Enable ]` button | "Uninstall…" |
| `installedEnabled` | `[● Enabled]` toggle (flipping = Disable) | "Uninstall…", "Open settings" |
| `uninstalling` | progress spinner | — |

### Uninstall confirmation sheet

Lists the pack size that will be reclaimed and an opt-in checkbox for user-data deletion ("Also delete clipboard history" / "Also delete downloaded videos" / etc.). User data is preserved unless the user explicitly opts in.

### Per-feature settings tabs

Existing `ClipboardSettingsView`, `DownloadsSettingsView`, etc. are reused unchanged. Conditionally rendered based on `FeatureManager.state(for:)`. If a feature is `installedDisabled`, its tab still appears with a banner: *"This feature is disabled. Settings here will apply when you re-enable it."*

### Hotkeys tab

Already a global cross-feature view. Now filters to show only hotkeys from features at least `installedDisabled`. Hotkeys belonging to a disabled feature are visible but greyed with a "Disabled" badge.

### Advanced tab

Gains:
- "Re-run onboarding…"
- "Open feature install directory in Finder"
- "Install pack from file…" (side-load escape hatch — § 4)
- "Reset all features to not-installed" (destructive action with confirmation)

## 9. Concurrency, persistence, and process boundaries

- All `FeatureManager` writes happen in the **main app**; the daemon is read-only on feature state. Reads cross the App Group `UserDefaults` boundary.
- `FeatureManager` is a Swift actor; no two transitions for the same feature can interleave.
- Concurrent install requests for the same feature: second call is a no-op while the first is in flight.
- Concurrent install requests for different features: allowed; each runs independently.
- The daemon observes `AppGroupSettings` changes via `KVO` / `NotificationCenter` and starts/stops its own per-feature work accordingly.

## 10. On-disk layout

```
~/Library/Application Support/MacAllYouNeed/
├── Features/
│   ├── downloader/
│   │   └── 1.0.0/
│   │       ├── manifest.json
│   │       ├── yt-dlp
│   │       └── ffmpeg
│   └── <future-feature>/<version>/…
├── Staging/
│   └── downloader.partial            # in-flight downloads
└── Logs/
    └── feature-install.log           # rotating, surfaced via "View log"
```

User data (clipboard DB, downloaded videos, snippets) lives in its existing locations and is **never** under `Features/`. Uninstall touches only `Features/<id>/`.

## 11. Testing strategy

### Unit tests (no network, no disk)

- `FeatureManager` state machine: every legal transition + every illegal one. Pure state, fully deterministic.
- `FeatureRegistry` ordering, lookup by id, presence of required descriptor fields.
- `FeaturePackManifest` JSON decoding: malformed manifests, schema-version mismatches, missing fields.
- Migration logic (§ 7): given a synthetic `AppGroupSettings` + DB state, assert each feature lands in the expected state. Table-driven.

### Component tests (real disk, no network)

- Install pipeline against a local fixture zip (`file://` URL): SHA verification (pass + fail), unzip, chmod, quarantine xattr removal, atomic move, cleanup of partial download on failure.
- Uninstall: pack directory gone, user data untouched.
- Concurrent operations: serialized per feature.

### Integration tests (real network, gated)

- Custom test trait so CI can opt in. Downloads a real pack from a test GitHub Release into a temp directory, verifies SHA, executes the binary's `--version`.
- Run nightly + on PRs that touch `FeatureManager` or `scripts/fetch-binaries.sh`. Not on every PR.

### UI tests

- Onboarding: picker step renders one card per registry entry; "Skip" leaves all features `notInstalled`; selecting Downloader triggers the download progress screen.
- Settings → Features: snapshot tests of each card state, plus interaction tests for Enable/Disable/Uninstall buttons.
- Done with SwiftUI's preview-driven snapshot testing (already used in the project).

### Manual QA matrix (per release)

- Fresh install on macOS 14, 15, 26.
- Upgrade install with prior usage of: Clipboard only / Downloader only / All four / None.
- Install Downloader → kill app mid-download → relaunch (resumability).
- Install Downloader → toggle airplane mode → retry (error handling).
- Install Downloader → corrupt the SHA in manifest → install (verification failure path).
- Disable Voice → confirm microphone use stops + System Settings still shows the permission (we don't revoke).
- Uninstall Downloader → pack gone, user's downloaded video files preserved.

## 12. Risks & mitigations

| # | Risk | Likelihood | Mitigation |
|---|---|---|---|
| 1 | **Gatekeeper / hardened runtime blocks downloaded binaries.** | High | Strip `com.apple.quarantine` xattr after verifying our own SHA + codesign signature (§ 4). Same pattern Sparkle uses. Test on fresh user account on each macOS version. |
| 2 | **Wrapper update + pack update get out of sync** (release published partially). | Medium | CI publishes the manifest *last*, after all pack zips are uploaded and verified. If manifest is missing, wrapper falls back to "no newer pack available". |
| 3 | **User behind corporate proxy / firewall** that blocks `objects.githubusercontent.com`. | Medium | Install error sheet shows the exact URL + a "Copy URL" button. Side-load via Advanced → "Install pack from file…" available from day one. |
| 4 | **Disk full mid-install.** | Low | Staging dir + atomic move (§ 4). Cleanup of staging dir runs at app launch. |
| 5 | **User manually deletes pack directory in Finder** while feature is enabled. | Low | Activator probes for required binaries on activate; missing → `installFailed` with "Reinstall" affordance + banner in feature's settings tab. |
| 6 | **Permission-revocation drift.** User disables, manually revokes permission, re-enables — feature can't run. | Medium | Each `activate()` re-verifies declared permissions and prompts if missing. Already the pattern Voice uses. |
| 7 | **AppGroupSettings race between main app and daemon** for `FeatureManager` state. | Medium | All writes go through main app; daemon is read-only on feature state. Serialize writes with a single Swift actor in the main app (§ 9). |
| 8 | **Future feature outgrows `FeatureDescriptor`** (multiple sub-packs, model file >2 GB, etc.). | High over time | `FeaturePackManifest.schemaVersion` lets us evolve the format. Current `assetPack: AssetPack?` reserves room to migrate to `assetPacks: [AssetPack]` if needed. |
| 9 | **Telemetry blind-spot.** Failed installs are only visible to the affected user. | Low (acceptable) | Surface a clear, copyable error in the install UI so user-reported issues are actionable. No telemetry until user explicitly opts in (matches app's privacy posture). |
| 10 | **Existing user surprised** that a feature "moved" because it's now in the Features tab. | Low | Migration's "What's new" sheet (§ 7) explicitly says nothing was disabled; Hotkeys tab still shows everything they had bound. |

## 13. What this design explicitly does not change

- Code signing of the wrapper itself, notarization of the DMG — Plan 7 territory, unchanged.
- Sync engine — Plan 2 deferred indefinitely; the Sync settings tab is removed.
- Apple Silicon / Intel split — feature packs ship universal binaries via `lipo`, same as today.
- Existing per-feature settings views — reused as-is, only their visibility is now conditional.
- The XPC daemon's responsibilities — only its observation of feature state changes is new (§ 9).

## 14. Open questions for implementation planning

These are intentionally deferred until the implementation plan is written, but flagged here so they aren't forgotten:

1. Exact persisted serialization of `FeatureState` (raw value strings vs. JSON-coded enum).
2. Where to surface install-progress notifications when the user closes the Settings window mid-download (menu bar dot? notification? both?).
3. Per-feature `activate()` ordering on app launch when multiple features are `installedEnabled` (parallel vs. sequential).
4. Whether the daemon needs a "shutdown all per-feature workers" bulk path for app quit, or whether `deactivate()` per feature is enough.
5. Sparkle integration: does the wrapper updater know to pre-warm pack downloads so the user isn't waiting twice?
