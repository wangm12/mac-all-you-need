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

| Wave | Phases that run concurrently | Concurrency | Why |
|---|---|---:|---|
| 1 | **01** alone | 1 | Foundation types + `FeatureManager`; everything else depends on it. |
| 2 | **02** ∥ **03** | 5 | 02 is one agent. 03 fans out to **four** parallel sub-agents (one per feature) once the Phase 03 shared scaffold (Task 1) lands. |
| 3 | **04** alone | 1 | Integrates 02 + 03 into the registry-driven bootstrap. |
| 4 | **05** alone | 1 | Builds the Features tab UI. |
| 5 | **06** ∥ **07** ∥ **08** ∥ **10** | 4 | All four depend on 05 (or earlier) and touch disjoint primary code paths. |
| 6 | **09** alone | 1 | Reuses card UI from 05 and pack download from 06. |
| 7 | **11** alone | 1 | Depends on final disk layout (06) and onboarding decision tree (09). |
| 8 | **12** alone | 1 | Final cleanup; touches many surfaces. |

**Peak concurrency:** Wave 2 (5 agents) and Wave 5 (4 agents).

---

## Sub-Agent Orchestration Guide

This section is the playbook for an orchestrator (human or top-level Claude) coordinating parallel sub-agents across phases. **Read this before kicking off any wave.**

### Pre-flight (one-time, before Wave 1)

- [ ] Confirm you're on a clean `main` (no uncommitted changes outside this initiative).
- [ ] Confirm the spec exists at `docs/superpowers/specs/2026-05-15-modular-features-design.md`.
- [ ] Confirm all 12 phase plans exist in `docs/superpowers/plans/2026-05-15-modular-features/`.
- [ ] Verify the build environment: `./scripts/ci-build.sh` passes on current `main`.
- [ ] Create a tracking branch for the whole initiative if you want one umbrella PR series: `git checkout -b modular-features/init`. Each phase still gets its own branch off this.
- [ ] Decide which sub-skill each phase's agents use:
  - **Within a phase**: agents use `superpowers:subagent-driven-development` (one fresh sub-agent per task, review between tasks). This is the recommended default.
  - **Alternative for short phases**: `superpowers:executing-plans` (single agent works the whole phase inline with checkpoints).

### Conflict points (read before dispatching parallel agents)

Parallel phases sometimes touch the **same shared file**. These are real merge-conflict risks. Resolution strategies are noted per file:

| File | Touched by | Resolution |
|---|---|---|
| `MacAllYouNeed/App/FeatureRegistryProvider.swift` | Phase 03 (×4 sub-agents), Phase 06, 07, 08 | **Pre-split before fan-out.** Within Phase 03 Task 1, split the file into `FeatureRegistryProvider.swift` (composition root, 10 lines) + `<Feature>Descriptor.swift` per feature. Each parallel sub-agent then owns its own file. Later phases (06/07/08) modify their feature's descriptor file only. |
| `MacAllYouNeed/Settings/Features/FeaturesTabView.swift` | Phase 06, Phase 07 | Have Phase 06 land first; Phase 07 rebases. The handler change in 06 is structural (install/cancel/retry wiring); 07's change is small (uninstall opt-in cache deletion). Phase 06's first PR review should be quick. |
| `MacAllYouNeed/App/AppController.swift` | Phase 06 (PackInstallController wiring), Phase 07 (orphan scanner init) | Same as above: 06 first, 07 rebases. Both edits are in the bootstrap section; rebase conflict is trivial. |
| `Shared/Sources/FeatureCore/FeatureStateReader.swift` | Phase 08, Phase 10 | **First-to-land wins.** Whichever phase lands first creates the file. The second phase's "Task: add FeatureStateReader if not present" must check `git ls-files` and skip when present. Both phase plans already document this. |
| `MacAllYouNeed/Settings/Features/FeatureCardView.swift` | Phase 05 (creates), Phase 08 (adds OS-extension badge) | Phase 05 lands first by definition; Phase 08 modification is additive (a new info badge). No real conflict. |
| `project.yml` | Phase 01, 02, 04, 08 | Each adds entries to different targets' `dependencies:`. Conflicts are textual but trivial; rebase resolves. |

**Conflict-resolution policy across the board**:
1. Land the first-to-finish parallel sub-agent's PR.
2. For each subsequent sub-agent in the same wave, rebase its branch on the merged `main` and re-run tests + CI.
3. If a rebase produces a non-trivial conflict (more than reordering imports / merging adjacent lines), pause and resolve in a fresh sub-agent dispatch with a focused "resolve rebase conflict" prompt.

### Wave-by-wave playbook

#### Wave 1 — Phase 01 (foundation)

**Dispatch**: 1 sub-agent.
- Prompt template: see "Standard Dispatch Prompt" below; fill in `<phase-id>=01`, `<phase-file>=01-foundation.md`, dependencies=`(none)`.
- Sub-skill: `superpowers:subagent-driven-development`.

**Verification gate before Wave 2**:
- [ ] Phase 01's PR merged to `main`.
- [ ] `cd Shared && PKG_CONFIG_PATH=... swift test --filter FeatureCore` passes.
- [ ] `FeatureCore` library exports `FeatureID`, `AssetState`, `ActivationState`, `FeatureRuntimeState`, `FeatureDescriptor`, `FeatureRegistry`, `FeatureActivator`, `FeatureManager`, `FeaturePackManifest`, `AssetPack`, `AssetCacheDescriptor`, `DarwinNotification`.
- [ ] Xcode project regenerated; `xcodebuild build` passes.

#### Wave 2 — Phase 02 ∥ Phase 03 (5 concurrent agents)

This is the largest fan-out. Phase 03's Task 1 (the shared `FeatureRegistryProvider` scaffold) **must land first** before the four activator sub-agents fan out — otherwise they collide on the same file.

**Recommended order within Wave 2**:

1. **Phase 03 Task 1 only** (1 agent): land the `FeatureRegistryProvider.swift` scaffold + the per-descriptor file split (see Conflict Points table). Merge to `main`.
2. Then dispatch in parallel (5 agents simultaneously):
   - **Phase 02** (full phase): one agent runs Tasks 1–13 of `02-pack-infrastructure.md`.
   - **Phase 03 Task 2** (Clipboard activator sub-agent): owner of `MacAllYouNeed/Clipboard/` files + `ClipboardDescriptor.swift`.
   - **Phase 03 Task 3** (Folder Preview activator sub-agent): owner of `MacAllYouNeed/FolderPreview/` files + `FolderPreviewDescriptor.swift`.
   - **Phase 03 Task 4** (Downloader activator sub-agent): owner of `MacAllYouNeed/Downloader/` files + `DownloaderDescriptor.swift`.
   - **Phase 03 Task 5** (Voice activator sub-agent): owner of `MacAllYouNeed/Voice/` files + `VoiceDescriptor.swift`.
3. After all 5 finish, run **Phase 03 Task 6** (phase verification) as a single follow-up agent (combines all four activator PRs into a final integration check).

**Dispatch prompt** for each Phase 03 sub-agent: see "Standard Dispatch Prompt" below; specify which task numbers the sub-agent owns (e.g., "Task 2 only").

**Verification gate before Wave 3**:
- [ ] Phase 02 PR merged. `swift test --filter PackPipeline` passes.
- [ ] All four Phase 03 sub-task PRs merged. Each activator's tests pass.
- [ ] `FeatureRegistryProvider.makeRegistry()` returns 4 descriptors with real activators (no `NoopFeatureActivator` leftovers).
- [ ] App still launches and behaves identically (AppController hasn't changed bootstrap yet — that's Wave 3).

#### Wave 3 — Phase 04 (registry-driven bootstrap)

**Dispatch**: 1 sub-agent. Not parallelizable — it's the integration point.

**Verification gate before Wave 4**:
- [ ] All features still work after launch.
- [ ] Disable a feature via direct `defaults write` to `AppGroupSettings` → relaunch → that feature is inactive (no hotkey, no menu item, no permission prompt).
- [ ] Re-enable via `defaults write` → relaunch → it's active.

#### Wave 4 — Phase 05 (Features tab UI)

**Dispatch**: 1 sub-agent.

**Verification gate before Wave 5**:
- [ ] Settings → Features tab shows 4 cards.
- [ ] Toggle Enable/Disable on a card; feature activates/deactivates without restart.
- [ ] Uninstall sheet renders (caches list will be empty for now — Phase 07 fills Voice caches).

#### Wave 5 — Phase 06 ∥ Phase 07 ∥ Phase 08 ∥ Phase 10 (4 concurrent agents)

**Recommended merge order to minimize rebase pain**:

1. **Phase 10 first** (least likely to conflict — daemon code is mostly isolated): dispatch alone or in parallel with 08.
2. **Phase 08** (isolated extension target + small `FeatureCardView` badge): parallel with 10.
3. **Phase 06** (shared `FeaturesTabView` + `AppController` edits): land third; rebase if needed.
4. **Phase 07** (shared `FeaturesTabView` + `AppController` edits): land last; rebase on 06's changes.

**FeatureStateReader race**: Phase 08 and Phase 10 both create `Shared/Sources/FeatureCore/FeatureStateReader.swift`. Whichever lands first creates it; the second checks `git ls-files docs/.../FeatureStateReader.swift` at the start of its relevant task and skips creation if present. Both phase plans document this guard.

**Dispatch all 4 in parallel** if you accept the rebase cost (best wall-clock time). **Or dispatch 10 + 08 first, then 06 + 07** if you want fewer rebases (saves human review time).

**Verification gate before Wave 6**:
- [ ] Phase 06: clicking Install on Downloader downloads a real pack and activates it.
- [ ] Phase 07: Voice card's Uninstall sheet shows the two Qwen3 cache rows when present.
- [ ] Phase 08: toggling Folder Preview off → Quick Look shows placeholder.
- [ ] Phase 10: toggling Clipboard off → daemon pasteboard poller stops (verify via Console.app or daemon log).

#### Wave 6 — Phase 09 (onboarding redesign)

**Dispatch**: 1 sub-agent.

**Verification gate before Wave 7**:
- [ ] Wipe `AppGroupSettings` to simulate first launch → onboarding shows new wizard.
- [ ] Pick Downloader → download progress runs → permission prompts only for declared permissions → Done.
- [ ] "Skip for now" exits with zero features enabled; app still launches.

#### Wave 7 — Phase 11 (migration)

**Dispatch**: 1 sub-agent.

**Verification gate before Wave 8**:
- [ ] Simulate existing-user state (write fake clipboard records / download records to App Group DB) → launch new build → migration runs once → "What's new" sheet appears → all features end up in expected state.
- [ ] Sentinel persists across relaunches; migration doesn't re-run.
- [ ] Sparkle pre-install script tested in isolation (script harness test passes).

#### Wave 8 — Phase 12 (cleanup & polish)

**Dispatch**: 1 sub-agent.

**Final gate**:
- [ ] All 12 phases checked off in this index plan.
- [ ] Manual QA matrix from spec § 11 walked through and recorded.
- [ ] Initiative marked complete in CLAUDE.md "Plans Status".

### Standard dispatch prompt template

Use this template when dispatching any per-phase sub-agent. Fill in the bracketed placeholders.

```
You are implementing one phase of the modular-features initiative for the
Mac All You Need (MAYN) macOS app. Your scope is strictly limited to the
tasks listed in your phase plan file.

## Your phase

- Phase ID: <phase-id>            e.g. "Phase 02" or "Phase 03 Task 4 (Downloader sub-task)"
- Plan file (read in full first): docs/superpowers/plans/2026-05-15-modular-features/<phase-file>.md
- Specific tasks to execute: <task-range>     e.g. "all tasks" or "Task 4 only"

## Context to read before starting

1. The design spec — the section relevant to your phase:
   docs/superpowers/specs/2026-05-15-modular-features-design.md
   (Your phase plan's "Goal" + "Depends on" sections tell you which spec § matters.)

2. The index plan — for the dependency graph and conventions:
   docs/superpowers/plans/2026-05-15-modular-features.md

3. The plan files of every phase listed in your "Depends on":
   <list-dependency-files>     e.g. "01-foundation.md, 02-pack-infrastructure.md"

4. The repo's CLAUDE.md for project context:
   /Users/mingjie.wang/Documents/personal/mac-all-you-need/CLAUDE.md
   and MacAllYouNeed/CLAUDE.md (UI-scoped rules).

## How to execute

Use the `superpowers:subagent-driven-development` skill. For each task in
your scope:
- Read the task's "Files" block to know what you'll touch.
- Walk through every checkbox step in order.
- Honor the TDD shape: failing test → confirm it fails → implement →
  confirm it passes → commit.
- Every commit message: `feat(modular-features): <task summary>`.
- Do NOT skip the "expected output" assertion on any step.

## Branch

Create a branch: `modular-features/phase-<phase-id-slug>` off current `main`.
Example: `modular-features/phase-02` or `modular-features/phase-03-downloader`.

## Conflict awareness

These files are shared with other parallel phases — coordinate via rebase:
<list-from-conflict-points-table>

If you find one of those files already modified by a parallel branch when
you go to commit, STOP and report. Do not force-push. Do not silently
overwrite.

## Done criteria

- All checkboxes in your task scope ticked off.
- `./scripts/ci-build.sh` passes.
- The phase's "Phase verification" final task completed (tests + manual
  smoke if applicable).
- A PR opened with title `Phase <N> — <name>` and the body pointing at
  the plan file path.

## Out of scope

Anything not in your task scope. If you discover something that "should
be done" outside your scope, add a TODO comment with a phase reference
(e.g., `// Phase 11 will handle this`) — do not implement it yourself.

## Output

When done, report: branch name, PR URL, list of commits, and whether
all verification steps passed. If anything failed, report what and why.
```

### Failure recovery

When a sub-agent reports failure:

1. **Read the failure output carefully** before re-dispatching. Common causes:
   - **Test environment mismatch** (e.g., missing `PKG_CONFIG_PATH`): fix the env, re-dispatch the same task.
   - **Dependency not landed**: a "Depends on" phase didn't fully merge. Wait for it. Don't proceed.
   - **Conflict point hit**: another parallel branch modified a shared file. Rebase the failing branch on the now-updated `main`, re-run tests, re-dispatch only if tests still fail after rebase.
   - **Plan defect**: the plan step is wrong (e.g., a referenced symbol doesn't exist). This means the plan needs amending — the orchestrator (you) edits the phase plan file, commits the amendment, and re-dispatches with a note about the change.
2. **Never** "force" past a failure by skipping the failing step. The TDD shape exists so a green commit is always a known-good state.
3. **Re-dispatch with a delta prompt**, not a fresh prompt: include the original prompt + a `## Previous attempt failure` block describing what went wrong and what you've fixed.

### Status tracking

The execution checklist below is the source of truth for orchestrator progress. Each phase's final task updates this index. The orchestrator should additionally maintain:

- A scratch doc (e.g., `docs/superpowers/plans/2026-05-15-modular-features-execution-log.md`, optional) recording: which sub-agent ran which phase, when, the PR URL, any rebases, and any plan amendments.

### Plan amendments required before kickoff

Two known plan defects that the orchestrator should patch into the affected phase plan files **before dispatching** the relevant agents:

1. **Phase 03 Task 1 must pre-split `FeatureRegistryProvider.swift`.** As written, Tasks 2–5 each modify a different descriptor function inside the same file; in parallel sub-agents this produces guaranteed merge conflicts. The fix: amend `03-activators.md` Task 1 to split the file into:
   - `MacAllYouNeed/App/FeatureRegistryProvider.swift` — the 10-line composition root (`makeRegistry()` calling each `<Feature>Descriptor.descriptor()`).
   - `MacAllYouNeed/App/Descriptors/ClipboardDescriptor.swift`
   - `MacAllYouNeed/App/Descriptors/FolderPreviewDescriptor.swift`
   - `MacAllYouNeed/App/Descriptors/DownloaderDescriptor.swift`
   - `MacAllYouNeed/App/Descriptors/VoiceDescriptor.swift`
   - Each per-feature descriptor file exposes `enum ClipboardDescriptor { static func descriptor() -> FeatureDescriptor }` etc.
   Then Tasks 2–5 each own one descriptor file plus their activator file. Zero shared-file conflicts.

2. **Phase 08 + Phase 10 `FeatureStateReader` guard.** Both plans add the same file. Whichever phase's branch is rebased second must skip the "Add `FeatureStateReader`" task if `git ls-files Shared/Sources/FeatureCore/FeatureStateReader.swift` returns non-empty. Both phase plans note this; the orchestrator should confirm the second-merged agent honors it during code review.

The orchestrator should commit these amendments to the phase plans before Wave 2 kicks off so the plans-as-executed match reality.

This is optional but recommended for a 12-phase initiative.

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
