# Voice Dictation Autopilot Execution Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development for implementation. This plan is the current-session execution wrapper over `2026-05-11-08-voice-master.md`; it does not replace the master plan.

**Goal:** Execute Plan 8 from spike through v1 ship gates without speculative shortcuts, using the design spec as the source of truth.

**Architecture:** Preserve the master plan dependency chain: Plan 8.0 produces empirical findings, Plan 8a freezes the production protocols and schema, Plans 8b/8c/8e run only after 8a, then 8d and 8f integrate downstream features. Work that touches shared project wiring, hotkeys, migrations, or `VoiceCoordinator` remains single-owner.

**Tech Stack:** Swift 5.9, SwiftUI/AppKit, AVAudioEngine, GRDB, XcodeGen, existing `./scripts/ci-build.sh`, plus model/provider dependencies only after the spike proves the integration path.

---

## Execution Rules

- Do not fake spike results. Gates that require physical interaction, model download, Instruments, or external app paste testing must be reported as manual-pending unless actually performed.
- Do not start Plan 8a production code until Plan 8.0 has a findings document with a real ASR backend decision, hotkey recommendation, paste caveats, and latency baseline.
- Plan 8a is the only owner of voice-related `ClipboardStore.migrations` changes.
- Do not edit unrelated dirty files or revert existing changes.
- Run `xcodegen generate` after adding Swift files/resources that must enter the Xcode project.
- Use `xcodebuild ... -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO` for targeted app verification and `./scripts/ci-build.sh` for broader verification when the local tree is buildable.

## Current-Session Sequence

### Task 1: Plan 8.0 Spike Implementation

**Files:**
- Modify/Create: `MacAllYouNeed/VoiceSpike/**`
- Modify/Create: `MacAllYouNeedTests/VoiceSpike/**`
- Modify: `MacAllYouNeed/Settings/SettingsRoot.swift`
- Modify: `MacAllYouNeed/Info.plist`
- Modify: `project.yml` only if the ASR dependency is compiled into the spike
- Create: `docs/superpowers/findings/2026-05-11-voice-spike-findings.md` only with real evidence

**Verification:**
- `xcodegen generate`
- Targeted `xcodebuild test` for launch-arg/scaffolding tests
- Targeted `xcodebuild build` for app compile
- Manual gates remain unchecked until physically exercised:
  - Mic capture with non-zero level
  - Fn/Globe press/release
  - Real local ASR transcript
  - Paste into TextEdit, Notes, and one Electron app
  - Instruments signposts visible

### Task 2: Plan 8a Plan Writing

**Input required:** completed Plan 8.0 findings.

**Output:** `docs/superpowers/plans/2026-05-11-08-a-voice-mvp.md`

**Must include:**
- Production `TranscriptionEngine` and result model contracts based on the validated backend.
- Production hotkey fallback if Fn/Globe is unreliable.
- Audio capture, Mini HUD, paste path, minimal Settings entry, storage schema migration, and tests.
- Explicit migration ownership for all v1 voice tables/columns listed in the master plan.

### Task 3: Plan 8a Implementation

**Hard gate:** starts only after Task 2 plan exists and Plan 8.0 findings are real.

**Verification:**
- Shared unit tests for pure Voice models/algorithms.
- Xcode tests for production wiring where possible.
- App build.
- Manual record -> transcribe -> paste smoke in at least TextEdit.

### Task 4: Plans 8b, 8c, and 8e Plan Writing + Implementation

**Input required:** Plan 8a protocols and schema landed.

**Parallel-safe only if write sets are disjoint:**
- 8b owns onboarding/settings UI files.
- 8c owns cleanup/provider/dictionary files.
- 8e owns app profile/power mode files.

**Forbidden in these plans:** adding new `ClipboardStore.migrations` entries.

### Task 5: Plan 8d Plan Writing + Implementation

**Input required:** Plan 8a engine protocol and model catalog decisions.

**Internal parallelism:** individual engine wrappers may run in parallel only after `ModelManager` and catalog contracts are stable.

### Task 6: Plan 8f Plan Writing + Implementation

**Input required:** Plans 8b/8c/8d/8e integrated.

**Single-owner work:** selection AI, streaming integration, translation, ClipboardBridge, TrainingExporter, final manual QA checklist.

### Task 7: Final Spec Verification

**Checks:**
- All master-plan acceptance criteria have evidence or are explicitly marked manual-pending with reason.
- `./scripts/ci-build.sh` passes on the working tree or failures are proven unrelated/pre-existing.
- Spec is updated for any implementation divergence.
- Final review confirms no unrelated file churn.
