# Modular Features — Design Spec

- **Date:** 2026-05-15
- **Status:** Draft, awaiting user review
- **Owner:** mingjie-father
- **Related plans:** Plan 6 (UI Shell — built on), Plan 7 (Distribution — depends on)

## 1. Goal

Convert Mac All You Need from a monolithic app that bundles every feature and starts everything at launch into one with **modular activation** (each feature can be independently enabled/disabled at runtime) and **on-demand heavy assets** (large binaries and model files download only when the user wants them). New users start with no features active, choose what they want during onboarding, and can change their mind later from Settings.

The system is built as a registry whose `FeatureDescriptor` carries view factories, hotkey declarations, menu-bar contributions, and lifecycle hooks. Adding a future feature = adding one descriptor + one activator + (optionally) one asset pack. Core code (`SettingsRoot`, `MenuBarHost`, hotkey registry, onboarding wizard) becomes a loop over the registry — no per-feature switch statements.

> Honesty about scope: Swift code for all four current features stays in the wrapper bundle (~10 MB total — see § 2 D7). What's "downloaded on demand" today is the Downloader's binaries (~192 MB) and the Voice feature's optional Qwen3 ASR model files (~900 MB – 1.75 GB depending on variant). Future features may declare additional packs.

### Non-goals

- Dynamic loading of Swift code at runtime (loadable frameworks). Swift code stays in the wrapper; only heavy assets are modular. Rationale: too much complexity for a few MB of binary savings.
- Sync engine work. Plan 2 remains deferred indefinitely; the Sync settings tab is removed by this design.
- App Store distribution. Distribution remains direct DMG / Sparkle (per Plan 7).

## 2. Decisions captured up front

| # | Decision | Rationale |
|---|---|---|
| D1 | **Modular activation + on-demand heavy assets.** Every feature can be enabled/disabled at runtime; heavy binaries and model files download only when the user opts into them. Swift code stays in the wrapper. | Honest framing — Swift code modularity isn't worth the dynamic-loading complexity. The user-visible win is "the heavy stuff is opt-in." |
| D2 | **Four top-level features only.** Clipboard, Folder Preview, Video Downloader, Voice Dictation. Sub-features (snippets, browser cookies, voice personalization) bundle with their parent. | Avoids toggle overload; sub-features rarely toggled independently. |
| D3 | **Asset packs hosted on MAYN's GitHub Releases.** No separate CDN. | GH Releases is already a Fastly-backed CDN; no infra to operate; same release as the wrapper DMG. |
| D4 | **Two-stage off semantics: Disable (assets stay) vs Uninstall (assets removed).** | Fast re-enable without re-download is the common case; explicit Uninstall for users who want disk back. |
| D5 | **Onboarding picks features first, then runs per-feature setup** (download → permissions → feature-specific config). | Skips irrelevant prompts; mirrors the existing Voice setup flow. |
| D6 | **Pack versions pinned to wrapper release.** Newer packs arrive only via a wrapper update (Sparkle). | Predictable QA; one source of truth per release. |
| D7 | **Hybrid architecture.** Swift always bundled, heavy assets on-demand. | Best return-on-complexity; loadable frameworks rejected. |
| D8 | **Registry / plugin shape with first-class extension points.** `FeatureDescriptor` carries view factories, hotkey lists, menu items, and OS-extension policy. Core code (settings, menu bar, hotkey registry, onboarding) is a loop over the registry. | Future features must integrate without core changes — the descriptor must carry enough to make that real. |
| D9 | **Sparkle pre-install script for upgraders.** Existing-user upgrade copies binaries out of the old bundle into `Features/` before Sparkle replaces the app, so no re-download. | Best UX for existing users; falls back gracefully to "needs download" if script can't run. |

## 3. Feature model & registry

### `FeatureDescriptor`

```swift
struct FeatureDescriptor {
    let id: FeatureID                       // .clipboard, .folderPreview, .downloader, .voice
    let displayName: String
    let icon: String                        // SF Symbol
    let summary: String                     // one-line, shown on cards
    let detailDescription: String           // longer, shown in onboarding "Learn more"
    let requiredPermissions: [Permission]
    let activator: any FeatureActivator

    // Asset model (see § 4): a feature has zero or more packs (most have zero or one).
    // Provider-managed caches (e.g., Voice's Qwen3 model files) are declared via assetCaches
    // so the lifecycle knows about them for uninstall and disk-usage reporting.
    let assetPacks: [AssetPack]             // [] = no monolithic pack required
    let assetCaches: [AssetCacheDescriptor] // provider-managed caches under our knowledge

    // Extension points — these are what make the registry actually pluggable.
    // SettingsRoot, MenuBarHost, HotkeyRegistry, and onboarding all loop over the registry
    // instead of hardcoding per-feature branches.
    let settingsTabFactory: (() -> AnyView)?         // settings tab body; visible when activationState != hidden
    let onboardingSetupFactory: (() -> AnyView)?    // wizard step content during per-feature setup
    let menuBarItemFactory: (() -> AnyView)?         // optional menu bar contribution; only rendered when enabled
    let hotkeys: [HotkeyDescriptor]                  // declared hotkeys; registered/unregistered by activation
    let osExtensionPolicy: OSExtensionPolicy        // how to handle non-disableable OS extensions (see § 3.3)
}

protocol FeatureActivator {
    func activate() throws    // start workers, register hotkeys, show UI surfaces
    func deactivate() throws  // reverse of activate; do NOT touch user data or OS perms
}
```

### Runtime state — split into two orthogonal axes

```swift
enum AssetState: Equatable {
    case notRequired                              // feature has no pack — Clipboard today
    case notDownloaded                            // pack required but absent
    case downloading(progress: Double)
    case downloadFailed(reason: String)
    case present(version: String)                 // verified, on disk, ready
}

enum ActivationState: Equatable {
    case disabled                                 // user opted out OR no asset
    case enabled                                  // activator has run; feature is live
}

struct FeatureRuntimeState: Equatable {
    let assetState: AssetState
    let activationState: ActivationState
}
```

The two axes are independent:
- A feature with `assetState == .notRequired` (Clipboard) can flip enabled↔disabled freely.
- A feature with `assetState == .notDownloaded` cannot become `.enabled`; user must install first.
- A feature with `assetState == .present` and `activationState == .disabled` (Downloader after user disables it) keeps its bytes on disk; re-enable is instant.
- Uninstall flips `assetState` back to `.notDownloaded` (and runs `deactivate()` first if needed). User-visible labels in UI map these compounds to simple verbs (Install / Enable / Disable / Uninstall) — see § 8 control mapping.

### `FeatureManager` and the registry

`FeatureRegistry` is an ordered array of descriptors held by the wrapper. `FeatureManager` is a single Swift actor (in the main app) that owns persisted `FeatureRuntimeState` per feature, validates transitions, and orchestrates activator calls. State is persisted to `AppGroupSettings`. **Every write fires a Darwin notification** (`com.macallyouneed.featureStateDidChange`) so the daemon can re-read; see § 9.

The wrapper baseline (always-on, never disableable) contains: launcher shell, menu bar host shell, Settings window shell, onboarding wizard shell, hotkey registry, `FeatureManager`. The shells are *empty containers* that populate themselves by iterating the registry. Feature product surfaces (clipboard popup, browse window menu items, voice HUD, dock controller, etc.) are mounted/unmounted by activators.

### 3.3 OS-extension policy (Folder Preview special case)

Some macOS subsystems can't be runtime-disabled because they're discovered by the OS via static `Info.plist` declarations in the bundle (Quick Look extensions, Login Items, File Provider extensions, etc.). For these:

```swift
enum OSExtensionPolicy {
    case none                                  // pure in-process feature
    case staticBundleExtension(StaticExtensionConfig)
}

struct StaticExtensionConfig {
    let extensionBundleID: String
    let runsRegardlessOfFeatureState: Bool     // true for QL — OS will launch it anyway
    let respectsFeatureFlag: Bool              // true means extension reads AppGroupSettings
                                               // and short-circuits to a "disabled" preview
}
```

**Folder Preview today** uses `staticBundleExtension(extensionBundleID: "FolderPreview", runsRegardlessOfFeatureState: true, respectsFeatureFlag: true)`. The Quick Look extension still launches when macOS triggers it, but on every preview request it reads the feature's `activationState` from `AppGroupSettings`:

- `.enabled` → render the normal HTML preview.
- `.disabled` → render a small placeholder: "Folder Preview is disabled. Open Mac All You Need → Settings → Features to enable."

The Browse Folder *window* (a main-app surface, not an OS extension) toggles cleanly via the activator. The spec is honest: a fully-uninstalled Folder Preview *still has its extension binary in the bundle*; we just short-circuit its output. Genuine removal requires uninstalling MAYN.

### Adding a future feature

1. Append a case to `FeatureID`.
2. Add a `FeatureDescriptor` to the registry — including its view factories, hotkey list, menu items, and any asset packs/caches.
3. Implement one `FeatureActivator`.
4. (Optional) Publish an asset pack zip and add it to the wrapper's manifest.

No edits to `FeatureManager`, `SettingsRoot`, `MenuBarHost`, `HotkeyRegistry`, or onboarding wizard are required — they all iterate the registry.

## 4. Feature pack format & distribution

This section covers **wrapper-managed packs**: zips of binaries pinned to a wrapper release, downloaded the first time the user installs the feature. Provider-managed caches (Voice's Qwen3 model files, future per-provider model downloads) are a separate concern — see § 4b.

### Pack contents

Each downloadable pack is one zip published as a release asset:

```
Downloader-1.0.0.zip
├── manifest.json          # version, schema version, per-file sha256, designated codesign requirement
├── yt-dlp                 # universal binary, signed with MAYN Developer ID
└── ffmpeg                 # universal binary, signed with MAYN Developer ID
```

Today only Downloader has a wrapper-managed pack. Clipboard, Folder Preview, and Voice declare `assetPacks: []`; for them, "install" is just a state flip (Folder Preview also has its OS-extension policy from § 3.3).

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
      "zipSha256": "abc123…",
      "sizeBytes": 201326592,
      "files": {
        "yt-dlp":  { "sha256": "…", "executable": true,  "maxBytes": 50000000 },
        "ffmpeg":  { "sha256": "…", "executable": true,  "maxBytes": 200000000 }
      },
      "codesignRequirement": "anchor apple generic and certificate leaf [subject.OU] = \"<TeamID>\""
    }
  }
}
```

Per-file SHAs (not just the whole-zip SHA) let us detect tampering of individual binaries even if a malicious zip happens to match the outer hash. The `codesignRequirement` is a designated requirement string evaluated by `SecStaticCodeCheckValidity`.

A new wrapper release ships a new manifest with new pack URLs/SHAs/versions; users receive pack updates implicitly when Sparkle delivers the wrapper update (D6).

### Download & verify pipeline

1. User taps "Install" → `URLSession.downloadTask` writes to a `.partial` staging path inside the App Group container, with progress reported to the UI.
2. **Whole-zip SHA-256** verification against manifest. Mismatch → delete partial + show error.
3. **Safe extraction** into `~/Library/Application Support/MacAllYouNeed/Features/<id>/<version>.staging/`:
   - Reject any entry whose normalized path escapes the destination dir (zip-slip protection).
   - Reject symlinks and hard links (no `S_IFLNK` or multi-link entries).
   - Reject entries not in the manifest's `files` allowlist.
   - Reject if cumulative extracted size exceeds `1.5 × sizeBytes` (zip bomb protection).
   - Each extracted file's size must be `≤ maxBytes` from the manifest.
4. **Per-file SHA-256** verification: every extracted file's hash must match its manifest entry.
5. **Code signature verification**: for each executable, evaluate the manifest's `codesignRequirement` via `SecStaticCodeCheckValidity` (`kSecCSDefaultFlags` + `kSecCSCheckAllArchitectures`). Reject if the signature fails or doesn't match the requirement.
6. `chmod +x` executables; strip `com.apple.quarantine` xattr (downloads are quarantined by macOS; required to exec under hardened runtime).
7. **Atomic rename** `<version>.staging/` → `<version>/`. `FeatureManager` transitions `assetState` to `.present(version)`; if user previously selected this feature for activation, also flips `activationState` to `.enabled` and runs the activator.

A failure at any step deletes the staging dir and surfaces a specific, copyable error. No silent partial state.

### Hosting

GitHub Releases. No separate CDN. Public release assets have no bandwidth quota, are served via Fastly globally, and the URL is the same release that publishes the wrapper DMG.

### Code signing

Binaries inside packs are signed with MAYN's Developer ID at CI release time (Plan 7). Combined with the existing `disable-library-validation` entitlement, hardened-runtime can exec them. The pack zip is just a container; the signatures and the manifest's designated requirement are the trust anchors.

### Resumability & failure

- Failed downloads leave only the `.partial` staging file; live path untouched.
- `URLSession` resume data is persisted across app launches.
- Stale `.partial` files older than 7 days are cleaned at app launch.

### Side-load escape hatch

Settings → Advanced exposes "Install pack from file…" so users behind corporate proxies (Risk 3) can fetch the zip manually and install it. **Same** verification pipeline applies (whole-zip SHA, safe extraction, per-file SHA, codesign requirement, quarantine removal). The user must also paste the zip's expected SHA-256 (to bind the side-load to the published release).

## 4b. Provider-managed asset caches (Voice ASR models)

Some features expose plug-in providers whose assets are too dynamic to pin in a wrapper-side manifest. The Voice feature today has Qwen3 ASR variants (~900 MB and ~1.75 GB) that download lazily the first time the user picks them. These are **not** wrapper-managed packs — they're provider-managed caches that the lifecycle still needs to know about.

### `AssetCacheDescriptor`

```swift
struct AssetCacheDescriptor {
    let id: String                              // "voice.qwen3.base", "voice.qwen3.large"
    let displayName: String                     // "Qwen3 ASR (base, ~900 MB)"
    let directoryURL: () -> URL                 // resolved at runtime; provider owns this path
    let estimatedBytes: Int64                   // for UI; actual size queried at uninstall time
    let category: AssetCacheCategory            // .modelWeights, .databaseCache, .other
}
```

A feature lists its caches in `assetCaches: [AssetCacheDescriptor]`. The provider (e.g., `Qwen3Engine`) is still the only thing that *writes* to that directory — the descriptor just gives `FeatureManager` enough information to:

- **Show disk usage** in the Features tab card (sum of all caches' actual on-disk sizes).
- **Offer per-cache deletion** in the Uninstall confirmation sheet (each cache is its own opt-in checkbox).
- **Reclaim space** without uninstalling the whole feature (a "Clear cached models" button in the feature's settings tab).

Provider downloads themselves remain provider business: the provider owns the URL, integrity check, and progress reporting for its own model files. This spec doesn't try to centralize provider downloads — that's a per-provider concern. What it centralizes is **awareness and cleanup**.

### Voice today, concretely

- `assetPacks: []` — no wrapper-managed pack.
- `assetCaches:` two entries, one for the Qwen3 base variant and one for the large variant. Groq Whisper (cloud ASR) has no cache.
- Voice's Settings tab continues to host its existing "Download Qwen3 model" affordance; nothing about provider download UX changes.

## 5. Lifecycle: install / enable / disable / uninstall

### State (recap from § 3)

`FeatureRuntimeState = (assetState, activationState)`. The product surface ("Install / Enable / Disable / Uninstall" buttons) maps these compounds to user-visible verbs:

| `assetState` | `activationState` | User sees | What changes when they act |
|---|---|---|---|
| `.notRequired` | `.disabled` | "Enable" button | Run activator → `.enabled` |
| `.notRequired` | `.enabled` | "Disable" toggle | Run deactivator → `.disabled` |
| `.notDownloaded` | `.disabled` | "Install" button | Download pack → on success: `.present` + `.enabled` |
| `.downloading` | `.disabled` | progress + "Cancel" | Cancel: drop staging, return to `.notDownloaded` |
| `.downloadFailed` | `.disabled` | "Retry" + reason | Retry: re-enter download |
| `.present` | `.disabled` | "Enable" + "Uninstall…" | Enable runs activator; Uninstall removes assets |
| `.present` | `.enabled` | "Disable" + "Uninstall…" | Disable runs deactivator; Uninstall runs deactivator then removes assets |

### Legal transitions

```
assetState transitions (managed by FeatureManager during install/uninstall):
  notRequired       (terminal — Swift-only feature)
  notDownloaded     --install-->     downloading       --success-->  present(version)
                                                       --failure-->  downloadFailed
  downloadFailed    --retry-->       downloading
  downloadFailed    --cancel-->      notDownloaded
  present(version)  --uninstall-->   notDownloaded     (auto-deactivate first if needed)
  present(old)      --updatePack-->  downloading       --success-->  present(new)

activationState transitions (managed by FeatureManager):
  disabled  --enable-->   enabled    (rejected if assetState requires .present and isn't)
  enabled   --disable-->  disabled
  enabled   --(asset uninstall)-->  disabled    (forced; deactivator runs)
```

`FeatureManager` rejects (or no-ops) any transition not on this list. Concurrent calls for the same feature serialize via the actor; the second is dropped if it would be a no-op or queued otherwise.

### `activate()` responsibilities (entering `activationState == .enabled`)

- Refuse to run if `assetState != .present` and the feature requires assets — surface as activator error → state stays `.disabled` with a flagged error in Settings.
- Probe required binaries on disk; if missing despite `.present`, demote `assetState` to `.downloadFailed("missing binary on disk")` and surface a "Reinstall" affordance (Risk 5).
- Register declared hotkeys (from descriptor's `hotkeys`).
- Mount menu bar contributions (from descriptor's `menuBarItemFactory`).
- Start background workers (clipboard poller, dispatch server, voice hotkey listener, etc.).
- Verify required permissions; trigger first-time prompts if needed.
- Re-write the feature-state Darwin notification so the daemon can react.

### `deactivate()` responsibilities (leaving `activationState == .enabled`)

- Unregister declared hotkeys.
- Unmount menu bar contributions.
- Stop background workers.
- Does **not** revoke OS permissions (we can't programmatically revoke; we just stop using them).
- Does **not** touch user data or asset files.
- Re-write the feature-state Darwin notification.

### Uninstall

Deletes `~/Library/Application Support/MacAllYouNeed/Features/<id>/<version>/` and any sibling versioned directories for that feature. The Uninstall confirmation sheet:

- Shows pack size that will be reclaimed.
- Lists each declared `assetCache` (e.g., "Qwen3 ASR base model — 912 MB", "Qwen3 ASR large model — 1.74 GB") with an opt-in checkbox per cache. **All checkboxes default unchecked.**
- May offer feature-data cleanup as a separate clearly-labeled opt-in (e.g., "Also clear clipboard history (~12 MB)" for Clipboard, "Also clear download history records" for Downloader — note: this clears the **records**, not the user's downloaded video files). Defaults unchecked.
- **Does not offer to delete user-authored documents.** Downloaded video files live where the user told the Downloader to put them; they are user documents and are out of scope for feature uninstall. If the user wants those gone, they delete them in Finder. The Downloads tab can have a separate "Reveal downloads folder…" link, but it does not appear in the Uninstall sheet.

### Failure handling

- If `activate()` throws after a successful install (e.g., hotkey conflict), `activationState` stays `.disabled` with a flagged error visible in Settings. Asset bytes are valid; install is not reverted.
- If `deactivate()` throws, log and force-progress the state machine; never leave the user in a transitional state.

## 6. Onboarding redesign

The current 6-step wizard (Welcome / Accessibility / FDA / Notifications / Sync / Done) is replaced by a feature-driven flow. `OnboardingState` and `OnboardingWindowController` are reused; the steps inside change.

### New flow

```
1. Welcome
2. Feature Picker             ← new, replaces fixed permission steps
3. Per-feature setup          ← repeats once per chosen feature, in registry order
   3a. Download progress      (skipped if descriptor.assetPacks is empty)
   3b. Permission grants      (only the ones this feature actually declares)
   3c. Feature-specific config (descriptor.onboardingSetupFactory; Voice uses this for ASR provider + optional Qwen3 model download)
4. Done                       ← summary + "you can change this any time in Settings → Features"
```

### Feature picker step

Grid of cards, one per registry entry. Each card shows: icon, name, one-line summary, "Learn more" disclosure (revealing `detailDescription`, declared permissions, download size), and a checkbox. **All cards default to unchecked** to honor the "wrapper has no functions" framing.

A "Skip for now" button is allowed and exits onboarding with zero features enabled — a legitimate end state. The user can always return via Settings → Features.

Cards render directly from `FeatureRegistry`, so a new feature appears here automatically once its descriptor lands.

### Per-feature setup step

For each selected feature in registry order:

- If `assetPacks` is non-empty: download-progress screen with size, progress bar, retry on failure. Stays on this screen until install completes.
- Permission prompts the feature declares. Mirrors the existing TCC auto-advance pattern.
- Feature-specific config screens supplied by the descriptor's `onboardingSetupFactory`. Today only Voice provides one (it reuses the existing `VoiceSettingsView` flow including provider selection and any provider-managed model download). Provider-managed asset downloads (§ 4b) happen here, in the provider's own UI.

### Done step

Lists what was installed/enabled and what was skipped. Closes with: "You can install or remove features any time from Settings → Features."

### Existing-user upgrade

Onboarding does not re-run (gated by `OnboardingState`). A separate one-time "What's new" sheet surfaces on first launch after upgrade — see § 7.

### Re-running onboarding

Settings → Advanced gains a "Re-run onboarding…" action that resets `OnboardingState`. Useful for support and for users who want to start fresh.

## 7. Migration for existing users

Two coordinated mechanisms run when an existing user upgrades to the first modular release:

1. **Sparkle pre-install script** copies binaries out of the old bundle into the new `Features/` directory **before** Sparkle replaces the app bundle. This means the new app finds yt-dlp + ffmpeg already in place — no re-download for upgraders.
2. **First-launch migration** (the new app) reads `AppGroupSettings`, decides each feature's runtime state based on prior usage, and shows a one-time "What's new" sheet.

### 7.1 Sparkle pre-install script

Sparkle supports `installerArguments` and a pre-install hook that runs from inside the new bundle before the swap. Our script:

```bash
#!/bin/bash
# pre-install: copy binaries out of the OLD app bundle into AppGroup Features/
OLD_APP="$1"   # path to currently-installed app
NEW_VERSION="$2"   # new wrapper version, parsed from new bundle's manifest
APPGROUP_BASE="$HOME/Library/Application Support/MacAllYouNeed"
DST="$APPGROUP_BASE/Features/downloader/$NEW_VERSION"

mkdir -p "$DST"
for bin in yt-dlp ffmpeg; do
    src="$OLD_APP/Contents/Resources/$bin"
    [ -f "$src" ] && cp -p "$src" "$DST/$bin"
done

# Write a marker that the new app reads to know migration-via-script ran
touch "$APPGROUP_BASE/Features/.sparkle-migration-pending"
exit 0
```

The script is best-effort: if it fails (e.g., the old bundle doesn't contain the binaries because the user is upgrading from a much older release), the new app falls back to "needs download" and prompts on first launch. The script runs as the user, not as root, so it can write to `~/Library/Application Support/`.

The script is signed and notarized as part of the wrapper (Sparkle requires this). Detail of exact integration with the existing Sparkle release pipeline is deferred to Plan 7.

### 7.2 First-launch migration logic

Triggered by a `migratedToFeatureModel: Bool` sentinel in `AppGroupSettings`, runs once on first launch after upgrade.

1. **Detect prior usage** for each feature, in this order of confidence:
   - **Direct evidence** (state in shared DB exists): clipboard records → Clipboard was used; download records → Downloader was used; voice settings configured → Voice was used; folder preview extension recently invoked → FolderPreview was used.
   - **Indirect evidence**: the feature's settings tab has any non-default value.
   - **No evidence**: assume passively installed but not actively used.
2. **Set each feature's `(assetState, activationState)`.**
   - **Downloader:**
     - If pre-install script wrote binaries to `Features/downloader/<currentVersion>/` and per-file SHAs match the wrapper's manifest → `assetState = .present`.
     - Else if SHAs don't match → `assetState = .downloadFailed("version mismatch — please reinstall")`. UI shows a one-tap "Update Downloader" button.
     - Else → `assetState = .notDownloaded`. UI shows "Install" button.
     - For activation: if usage evidence → `activationState = .enabled`; else `.disabled`.
   - **Clipboard / Folder Preview / Voice (Swift-only):** `assetState = .notRequired`. `activationState = .enabled` if usage evidence; else `.disabled`.
   - **Voice with Qwen3 model files on disk** from a prior install: detect by probing the cache directory; if present, leave them in place (they're a provider-managed cache, not asset state). The Voice settings tab will show the existing models as available providers.
3. **Show a one-time "What's new" sheet** on first launch (separate from onboarding): "Mac All You Need is now modular — you can pick which features to use. Nothing was disabled; you can change anything in Settings → Features." Single button: *Open Features Settings*.
4. **Persist the sentinel.**
5. **Delete the `.sparkle-migration-pending` marker** if present.

### Edge cases

- **Corrupted detection state** (DB unreadable): assume all four features have `activationState = .enabled` to avoid silently breaking workflows. User can disable from Settings.
- **Downgrade then re-upgrade**: sentinel persists; migration runs at most once per user.
- **Fresh install on a Mac that previously had MAYN** (Application Support wiped): no DB → treated as new user → onboarding runs.
- **Sparkle script ran but new app version differs from script's `NEW_VERSION` arg** (race during partial release): SHA check in step 2 catches this and demotes to `.downloadFailed("version mismatch")`; UI prompts re-download. No silent failure.

## 8. Settings redesign

### Tab structure

```
General │ Features │ Hotkeys │ Advanced │ <feature tabs…>
```

- **General**, **Features**, **Hotkeys**, **Advanced** are always visible (wrapper-level).
- A per-feature tab (Clipboard / Downloads / Folder Preview / Voice) appears whenever the feature is *visible to the user* — i.e., either `assetState == .notRequired`, `.present`, `.downloading`, or `.downloadFailed`. It is hidden when `assetState == .notDownloaded` (the feature card lives in the Features tab in that state — there's nothing else to configure yet).
- Per-feature tabs render in `FeatureRegistry` order — `SettingsRoot` iterates `FeatureRegistry` and asks each descriptor for its `settingsTabFactory`.
- The current **Sync** tab is removed entirely (Plan 2 deferred indefinitely).

### Features tab — the catalog/manager

Same card grid as the onboarding picker, but cards show live state and have actions. Control labels map from the orthogonal state pair (§ 5):

| `(assetState, activationState)` | Primary control on card | Secondary actions in `⌄` menu |
|---|---|---|
| `(.notRequired, .disabled)` | `[ Enable ]` | — |
| `(.notRequired, .enabled)`  | `[● Enabled]` toggle | "Open settings" |
| `(.notDownloaded, .disabled)` | `[ Install ]` | — |
| `(.downloading, .disabled)` | progress bar + `[ Cancel ]` | — |
| `(.downloadFailed, .disabled)` | `[ Retry ]` + reason | "View log" |
| `(.present, .disabled)` | `[ Enable ]` | "Uninstall…" |
| `(.present, .enabled)`  | `[● Enabled]` toggle | "Uninstall…", "Open settings", "Clear cached models…" (if `assetCaches` non-empty) |

Cards also display: pack size on disk (sum of pack + caches), declared permissions with a granted/missing indicator, and any active error from a previous activation attempt.

### Uninstall confirmation sheet

Layout (per § 5):

- **Pack to remove:** `Features/downloader/1.0.0/` (192 MB) — always removed.
- **Caches to remove (opt-in, default unchecked):**
  - ☐ Qwen3 ASR base model (912 MB)
  - ☐ Qwen3 ASR large model (1.74 GB)
- **Feature data to remove (opt-in, default unchecked):**
  - ☐ Clear clipboard history (12 MB) — *applies to Clipboard*
  - ☐ Clear download history records (8 KB) — *applies to Downloader; does not delete your video files*
  - ☐ Clear snippets — *applies to Clipboard*
- **Not affected (always preserved):** any user-authored documents (downloaded video files, exported clipboard items). The sheet says this explicitly so the user isn't anxious about losing files.

The exact rows are produced by iterating the descriptor's `assetCaches` plus a per-feature "feature data" enumeration. New features auto-contribute their rows.

### Per-feature settings tabs

Existing `ClipboardSettingsView`, `DownloadsSettingsView`, `FolderPreviewSettingsView`, `VoiceSettingsView` are reused unchanged. They're invoked via the descriptor's `settingsTabFactory`. When `activationState == .disabled`, the tab still appears with a banner: *"This feature is disabled. Settings here will apply when you re-enable it."*

### Hotkeys tab

Already a global cross-feature view. Now built by iterating `FeatureRegistry` and consuming each descriptor's `hotkeys`. Hotkeys belonging to a disabled (or not-installed) feature are visible but greyed with a "Disabled" or "Not installed" badge.

### Advanced tab

Gains:
- "Re-run onboarding…"
- "Open feature install directory in Finder"
- "Install pack from file…" (side-load escape hatch — § 4)
- "Reset all features…" (destructive: returns every feature to `(.notDownloaded | .notRequired, .disabled)`, with confirmation)

## 9. Concurrency, persistence, and process boundaries

- All `FeatureManager` writes happen in the **main app**; the daemon is read-only on feature state. Reads cross the App Group `UserDefaults` boundary.
- `FeatureManager` is a Swift actor; no two transitions for the same feature interleave.
- Concurrent install requests for the same feature: second call is a no-op while the first is in flight.
- Concurrent install requests for different features: allowed; each runs independently.
- **Daemon observation uses Darwin notifications**, not Foundation `NotificationCenter` or KVO (neither crosses process boundaries). The main app posts `com.macallyouneed.featureStateDidChange` via `CFNotificationCenterPostNotification` after every persisted write. The daemon listens via `CFNotificationCenterAddObserver` on `CFNotificationCenterGetDarwinNotifyCenter()` and reloads `AppGroupSettings` synchronously on each notification.
- **Daemon startup gating.** On launch, the daemon reads `FeatureManager` state from `AppGroupSettings` *before* spinning up any per-feature workers. Workers (clipboard pasteboard poller, snippet expander, dispatch server, etc.) are tied 1:1 to feature `activationState == .enabled`; a feature in `.disabled` produces no workers. The daemon already uses this pattern for one Darwin notification today (see `ClipboardDaemon/DaemonContainer.swift` reload-on-notify); we extend that mechanism to feature state.
- **Reload semantics.** When the daemon receives the Darwin notification, it diffs current vs. previous per-feature `activationState` and starts/stops workers in response. State is the source of truth; workers are derived.

## 10. On-disk layout

```
~/Library/Application Support/MacAllYouNeed/
├── Features/
│   ├── downloader/
│   │   └── 1.0.0/                          # wrapper-managed pack
│   │       ├── manifest.json
│   │       ├── yt-dlp
│   │       └── ffmpeg
│   ├── voice/
│   │   └── caches/                         # provider-managed; § 4b
│   │       ├── qwen3-base/                 # AssetCacheDescriptor "voice.qwen3.base"
│   │       └── qwen3-large/                # AssetCacheDescriptor "voice.qwen3.large"
│   ├── .sparkle-migration-pending          # marker dropped by pre-install script (§ 7.1)
│   └── <future-feature>/<version>/…
├── Staging/
│   └── downloader-1.0.0.partial            # in-flight downloads + .resume-data sidecar
└── Logs/
    └── feature-install.log                 # rotating, surfaced via "View log"
```

User data (clipboard DB, downloaded video files in user-chosen folders, exported snippets) lives in its existing locations and is **never** under `Features/`. Uninstall touches only `Features/<id>/` (and only the cache subdirectories the user opted into).

## 11. Testing strategy

### Unit tests (no network, no disk)

- `FeatureManager` state machine: every legal transition + every illegal one across both axes (`assetState`, `activationState`). Pure state, fully deterministic.
- `FeatureRegistry` ordering, lookup by id, presence of required descriptor fields including factories.
- `FeaturePackManifest` JSON decoding: malformed manifests, schema-version mismatches, missing fields, missing per-file SHAs, missing codesign requirement.
- Migration logic (§ 7.2): given a synthetic `AppGroupSettings` + DB state + presence/absence of pre-install marker, assert each feature lands in the expected `(assetState, activationState)`. Table-driven.

### Component tests (real disk, no network)

- Install pipeline against local fixture zips (`file://` URLs) covering each security check independently:
  - **Happy path** — verify whole-zip SHA, safe extract, per-file SHA, codesign requirement, quarantine xattr removal, atomic move.
  - **Whole-zip SHA mismatch** — abort, no live state.
  - **Per-file SHA mismatch** — abort, no live state.
  - **Zip-slip attempt** (entry path `../../malicious`) — abort.
  - **Symlink in zip** — abort.
  - **Unexpected file in zip** (not in manifest allowlist) — abort.
  - **Zip bomb** (extracted size > 1.5× declared) — abort.
  - **Codesign requirement mismatch** (binary signed by different identity) — abort.
- Side-load: same matrix via "Install from file…" path.
- Uninstall: pack directory gone; opt-in caches gone only when checked; user data untouched.
- Concurrent operations: serialized per feature.

### Integration tests (real network, gated)

- Custom test trait so CI can opt in. Downloads a real pack from a test GitHub Release into a temp directory, verifies SHA, runs the binary's `--version`.
- Run nightly + on PRs that touch `FeatureManager` or `scripts/fetch-binaries.sh`. Not on every PR.

### Cross-process tests

- Darwin-notification round-trip: spawn a child process simulating the daemon, post `com.macallyouneed.featureStateDidChange` from the parent, assert the child sees the new state and starts/stops a synthetic worker.
- Daemon startup gating: launch daemon with each combination of feature activation states preset in `AppGroupSettings`; assert the right workers (and only those) are running.

### UI tests

- Onboarding: picker step renders one card per registry entry; "Skip" leaves all features in their default state; selecting Downloader triggers the download progress screen.
- Settings → Features: snapshot tests of each card state from the table in § 8, plus interaction tests for Install/Enable/Disable/Uninstall buttons.
- Folder Preview disabled-state placeholder: invoke the Quick Look extension while feature is disabled in `AppGroupSettings`; assert the placeholder view is rendered.
- Done with SwiftUI's preview-driven snapshot testing (already used in the project).

### Manual QA matrix (per release)

- Fresh install on macOS 14, 15, 26.
- Upgrade install with prior usage of: Clipboard only / Downloader only / All four / None. Confirm Sparkle pre-install script ran and binaries are in place.
- Install Downloader → kill app mid-download → relaunch (resumability via `URLSession` resume data).
- Install Downloader → toggle airplane mode → retry (error handling).
- Install Downloader → corrupt the SHA in manifest → install (verification failure path).
- Side-load a pack with a symlink injected → install rejects.
- Disable Voice → confirm microphone use stops; System Settings still shows the permission (we don't revoke). Re-enable → activator re-prompts if user manually revoked.
- Uninstall Downloader → pack gone, user's downloaded video files preserved. Re-enable Downloader → re-download starts.
- Uninstall Voice with Qwen3 large model checkbox unchecked → caches retained; checkbox checked → caches removed.
- Folder Preview disabled in app → Quick Look on a folder shows placeholder; re-enable → normal preview returns.

## 12. Risks & mitigations

| # | Risk | Likelihood | Mitigation |
|---|---|---|---|
| 1 | **Gatekeeper / hardened runtime blocks downloaded binaries.** | High | Strip `com.apple.quarantine` xattr after verifying whole-zip SHA, per-file SHA, and designated codesign requirement (§ 4). Same pattern Sparkle uses. Test on fresh user account on each macOS version. |
| 2 | **Wrapper update + pack update get out of sync** (release published partially). | Medium | CI publishes the wrapper-side manifest update *last*, after all pack zips are uploaded and verified. If a referenced pack is missing, install UI shows a clear error; old pack (if `assetState == .present(oldVersion)`) keeps working. |
| 3 | **User behind corporate proxy / firewall** that blocks `objects.githubusercontent.com`. | Medium | Install error sheet shows the exact URL + a "Copy URL" button. Side-load via Advanced → "Install pack from file…" available from day one. |
| 4 | **Disk full mid-install.** | Low | Staging dir + atomic rename (§ 4). Cleanup of `.partial` files older than 7 days at app launch. |
| 5 | **User manually deletes pack directory in Finder** while feature is enabled. | Low | Activator probes for required binaries on activate; missing → demote `assetState` to `.downloadFailed("missing binary")` with a "Reinstall" affordance + banner in feature's settings tab. |
| 6 | **Permission-revocation drift.** User disables, manually revokes permission, re-enables — feature can't run. | Medium | Each `activate()` re-verifies declared permissions and prompts if missing. Already the pattern Voice uses. |
| 7 | **AppGroupSettings race between main app and daemon** for `FeatureManager` state. | Medium | All writes go through main app's actor; daemon is read-only. Darwin notification triggers daemon reload; daemon diff-applies to its workers (§ 9). |
| 8 | **Sparkle pre-install script fails** (e.g., old bundle is from before binaries-in-Resources, or sandboxed environment). | Medium | Best-effort: missing binaries → migration falls back to `.notDownloaded`; user sees a one-tap "Install Downloader" prompt in the "What's new" sheet. No silent failure. |
| 9 | **Provider-managed cache (Voice Qwen3 model) becomes orphan** if the provider is removed in a future release but the cache remains on disk. | Medium | When the wrapper releases drop a provider, the new manifest also drops its `AssetCacheDescriptor`. A migration step at app launch detects orphan dirs under `Features/voice/caches/` not declared by any current descriptor and offers a one-time "Clean up old Voice models (X MB)" prompt. |
| 10 | **OS-extension can't be runtime-uninstalled** (Folder Preview Quick Look extension). | High (architectural) | Acknowledged in § 3.3: extension always lives in the bundle; `respectsFeatureFlag` short-circuits to a placeholder when disabled. Genuine removal requires uninstalling MAYN. UI is honest about this in the Folder Preview card. |
| 11 | **Future feature outgrows `FeatureDescriptor` extension points** (needs a new factory type, sub-packs, model file >2 GB, etc.). | High over time | `FeaturePackManifest.schemaVersion` lets us evolve manifest format. `assetPacks: [AssetPack]` is already plural. Descriptor is a value type; adding optional fields is non-breaking. |
| 12 | **Telemetry blind-spot.** Failed installs are only visible to the affected user. | Low (acceptable) | Surface a clear, copyable error in the install UI so user-reported issues are actionable. No telemetry until user explicitly opts in (matches app's privacy posture). |
| 13 | **Existing user surprised** that a feature "moved" because it's now in the Features tab. | Low | Migration's "What's new" sheet (§ 7.2) explicitly says nothing was disabled; Hotkeys tab still shows everything they had bound. |

## 13. What this design explicitly does not change

- Code signing of the wrapper itself, notarization of the DMG — Plan 7 territory, unchanged.
- Sync engine — Plan 2 deferred indefinitely; the Sync settings tab is removed.
- Apple Silicon / Intel split — feature packs ship universal binaries via `lipo`, same as today.
- Existing per-feature settings views — reused as-is via `settingsTabFactory`; only their visibility and host plumbing change.
- Provider-internal download UX (e.g., how `Qwen3Engine` reports its model download progress) — out of scope; the lifecycle only learns about the resulting cache directories via `assetCaches`.
- The XPC daemon's existing responsibilities — only the addition of feature-state Darwin observation + worker gating is new (§ 9).

## 14. Open questions for implementation planning

These are intentionally deferred until the implementation plan is written, but flagged here so they aren't forgotten:

1. Exact persisted serialization of `FeatureRuntimeState` (raw value strings vs. JSON-coded enum vs. separate keys per axis).
2. Where to surface install-progress notifications when the user closes the Settings window mid-download (menu bar dot? notification? both?).
3. Per-feature `activate()` ordering on app launch when multiple features are enabled (parallel vs. sequential; some features may have init dependencies — e.g., dispatch server + downloader integration).
4. Whether the daemon needs a "shutdown all per-feature workers" bulk path for app quit, or whether per-feature `deactivate()` driven by the activation Darwin notification is enough.
5. Sparkle integration: exact name and signature of the pre-install script hook used by Sparkle 2 (`SUDownloadOperation`'s install delegate) and how to bind `NEW_VERSION` to the version string in the new bundle.
6. How the wrapper detects an orphaned provider cache (Risk 9): walk-the-directory at launch vs. probe-per-descriptor.
7. Whether `FeatureID` stays a closed enum or moves to a string-typed identifier (closed enum is safer for compile-time exhaustiveness; string-typed is better if the registry ever loads from JSON instead of Swift).
