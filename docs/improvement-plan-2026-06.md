# Mac All You Need — Codebase Improvement Plan

**Date:** 2026-06-11
**Author:** Audit pass (static analysis + clean Debug build + targeted call-graph verification)
**Scope:** All first-party code. Excluded: `reference-projects/`, `build/`, `.build/`, `dist/`, `Vendored/`, FluidAudio vendored checkout.

---

## How to read this plan

Every finding carries a **confidence tag**. The audit originally ran via scoped subagents (each searching only its slice), which produced at least one significant false positive — a "dead SmartText cluster" that is actually **live** via the daemon. The tags below reflect what has since been re-checked.

| Tag | Meaning |
|-----|---------|
| ✅ **Verified** | Re-checked against the full tree (app + Shared + daemon + extensions) or grounded in code that literally exists (e.g. a force-unwrap). Safe to act on. |
| ⚠️ **Needs verification** | Plausible but derived from a scoped search or static reading only. Confirm in Phase 0 before acting. |
| 📊 **Needs measurement** | A performance *risk*, not a measured fact. Profile before optimizing. |

**Critical correction (already applied to this plan):** `SmartTextService`, `CaptureDecision`/`SmartCapturePolicy`, and `SensitiveContentFilter` are **LIVE** (called from `ClipboardDaemon/DaemonContainer.swift:81`). They must **not** be deleted. The earlier "dead cluster" claim was wrong because that subagent's search was scoped to `Shared/Sources/` and missed the daemon caller.

---

## Phase 0 — Verification (do this FIRST)

Converts the rest of the plan from "static guess" to "evidence." Nothing below Phase 0 should be *deleted* until Phase 0.1 confirms it; nothing should be *optimized* until Phase 0.3 measures it.

| ID | Task | Why |
|----|------|-----|
| V1 | Re-grep every "no caller" claim against the **full tree** (already done for the items tagged ✅ below). For any remaining ⚠️ dead-code item, confirm zero non-test references across `MacAllYouNeed/ Shared/ ClipboardDaemon/ FolderPreview/ FinderHistoryExtension/ RemindersWidget/ Tools/`. | The SmartText false positive proves scoped greps lie across target boundaries. |
| V2 | Run the suites: `cd Shared && PKG_CONFIG_PATH=… swift test` and `xcodebuild test -scheme MacAllYouNeed -destination 'platform=macOS,arch=arm64'`. Record pass/fail. | Static reading cannot prove features work. Not yet done. |
| V3 | Profile the heavy features with Instruments under realistic load: DockPreviews capture (Allocations + Time Profiler), Voice dictation HUD, clipboard polling. Capture peak memory, sustained CPU, disk I/O. | The user's literal ask ("great performance, no excessive memory/CPU/disk") requires measurement, not inspection. |

**Build baseline (measured):** Debug build succeeds, exit 0, **1 benign warning** ("No AppIntents.framework dependency"). App bundle **274 MB**, of which **185 MB is bundled tooling** (`ffmpeg` 150 MB + `yt-dlp` 35 MB); first-party Swift ≈ 53 MB.

---

## Phase 1 — Correctness & crash safety (CRITICAL)

### F1 — Semantic embedding ranking is unwired ✅
- **Evidence:** `ClipboardEnrichmentCoordinator` (`MacAllYouNeed/App/Coordinators/ClipboardEnrichmentCoordinator.swift:12`) is the only writer of `setEmbedding`/`setOCRText`, and has **0 non-test references** — it is never instantiated. The `.clipboardSmartText` worker path (`AppFeatureWorkerHost.swift:34`) starts only `ClipboardWorker`, which **reads** enrichment columns but never writes them.
- **Scope correction:** This is *narrow*. Text detection, calculator, link-clean, `copySmartText`, and `/type:` filtering all work (daemon computes them at capture). Image-OCR **search** works (daemon OCRs at capture → `search.upsert`). The **only** dead capability is embedding-based semantic ranking, plus the `ocr_text` *column* fallback in `DockItem.smartCopyValue`.
- **Decision required (pick one):**
  - **(a) Wire it on** — instantiate `ClipboardEnrichmentCoordinator` in `AppController`, gated on `clipboardSmartText` enabled + `SmartTextSettings.semanticEnabled()`, started/stopped with the clipboard worker. *Effort: M. Risk: med (adds a 30s background timer doing NLEmbedding + Vision work — pair with F7).*
  - **(b) Remove the illusion** — if semantic search is deferred, delete `ClipboardEnrichmentCoordinator`, `SmartTextRankBlend` (F8), the `setEmbedding`/`idsMissingEmbedding` column path, and hide the "semantic" Settings toggle so users can't enable a dead feature. *Effort: M. Risk: low.*
- **Recommendation:** Decide intent first. If "everything is supposed to work" → (a). Do not leave it half-wired.

### F2 — Force-unwrapped App Group container ✅
- **Evidence:** `FileOrganizer/FileOrganizerCoordinator.swift:18` — `containerURL(forSecurityApplicationGroupIdentifier:)!` crashes if the entitlement is missing; also hardcodes the group ID string.
- **Fix:** Use the canonical `AppGroup.containerURL()` and let the throwing init propagate. *Effort: S. Risk: low.*

### F3 — `as! AXUIElement` force-casts on untrusted AX values ✅
- **Evidence (7 sites):** `WindowControl/WindowKeyboardActionPerformer.swift:69`, `ActiveWindowBorderController.swift:69`, `WindowControlCoordinator.swift:387`, `WindowScrollResizeController.swift:16`, `WindowControlCoordinator+Radial.swift:241`, `FinderHistory/FolderHistoryFinderPathResolver.swift:25`, `FolderHistoryPanelPlacement.swift:70`.
- **Problem:** AX APIs return loosely-typed `CFTypeRef`; an unexpected type from an arbitrary app (Electron, odd window managers) hard-crashes the whole app.
- **Fix:** Replace each `as!` with `guard let … as? AXUIElement else { return … }`. Consider one shared helper `axElement(_:) -> AXUIElement?`. *Effort: S. Risk: low.*

---

## Phase 2 — Dead code & repo hygiene (zero/low risk)

Pure deletions; each verified to have no production use. Do **not** include the SmartText files here — they are live.

| ID | Item | Status | Action |
|----|------|--------|--------|
| F8 | `Shared/Sources/Core/SmartText/SmartTextRankBlend.swift` | ✅ 0 refs | Delete (or keep only if F1(a) chosen — it's the semantic-rank blend). |
| F9 | `Shared/Sources/Core/WindowControl/BSPAutoFlowSpike.swift` | ✅ 0 refs (self-labeled "feasibility spike") | Delete. |
| F10 | `SettingsRoot.featureTabs(registry:states:)` (`Settings/SettingsRoot.swift:10`) | ✅ 0 refs | Delete, or make it the canonical settings path (see F5). |
| F11 | `FeatureRuntime.deactivateAll()` (`App/FeatureRuntime.swift:44`) | ✅ no caller | Either call it from `applicationWillTerminate` (implements the documented graceful shutdown), or delete. Recommend wiring it — workers/event taps/dispatch server currently tear down only via process exit. |
| F12 | `scripts/import-typeless-history.py` | ✅ orphaned (Makefile + `.sh` use the Swift CLI) | Delete (12 KB duplicate importer that will rot). |
| F13 | Empty dirs: `MacAllYouNeed/{WindowSwitcher,DockLocking,CmdTabEnhancements,ActiveAppIndicator}`, `Shared/Sources/Platform/Audio` | ✅ 0 files | Remove (untracked; they imply features that don't exist). |

---

## Phase 3 — Modularity (the stated #1 goal: every feature self-contained)

### F14 — Descriptor contract is half-adopted ⚠️
- **Evidence:** `FeatureDescriptor` exposes `settingsTabFactory`/onboarding/menubar hooks, but live wiring bypasses them with hardcoded per-feature switches/arrays: `MainWindowRoot.detailView` (12-case switch, ~`:106`), `MainWindowDestinationRouter`, `SettingsDetailContent.detailView` (`SettingsRoot.swift:234`), `SettingsDestination` enum, `FeatureOnboardingWizardRegistry` (`:20`), and the `dashboardTiles` literal array (`FunctionDestinationRegistry.swift:87`). `SettingsRoot.featureTabs` (the registry-driven path) is dead (F10).
- **Impact:** Adding one feature touches ~7 files instead of one descriptor — the opposite of self-contained.
- **Fix (incremental):**
  1. Add `pageFactory` to `FeatureDescriptor`; convert `MainWindowRoot`/router switches to descriptor lookups.
  2. Make `SettingsDetailContent` consume `settingsTabFactory` (revive the dead path); delete the hardcoded switch.
  3. Move each onboarding wizard onto its descriptor; delete `FeatureOnboardingWizardRegistry`.
  4. Derive `dashboardTiles` (title/icon/accent/summary) from descriptors; delete the literal array + raw-RGB `accent(for:)`.
- *Effort: L. Risk: med. Highest long-term payoff; do it feature-by-feature behind tests.*

### F15 — `Clipboard/` is a half-finished stub ⚠️
- **Evidence:** `Clipboard/` (75 LOC) — `ClipboardFeatureActivator.activate()` only starts a `SnippetExpander` with a no-op lookup and comments that real ownership "stays in AppController until Phase 04." Real lifecycle lives in `AppController`; UI lives in `ClipboardDock/`.
- **Fix:** Finish Phase 04 (move `HotkeyController` + reader ownership into the feature) **or** fold `Clipboard/` into `ClipboardDock/` and delete the stub. *Effort: M. Risk: med.*

### F16 — `LLM/` is a Voice wrapper miscategorized as a feature ⚠️
- **Evidence:** `LLM/` (60 LOC) is built entirely on `VoiceLLMProvider`/`VoiceLLMRequest`/`VoicePromptBuilder`; its only template case is `.voiceCleanup`.
- **Fix:** Either move it under `Voice/`, or, if it's the seed of a generic LLM layer, invert the dependency and move the shared LLM primitives to `Shared/`. *Effort: M. Risk: low.*

### F17 — Voice-owned enum leaked into FileOrganizer ⚠️
- **Evidence:** `FileOrganizer/AIFileOrganizerSettings.swift:6` reuses `VoiceCleanupProviderKind` (owned by Voice).
- **Fix:** Move the provider-kind enum to `Shared/` so both features depend on shared, not on each other. *Effort: S. Risk: low.*

### F18 — Tools CLI scaffolding duplicated ✅
- **Evidence:** `Tools/TypelessImport/TypelessImportCLI.swift` and `Tools/VoiceTrainingExport/VoiceTrainingExportCLI.swift` independently reimplement the app-running guard, `--mayn-container` parsing + tilde expansion, and container validation.
- **Fix:** Extract a shared `MAYNToolHarness` (container resolution + running-app guard + arg helpers). *Effort: S. Risk: low.*

### F19 — ASR engines lack a shared protocol ⚠️
- **Evidence:** `Voice/ASR/{GroqASREngine,Qwen3Engine,VoiceLocalASREngine}.swift` each define `transcribe` independently; selection is by branching.
- **Fix:** Introduce `ASRProviding { func transcribe(...) }`; select polymorphically. *Effort: M. Risk: low.*

### F20 — (Note, not a defect) Clipboard-specific XPC in `Shared/Core/XPC/`
- Defensible because both daemon and app consume it. Leave as-is; documented here so it isn't "fixed" by mistake.

---

## Phase 4 — God-object decomposition (maintainability)

All sizes ✅ measured. Decompose behind existing tests; no behavior change.

| ID | File | LOC | Action |
|----|------|-----|--------|
| F21 | `Voice/VoiceCoordinator.swift` | 1488 | Extract `VoicePipelineController` (ASR+cleanup) and `VoiceHUDPresenter`. |
| F22 | `App/MainWindow/Destinations/VoiceDestinationView.swift` | 1533 (single `View` struct) | Split into `private struct` subviews like its peers (`ClipboardDestinationView`, `DownloadsSettingsView` already are). |
| F23 | `DockPreviews/DockPreviewCoordinator.swift` | 1093 (~50 props/methods) | Extract pointer/click-monitor lifecycle and merge/hydration into separate types. |
| F24 | `ClipboardDock/Window/DockWindowController.swift` | 988 | De-duplicate the two shortcut-dispatch paths (key handler `:451-678` vs `performDockShortcut` `:764-851`) into one table. |
| F25 | `App/AppControllerVoice.swift` | 494 / 54 methods | Move Voice settings read/write/test into a `VoiceSettingsService` the Voice views consume directly. |
| F26 | `App/.../FunctionDestinationRegistry.swift` | 515 | Folds into F14 (descriptor-driven); rename — it contains no registry. |

Other >600-LOC files (`DownloadCoordinator` 779, `WindowControlEventTap` 709, `DockHubSubsystemSettings` 874) are cohesive-by-domain — lower priority; split opportunistically.

---

## Phase 5 — Performance (📊 measure in Phase 0/V3 before optimizing)

| ID | Risk | Evidence | Proposed fix |
|----|------|----------|--------------|
| F27 | Always-on 400 ms pasteboard loop never suspends even when Downloader disabled | `AppController.startAutoDownloadPromptLoop()` `:623` | Gate the task on feature-enabled; coalesce with the 1 s `LocalClipboardReader` poll. |
| F28 | 0.15 s synchronous AX poll redrawing a border (6.7 Hz IPC) | `WindowControl/ActiveWindowBorderController.swift:36` | Drive off AX notifications (`AXObserverCoordinator` already exists) instead of polling. |
| F29 | Dock-badge timer never invalidates when idle | `Downloader/DockProgressController.swift:14` | Invalidate when no active downloads; restart on enqueue. |
| F30 | 40 Hz full-HUD republish during dictation, atop three 60fps `TimelineView`s | `VoiceCoordinator.swift:1137` | Feed amplitude via a single `@Published` value instead of rebuilding the HUD view each tick. |
| F31 | `keysByBlob` index grows unbounded (NSCache data is bounded, the index isn't) | `Platform/Image/ThumbnailCache.swift:6` | Prune the index on eviction (NSCache delegate) or cap it. |
| F32 | `WatchDaemon` re-lists the whole dir as "newFiles" (no diff) + double-applies 2 s debounce (~4 s latency) | `FileOrganizer/WatchDaemon.swift:56` | Diff against a prior snapshot; use the debounce once. |
| F33 | 60 Hz main-actor pointer re-arm + main-thread AX tree walks while a preview is open; synchronous main-actor disk reads in thumbnail hydrate | `DockPreviewCoordinator.swift:767`, `DockPreviewVisibleThumbnailCache.swift:81` | Confirm via Time Profiler; move disk reads off main; widen the AX poll throttle. |
| F34 | `ClipEmbeddingService.vector` reloads `NLEmbedding` per call | `Shared/Sources/Core/SmartText/ClipEmbeddingService.swift:26` | Cache the `NLEmbedding` instance per language. **Only relevant if F1(a) is chosen.** |
| F35 | App bundle 274 MB; 185 MB is `ffmpeg`+`yt-dlp` | measured | Distribution lever (thin/lazy-download tooling); not a code defect. Track for Plan 7. |

**Note:** Static review found **no retain cycles** in the hot paths, and DockPreviews capture/thumbnail memory is already bounded (4-stream cap, 16-entry LRU, disk prune). These are risks to *measure*, not confirmed regressions.

---

## Phase 6 — Documentation & build hygiene

| ID | Item | Status | Action |
|----|------|--------|--------|
| F36 | `CLAUDE.md`/`AGENTS.md`/`README.md` all say "seven first-class tool surfaces"; `FeatureID` has **11** (adds smartText, folderHistory, voiceReminders, aiFileOrganizer, **dockPreviews** — the largest feature) | ✅ | Update all three to the real 11. Document DockPreviews (currently 19k LOC with zero architectural docs). |
| F37 | `AGENTS.md` (311) and `CLAUDE.md` (310) are near-duplicate behavioral-guideline files | ✅ | Collapse to one canonical file; have the other reference it. |
| F38 | Stale invariant: code+`CLAUDE.md` say "AppController is a `static let`"; it's actually a per-delegate instance property (`MacAllYouNeedApp.swift:49`) | ✅ | Fix the doc/comment **and** verify the single-instance safety property didn't regress. |
| F39 | `MacAllYouNeed.xcodeproj/project.pbxproj` committed alongside `project.yml` (xcodegen source) — dual source of truth | ⚠️ | Decide: gitignore the generated `.pbxproj` (keep only the 2 hand-authored schemes) **or** drop xcodegen. Stop tracking both. |
| F40 | Parallel `docs/plans/` vs `docs/specs/feature-expansion-2026/` trees + ~40 shipped execution plans in `docs/` | ⚠️ | Move shipped/superseded docs to `docs/archive/`. |

---

## Suggested execution order

1. **Phase 0** (V1–V3) — verify + run tests + profile. Gate for everything else.
2. **Phase 1** (F2, F3) — crash-safety; mechanical, low-risk. Resolve **F1 decision** (wire vs remove).
3. **Phase 2** — dead-code deletions (zero-risk, immediate clarity win).
4. **Phase 6** — docs (cheap, high signal; fixes the "7 vs 11" confusion that misled this very audit).
5. **Phase 3** (F14 first) — modularity; the stated #1 goal. Feature-by-feature behind tests.
6. **Phase 4 / Phase 5** — decomposition and (measured) performance, opportunistically.

## Confidence summary

- ✅ Verified: F1, F2, F3, F8–F13, F18, F36–F38 (and the SmartText *liveness* correction).
- ⚠️ Verify in Phase 0: F14–F17, F19, F39, F40, and any other "no caller" claim.
- 📊 Measure in Phase 0/V3: all of Phase 5.
- **Not yet done:** test suites (V2) and profiling (V3) — until these run, no functional or performance claim in this plan is proven.
