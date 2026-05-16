# Modular Features — Implementation Plan Index

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement each phase plan task-by-task. Steps in phase plans use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert MAYN from a monolithic app to a registry-driven system with modular activation and on-demand heavy assets, per the design at `docs/superpowers/specs/2026-05-15-modular-features-design.md`.

**Architecture:** A `FeatureRegistry` of `FeatureDescriptor`s is the single source of truth. `FeatureManager` (actor) owns each feature's `(assetState, activationState)` runtime state, persists to App Group settings, and posts a Darwin notification on every change. Existing subsystems are wrapped in `FeatureActivator`s and made startable/stoppable. Heavy binaries (yt-dlp + ffmpeg) and provider model caches (Voice Qwen3) become on-demand. UI shells (Settings tabs, menu bar, hotkey list, onboarding wizard) iterate the registry instead of hardcoding per-feature code.

**Tech Stack:** Swift 5.9+, SwiftUI, AppKit, Swift actors, `URLSession`, `SecStaticCodeCheckValidity`, `CFNotificationCenterGetDarwinNotifyCenter`, `AppGroupSettings`, GRDB (existing), Sparkle 2 (Plan 7 integration point).

---

## How to read this plan

The work is split into **12 phase plans**, each in `docs/superpowers/plans/2026-05-15-modular-features/`. Each phase is independently committable and leaves the system in a working state. The goal of the split:

- **Reviewable PRs** — one phase = one PR.
- **Parallelizable execution** — phases without dependencies can run in parallel sub-agents.
- **Bisectable** — if something breaks weeks later, `git bisect` lands on a single phase.

## Dependency graph

```
                    ┌─────────────────────────────────┐
                    │ Phase 01 — Foundation           │
                    │ FeatureID, Descriptor,          │
                    │ Registry, FeatureManager actor  │
                    └────────────────┬────────────────┘
                                     │
                ┌────────────────────┼────────────────────┐
                ▼                    ▼                    ▼
   ┌────────────────────┐ ┌──────────────────────┐
   │ Phase 02 — Pack    │ │ Phase 03 — Activators│  ◄── PARALLEL with Phase 02
   │ Infrastructure     │ │ (4 sub-agents inside)│      Each activator wraps an
   │ Manifest, download │ │ Clipboard, FolderPv, │      existing subsystem; the
   │ + verify pipeline  │ │ Downloader, Voice    │      4 sub-tasks are mutually
   └─────────┬──────────┘ └──────────┬───────────┘      independent.
             │                       │
             └───────────┬───────────┘
                         ▼
       ┌─────────────────────────────────┐
       │ Phase 04 — Registry-driven      │
       │ Bootstrap                       │
       │ AppController, SettingsRoot,    │
       │ MenuBarHost, HotkeyRegistry     │
       │ all iterate the registry.       │
       │ All features default to enabled │
       │ to preserve current behavior.   │
       └────────────────┬────────────────┘
                        ▼
       ┌─────────────────────────────────┐
       │ Phase 05 — Features Tab UI      │
       │ Settings → Features cards;      │
       │ Enable/Disable wired through    │
       │ FeatureManager. Per-feature     │
       │ tabs become conditional.        │
       └──┬──────┬──────┬──────┬─────────┘
          │      │      │      │
          ▼      ▼      ▼      ▼      ◄── PARALLEL fan-out
   ┌──────────┐┌──────────┐┌──────────────┐┌────────────────┐
   │ Phase 06 ││ Phase 07 ││ Phase 08     ││ Phase 10       │
   │ Downloader││ Voice    ││ FolderPreview││ Daemon Darwin  │
   │ pack     ││ asset    ││ placeholder  ││ observation    │
   │          ││ caches   ││ (extension)  ││ + worker gating│
   └────┬─────┘└──────────┘└──────────────┘└────────────────┘
        │
        ▼
   ┌──────────────────────────────────┐
   │ Phase 09 — Onboarding redesign   │
   │ Welcome → Picker →               │
   │ Per-feature setup → Done         │
   └────────────┬─────────────────────┘
                ▼
   ┌──────────────────────────────────┐
   │ Phase 11 — Migration             │
   │ Sparkle pre-install script;      │
   │ first-launch migration logic;    │
   │ "What's new" sheet               │
   └────────────┬─────────────────────┘
                ▼
   ┌──────────────────────────────────┐
   │ Phase 12 — Cleanup & polish      │
   │ Remove Sync tab; Advanced actions│
   │ (re-run onboarding, install from │
   │ file, reset all features); copy  │
   │ pass; final QA matrix sweep      │
   └──────────────────────────────────┘
```

## Parallelization map

| Wave | Phases that can run concurrently | Why |
|---|---|---|
| 1 | **01** alone (blocking) | Everything depends on the foundation types and `FeatureManager`. |
| 2 | **02** ∥ **03** | Both depend only on Phase 01. Pack pipeline (02) and the four feature activators (03) touch disjoint files. |
| 3 | **04** alone | Integrates 02 + 03 results into the registry-driven bootstrap. Touches `AppController`, `SettingsRoot`, `MenuBarHost`, `HotkeyRegistry`. |
| 4 | **05** alone | Builds the Features tab UI. Single file group; not worth splitting. |
| 5 | **06** ∥ **07** ∥ **08** ∥ **10** | All four depend on 05 (or earlier) but touch disjoint code. Downloader pack (06), Voice caches (07), Folder Preview extension (08), and daemon (10) are independent. |
| 6 | **09** alone | Onboarding picker reuses card UI from 05 and pack download UI from 06. |
| 7 | **11** alone | Migration depends on the final disk layout from 06 and the onboarding decision tree from 09. |
| 8 | **12** alone | Final cleanup and polish; touches many surfaces. |

**Inside Phase 03**, the four activator wrappers can themselves run in parallel sub-agents (one per feature: `clipboard`, `folderPreview`, `downloader`, `voice`). The per-feature work doesn't touch shared files. This is the largest parallel fan-out in the plan.

**Recommended sub-agent dispatch**:
- Wave 2: dispatch one sub-agent for Phase 02, one for each of the four Phase 03 sub-tasks (5 concurrent agents, after Phase 01 lands).
- Wave 5: dispatch one sub-agent per phase in {06, 07, 08, 10} (4 concurrent agents).

## Phase summaries

### Phase 01 — Foundation
**File:** `2026-05-15-modular-features/01-foundation.md`
**Outputs:** `FeatureID`, `FeatureRuntimeState`, `AssetState`, `ActivationState`, `FeatureDescriptor` (with all factory fields), `FeatureRegistry`, `FeatureActivator` protocol, `FeatureManager` actor with state machine, App Group persistence layer, Darwin notification posting (consumer added in Phase 10).
**Tests:** State-machine truth-table tests (every legal/illegal transition), `FeatureRegistry` lookup tests, `FeaturePackManifest` JSON decoding tests (manifest types defined here, used by Phase 02).
**Depends on:** Nothing.
**Unlocks:** Phase 02, Phase 03.

### Phase 02 — Pack infrastructure
**File:** `2026-05-15-modular-features/02-pack-infrastructure.md`
**Outputs:** `PackDownloader` (runs `URLSession`, reports progress), `PackInstaller` (zip-slip-safe extract, per-file SHA, codesign verification, quarantine xattr removal, atomic rename), `PackUninstaller`, `SideloadInstaller` (same pipeline for "Install from file…").
**Tests:** Component tests against local fixture zips covering each security check independently (whole-zip SHA mismatch, per-file SHA mismatch, zip-slip, symlink, unexpected file, zip bomb, codesign mismatch, happy path).
**Depends on:** Phase 01.
**Unlocks:** Phase 04 (FeatureManager wires Phase 02 services into install/uninstall transitions).

### Phase 03 — Feature activators (4 parallel sub-tasks)
**File:** `2026-05-15-modular-features/03-activators.md`
**Outputs:** `ClipboardActivator`, `FolderPreviewActivator`, `DownloaderActivator`, `VoiceActivator` — each conforms to `FeatureActivator` and wraps the existing initialization code from `AppController`. `FeatureDescriptor` instances for each feature populate the registry (without the asset packs — those land in Phase 06+).
**Tests:** Activator lifecycle tests (activate sets up workers, deactivate tears them down, idempotency).
**Depends on:** Phase 01.
**Unlocks:** Phase 04.

### Phase 04 — Registry-driven bootstrap
**File:** `2026-05-15-modular-features/04-registry-driven-bootstrap.md`
**Outputs:** `AppController` no longer hardcodes feature initialization — it iterates the registry, calling `activator.activate()` for each feature whose `activationState == .enabled`. `SettingsRoot` builds tabs from `descriptor.settingsTabFactory`. `MenuBarHost` mounts items from `descriptor.menuBarItemFactory`. `HotkeyRegistry` loops `descriptor.hotkeys`. **All four features default to `.enabled` so user-visible behavior is unchanged.**
**Tests:** Integration test that boots `AppController` and asserts each feature's activator ran once; same with one feature pre-disabled in `AppGroupSettings` to assert it does not run.
**Depends on:** Phase 02, Phase 03.
**Unlocks:** Phase 05.

### Phase 05 — Features tab UI
**File:** `2026-05-15-modular-features/05-features-tab-ui.md`
**Outputs:** `FeaturesTabView`, `FeatureCardView` (one per registry entry), Enable/Disable toggle, Uninstall confirmation sheet (caches enumeration, opt-in checkboxes per cache), per-feature settings tab visibility tied to state, Hotkeys tab grey-out for disabled features, Sync tab removal.
**Tests:** Snapshot tests for each card state from § 8 of the spec; interaction tests (tap Enable → state changes; tap Disable → state changes).
**Depends on:** Phase 04.
**Unlocks:** Phase 06, 07, 08, 10 (all parallel after this).

### Phase 06 — Downloader pack (first asset-pack feature)
**File:** `2026-05-15-modular-features/06-downloader-pack.md`
**Outputs:** `Resources/FeaturePackManifest.json` shipping with the wrapper, `DownloaderActivator` updated to require `assetState == .present`, build-time CI step that signs the binaries and computes per-file SHAs for the manifest, Install button on Downloader card wires Phase 02 `PackDownloader`/`PackInstaller`, "Install pack from file…" side-load hook in Advanced tab.
**Tests:** Integration test fakes a small pack zip in a local fixture, runs the full install pipeline, asserts pack lands in `Features/downloader/<version>/`, activator can run yt-dlp.
**Depends on:** Phase 05.
**Unlocks:** Phase 09, Phase 11.

### Phase 07 — Voice asset caches
**File:** `2026-05-15-modular-features/07-voice-asset-caches.md`
**Outputs:** `AssetCacheDescriptor` for `voice.qwen3.base` and `voice.qwen3.large` populated in the Voice descriptor, Uninstall sheet enumerates these caches with on-disk size, "Clear cached models…" action in Voice settings tab, orphan-cache detection at app launch (Risk 9 from spec).
**Tests:** Synthetic cache directory under `Features/voice/caches/qwen3-base/` → uninstall sheet shows it; checkbox checked → directory removed; checkbox unchecked → directory preserved.
**Depends on:** Phase 05.
**Unlocks:** None (independent leaf).

### Phase 08 — Folder Preview placeholder
**File:** `2026-05-15-modular-features/08-folderpreview-placeholder.md`
**Outputs:** `OSExtensionPolicy` enum integrated into `FolderPreviewActivator`'s descriptor with `respectsFeatureFlag: true`, FolderPreview extension target reads `AppGroupSettings.featureState(for: .folderPreview)` on every preview request, renders a placeholder `NSAttributedString` view when disabled.
**Tests:** UI test invokes the QL extension via `qlmanage` after writing `activationState = .disabled` to the App Group; asserts placeholder text appears in the rendered output.
**Depends on:** Phase 05 (descriptor structure).
**Unlocks:** None (independent leaf).

### Phase 09 — Onboarding redesign
**File:** `2026-05-15-modular-features/09-onboarding-redesign.md`
**Outputs:** New `OnboardingState` cases (`featurePicker`, `featureSetup`), `FeaturePickerView` (card grid, all unchecked), per-feature setup wizard that sequences download → permissions → `descriptor.onboardingSetupFactory()`, new "Done" step with installed/skipped summary, "Skip for now" exit allowed.
**Tests:** UI test runs the wizard, picks Downloader, asserts download progress screen appears, asserts permission prompts only for declared permissions; "Skip" path leaves all features `.disabled`.
**Depends on:** Phase 06.
**Unlocks:** Phase 11.

### Phase 10 — Daemon Darwin observation + worker gating
**File:** `2026-05-15-modular-features/10-daemon-darwin-observation.md`
**Outputs:** `FeatureStateObserver` in `ClipboardDaemon` that listens on `com.macallyouneed.featureStateDidChange`, rereads `AppGroupSettings`, diffs per-feature activation state, starts/stops workers (clipboard pasteboard poller, snippet expander, dispatch server). Daemon startup gates worker startup on `activationState == .enabled`.
**Tests:** Two-process test (parent main app + child daemon) asserts the daemon sees the notification and starts/stops a synthetic worker; daemon startup test with each pre-set state combination.
**Depends on:** Phase 04 (FeatureManager exists with notification posting from Phase 01).
**Unlocks:** None (independent leaf).

### Phase 11 — Migration
**File:** `2026-05-15-modular-features/11-migration.md`
**Outputs:** `Migrator` runs once on first launch after upgrade (sentinel `migratedToFeatureModel: Bool` in `AppGroupSettings`), Sparkle pre-install bash script in `Resources/`, build-time integration of the script with Sparkle's installer, `WhatsNewSheetView`, prior-usage detection (clipboard records / download records / voice settings / folder preview recently invoked).
**Tests:** Table-driven migration tests over the matrix from § 7.2; pre-install script tested by simulating a "fake old bundle" + running the script + asserting `Features/downloader/<version>/` is populated.
**Depends on:** Phase 06, Phase 09.
**Unlocks:** Phase 12.

### Phase 12 — Cleanup & polish
**File:** `2026-05-15-modular-features/12-cleanup.md`
**Outputs:** Remove Sync tab + `SyncSettingsView` (deferred-indefinitely subsystem), add Advanced tab actions ("Re-run onboarding…", "Open feature install directory in Finder", "Install pack from file…", "Reset all features…"), final copy pass through user-facing strings, manual QA matrix run.
**Tests:** Smoke test the four Advanced actions; QA matrix is manual.
**Depends on:** Phase 11.
**Unlocks:** Ships.

## Execution checklist

Use this top-level checklist to track plan completion. Each row's detail lives in its phase plan.

- [ ] Phase 01 — Foundation
- [ ] Phase 02 — Pack infrastructure
- [ ] Phase 03 — Feature activators
- [ ] Phase 04 — Registry-driven bootstrap
- [ ] Phase 05 — Features tab UI
- [ ] Phase 06 — Downloader pack
- [ ] Phase 07 — Voice asset caches
- [ ] Phase 08 — Folder Preview placeholder
- [ ] Phase 09 — Onboarding redesign
- [ ] Phase 10 — Daemon Darwin observation
- [ ] Phase 11 — Migration
- [ ] Phase 12 — Cleanup & polish

## Conventions across all phase plans

- **Branch & commit**: each phase = one feature branch off `main`; squash-merge into `main` when its phase plan's tests pass.
- **TDD**: every phase plan opens each task with the failing test, then the minimum code to pass. No exceptions.
- **Frequent commits**: each phase plan's tasks end with a `git commit`. Commit message format: `feat(modular-features): <task summary>`.
- **No placeholders**: each step contains the actual code/command/expected output. If a step references a type/method, that type/method is defined in an earlier task in the same or a dependency phase.
- **Test command**: `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter <name>` for Shared package tests; `xcodebuild test -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -destination 'platform=macOS,arch=arm64' -only-testing:<target>/<class>/<method>` for Xcode tests.
- **Build verification**: each phase ends with `./scripts/ci-build.sh` succeeding (full build + lint + tests).
