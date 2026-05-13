# Voice Dictation — Master Plan (Plan 8)

> **For agentic workers:** This is the orchestration / master plan. Detailed task breakdowns live in `2026-05-11-08-<sub-plan>.md` files. To implement an individual sub-plan, use superpowers:subagent-driven-development on that sub-plan's file.

**Goal:** Coordinate the delivery of the Voice Dictation subsystem (Typeless-grade local-first dictation with zh+en code-switching) across 7 sequenced sub-plans (1 spike + 6 implementation phases) by defining dependencies, parallelization strategy, integration checkpoints, and verification gates.

**Architecture:** Approach 1 from the design spec — integrated module under `MacAllYouNeed/Voice/` plus shared algorithms/protocols under `Shared/Sources/Voice/`. No XPC. Reuses existing AppController, GRDB stack (clipboard.sqlite + search.sqlite), HotkeyRegistry, EncryptionService, and Settings/Onboarding infrastructure.

**Tech Stack:** Swift 5.9+ · SwiftUI + AppKit · GRDB · AVAudioEngine · MLX-swift (Qwen3) · WhisperKit · FluidAudio (Parakeet + Silero VAD) · sherpa-onnx (SenseVoice) · KeyboardShortcuts · SelectedTextKit · Anthropic / OpenAI-compat HTTP

**Source spec:** [`docs/superpowers/specs/2026-05-11-voice-dictation-design.md`](../specs/2026-05-11-voice-dictation-design.md)

---

## 1. Sub-Plan Map

7 plans total — **1 spike + 6 implementation**. Numbering matches the spec's Section 10.

| ID | File | Title | LOC est. | Status |
|---|---|---|---|---|
| **8.0** | `2026-05-11-08-0-voice-spike.md` | Technical spike — derisk 5 hard unknowns | ~300 | **Detailed (ready to execute)** |
| **8a** | `2026-05-11-08-a-voice-mvp.md` | Voice MVP — capture + 1 ASR + Mini HUD + paste | ~1500 | Stub (write after 8.0 lands) |
| **8b** | `2026-05-11-08-b-voice-onboarding.md` | 8-step onboarding wizard + Settings tab shell | ~1500 | Stub |
| **8c** | `2026-05-11-08-c-voice-cleanup.md` | Cleanup pipeline + LLM providers + dictionary | ~1200 | Stub |
| **8d** | `2026-05-11-08-d-voice-multi-engine.md` | Multi-engine ASR + ModelManager + Notch HUD | ~1500 | Stub |
| **8e** | `2026-05-11-08-e-voice-power-mode.md` | Per-app PowerMode + AppProfileStore + AutoSendKey | ~700 | Stub |
| **8f** | `2026-05-11-08-f-voice-advanced.md` | AI-on-selection + streaming + translation + ClipboardBridge + TrainingExporter | ~700 | Stub |

**Total estimated:** ~7000 LOC (excludes spike).

**Why detailed plans for 8a-8f wait:** Plan 8.0 spike outputs (chosen ASR backend, real latency numbers, paste-injection caveats per app) directly shape 8a-8f's implementation. Writing them in detail before the spike would lock in assumptions that the spike exists to validate. **8a's detailed plan is written in the same session that closes Plan 8.0**, by re-invoking the writing-plans skill with the spike's findings file as input.

---

## 2. Dependency Graph

```
                     ┌────────────────────────────────┐
                     │   8.0 Spike (gates everything) │
                     └────────────────┬───────────────┘
                                      │ produces: spike-findings.md
                                      │           (chosen backend, real latencies,
                                      │            paste caveats, codesign config)
                                      ▼
                     ┌────────────────────────────────┐
                     │   8a Voice MVP                 │
                     │   (defines TranscriptionEngine │
                     │    protocol + LLMProvider      │
                     │    protocol + AppProfile type) │
                     └────────────────┬───────────────┘
                                      │ exports: protocols + minimal Coordinator
                                      ▼
              ┌───────────────────────┼───────────────────────┐
              │                       │                       │
              ▼                       ▼                       ▼
      ┌──────────────┐        ┌──────────────┐        ┌──────────────┐
      │ 8b Onboarding│        │ 8c Cleanup   │        │ 8e Power Mode│
      │ (Settings UI │        │ (LLM         │        │ (per-app     │
      │  + 8 steps)  │        │  providers + │        │  profiles)   │
      │              │        │  dictionary) │        │              │
      └──────┬───────┘        └──────┬───────┘        └──────┬───────┘
             │                       │                       │
             └───────────────────────┼───────────────────────┘
                                     │ all 3 ship
                                     ▼
                     ┌────────────────────────────────┐
                     │   8d Multi-engine ASR          │
                     │   (4 more engines + ModelMgr   │
                     │    + Notch HUD)                │
                     └────────────────┬───────────────┘
                                      │ exports: engine catalog
                                      ▼
                     ┌────────────────────────────────┐
                     │   8f Advanced features         │
                     │   (selection + streaming +     │
                     │    translation + bridge +      │
                     │    training export)            │
                     └────────────────────────────────┘
```

**Critical path:** 8.0 → 8a → (8b ∥ 8c ∥ 8e) → 8d → 8f
**Parallel-eligible waves:** Wave 2 (8b, 8c, 8e). Within waves, additional intra-plan parallelization (Section 3).

---

## 3. Parallelization Strategy

The user explicitly asked which work can be multi-threaded / done by sub-agents in parallel. Two layers:

### 3.1 Inter-plan parallelism (master-plan level)

| Wave | Plans | Why parallelizable | Sub-agents needed |
|---|---|---|---|
| 0 | **8.0** | Sequential — gates everything | 1 (spike work is investigative, not splittable) |
| 1 | **8a** | Defines protocols other plans consume | 1 (single coherent module that defines public API) |
| 2 | **8b ∥ 8c ∥ 8e** | Once 8a's protocols freeze, these touch disjoint files | **3 sub-agents in parallel** |
| 3 | **8d** | Touches ASR layer with engines defined by 8a's protocol | 1 (but 4 engines can parallelize internally — see 3.2) |
| 4 | **8f** | Integrates streaming + selection + translation | 1 (high integration risk, single-threaded for safety) |

**Wave 2 dispatch (in master orchestration session, after 8a lands):**
```
Agent: "Implement Plan 8b (Onboarding) per docs/.../2026-05-11-08-b-voice-onboarding.md"
Agent: "Implement Plan 8c (Cleanup) per docs/.../2026-05-11-08-c-voice-cleanup.md"
Agent: "Implement Plan 8e (Power Mode) per docs/.../2026-05-11-08-e-voice-power-mode.md"
```
All three dispatched in a single message with multiple Agent tool calls (per parent-agent doc on parallelism). Each uses `isolation: "worktree"` so they don't collide on `project.yml` or schema migrations.

**Wave-2 merge gate:** After all three return, run cross-integration test suite (Section 5.3) before proceeding to Wave 3.

### 3.2 Intra-plan parallelism (within a single sub-plan)

The biggest opportunity is **Plan 8d** — 4 ASR engines, each implementing the same `TranscriptionEngine` protocol from disjoint files:

```
Plan 8d internal parallelism:
  Wave 3a (sequential): ModelManager + ModelCatalog + LanguageDetector + Notch HUD
  Wave 3b (parallel — 4 sub-agents):
    Agent: SenseVoiceEngine (sherpa-onnx wrapper)
    Agent: ParakeetEngine (FluidAudio wrapper)
    Agent: WhisperEngine (WhisperKit wrapper)
    Agent: SonioxEngine (URLSessionWebSocketTask)
  Wave 3c (sequential): integration tests + Settings model picker UI
```

Similarly **Plan 8c** — 3 LLM providers can parallelize (Anthropic / OpenAI-compat / Ollama). And **Plan 8b** — 8 onboarding steps can parallelize once shared design system is defined.

**Each sub-plan's detailed plan must explicitly mark task groups as `parallel-safe: true|false`** so the subagent-driven-development skill can dispatch them in parallel batches.

### 3.3 What is NOT parallelizable

- Anything that modifies `project.yml` (xcodegen lock conflicts).
- **Schema migrations on `clipboard.sqlite` (single-owner: Plan 8a).** Multiple parallel sub-plans cannot each append entries to `ClipboardStore.migrations` because the migration sequence number is monotonic and shared. **Plan 8a is the designated schema migration owner**: its scope is expanded to land *all* voice-related table creates and column adds in a single migration entry, even tables not used by 8a's runtime code (e.g. `voice_dictionary` used by 8c, `app_profiles` used by 8e). Plans 8b, 8c, 8e depend on the schema being already-present and only do CRUD against it. This rule is enforced by review gate (PR cannot land if it adds a `migrations` entry from a non-8a sub-plan).
- Anything that registers a hotkey (HotkeyRegistry global state).
- The `VoiceCoordinator` state machine (single owner per design).
- Final integration in Plan 8f (intentionally single-threaded).

The master plan enforces serialization for these by sequencing them within a single sub-plan rather than splitting across parallel sub-agents.

**Schema migration owner contract (Plan 8a):**

| Table / column | First runtime use | But created in Plan 8a |
|---|---|---|
| `voice_transcripts` | 8a | ✅ |
| `audio_archives` | 8a | ✅ |
| `voice_dictionary` | 8c | ✅ (created empty) |
| `app_profiles` | 8e | ✅ (created empty) |
| `clipboard_records.capture_origin` | 8f (when ClipboardBridge writes) | ✅ |
| `clipboard_records.voice_transcript_id` | 8f | ✅ |
| `idx_clipboard_records_capture_origin` | 8f | ✅ |

---

## 4. Cross-cutting Verification Strategy

### 4.1 Per-task verification (TDD enforced)

Every implementation task in every sub-plan follows red → green → commit:
1. Write failing test
2. Run test, confirm failure with expected error
3. Write minimal implementation
4. Run test, confirm pass
5. Commit (one commit per task, or per coherent task cluster)

The writing-plans skill enforces this structure for all sub-plans.

### 4.2 Per-sub-plan acceptance gates

Each sub-plan ends with explicit acceptance criteria. Examples:
- **8.0 Spike:** 5 named gates pass (mic/codesign, hotkey/PTT, ASR backend, paste, benchmark instrumentation) — see spec Section 10.
- **8a MVP:** end-to-end record → ASR → cleaned → paste round-trip works in TextEdit + one Electron app, with HUD visible.
- **8b Onboarding:** all 8 steps reachable, model download completes, resume-on-quit works.
- **8c Cleanup:** filler removal + LLM cleanup with one provider passes Chinese-English mixed phrase suite.
- **8d Multi-engine:** all 4 additional engines pass smoke test on the same fixture audio.
- **8e Power Mode:** per-app profile switches ASR + prompt automatically when frontmost app changes.
- **8f Advanced:** selection AI works in Notes, translation works for one language pair, training export produces a loadable .jsonl.

Sub-plan acceptance gates are themselves CI tests (where possible) so closure is demonstrable, not asserted.

### 4.3 Wave checkpoint reviews

After each wave closes:
- Run cross-integration tests (Section 5.3).
- Run `./scripts/ci-build.sh` (existing).
- Re-run all `Shared/Tests/VoiceTests/` and `MacAllYouNeedTests/Voice/`.
- Manual smoke test: record one Chinese-English mixed phrase, verify it pastes correctly into a real app.
- Commit a wave-close marker: `git tag voice-wave-N-complete`.

### 4.4 Final ship gate (after Plan 8f)

- All sub-plan acceptance gates pass.
- Manual QA matrix from spec Section 9 passes (60 combinations + 5 phrase suite).
- Performance baselines meet the post-spike v1 targets, or honestly miss with documented reason. Spec Section 8 starts as hypotheses and Plan 8.0 converts them into measured targets.
- Onboarding flow tested by a fresh user (not the implementer).
- Privacy claims audited: monitor network traffic during local-only run, confirm zero packets except for HuggingFace downloads.
- Spec updated with any divergences uncovered during implementation.

---

## 5. Cross-cutting Test Strategy

Different test layers across all sub-plans, with consistent locations:

### 5.1 Unit tests — `Shared/Tests/VoiceTests/`

Pure Swift, no models, no AppKit, runs on CI. Each sub-plan adds tests in its own subdirectory:
- `Shared/Tests/VoiceTests/Audio/` (8a)
- `Shared/Tests/VoiceTests/Cleanup/` (8c)
- `Shared/Tests/VoiceTests/PowerMode/` (8e)
- `Shared/Tests/VoiceTests/Selection/` (8f)
- `Shared/Tests/VoiceTests/Algorithms/` (8a, 8d, 8f shared)

Run via: `cd Shared && PKG_CONFIG_PATH=/opt/homebrew/opt/libarchive/lib/pkgconfig swift test`

### 5.2 Integration tests — `MacAllYouNeedTests/Voice/`

Requires AppKit / Xcode test target. Uses fixed audio fixture files in `MacAllYouNeedTests/Voice/Fixtures/`.

Run via: `xcodebuild test -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed`

Coverage:
- End-to-end record → cleanup → paste against fixed audio.
- Database migration (clipboard.sqlite schema upgrade).
- Mock NSWorkspace frontmost app change.
- ClipboardBridge writes to clipboard_records correctly.

### 5.3 Cross-integration tests (per wave checkpoint)

Custom test target `MacAllYouNeedTests/Voice/CrossPlan/` for tests that exercise multiple sub-plans together:
- After Wave 2 (8b + 8c + 8e): onboarding completes → cleanup pipeline runs → power mode profile auto-applies.
- After Wave 3 (8d): all 5 engines pass the fixture suite.
- After Wave 4 (8f): full Typeless-equivalent flow.

### 5.4 Local-only model + perf tests — `Shared/Tests/VoicePerfTests/`

Marked `@available(macOS 14, *)` and gated on a custom `RUN_MODEL_TESTS=1` env var so CI skips them. Each sub-plan adds its own perf benchmark.

Run locally: `RUN_MODEL_TESTS=1 swift test --filter VoicePerfTests`

### 5.5 Manual QA matrix (final ship)

Per spec Section 9. Tracked in a checklist file `MacAllYouNeedTests/Voice/Manual-QA.md` produced during Plan 8f. 60 combinations + 5 phrase suite.

### 5.6 Privacy audit

Run with Little Snitch or `nettop` during a "local-only" session (default model + Ollama provider):
- Allowed: HuggingFace download URL during onboarding only.
- Blocked: any other domain.
- Document findings in `docs/superpowers/findings/2026-XX-XX-voice-privacy-audit.md`.

---

## 6. Worktree & Branch Strategy

Each sub-plan executes in its own git worktree to enable parallel development without stepping on each other:

```bash
# Wave 1 — Plan 8a
/wt-new voice-mvp

# Wave 2 — three parallel worktrees (one per sub-plan)
/wt-new voice-onboarding
/wt-new voice-cleanup
/wt-new voice-power-mode

# Wave 3 — Plan 8d, with 4 nested worktrees for engine parallelism
/wt-new voice-multi-engine
# (within voice-multi-engine, dispatch 4 engine sub-agents with isolation: "worktree")

# Wave 4 — Plan 8f
/wt-new voice-advanced
```

Wave 2's three worktrees merge to a `voice-wave-2-integration` branch before merging to main. This catches schema collision and project.yml conflicts at the merge step, not in main.

---

## 7. Risk Register

| Risk | Owner Plan | Mitigation |
|---|---|---|
| Qwen3-ASR-0.6B has no production-grade Swift wrapper | 8.0 | Spike validates; if unworkable, demote to v1.1 and ship 8a with Parakeet or SenseVoice as default |
| Fn / Globe key cannot be captured for press/release | 8.0 | Spike gate 2; fallback shortcut documented in spec update |
| Codesign / hardened-runtime blocks model download or audio capture | 8.0 | Spike gate 1; entitlements adjusted before 8a |
| Paste injection unreliable in Electron / Catalyst apps | 8.0 | Spike gate 4; AppleScript fallback path mandatory |
| Latency hypotheses way off (e.g. 3s instead of 760ms) | 8.0 | Spike gate 5; if real numbers > 1.5s, revisit batch-vs-streaming default |
| `clipboard.sqlite` migration breaks existing users' clipboard data | 8a (single schema migration owner) | Idempotent migration test before merge; backup script in app data dir |
| Sub-agent worktrees collide on `project.yml` | All Wave 2 | Each agent re-runs `xcodegen` only at task end; merge step rebuilds project.yml |
| MLX-swift adds significant compile-time / build-time | 8d | Add to project as conditional dependency; document build-time impact |
| Ollama installation friction during onboarding | 8b / 8c | Detect Ollama binary; "Install" button deep-links to ollama.com download |
| Anthropic / OpenAI API quota exhausted during dev | 8c | Use cheap models (Haiku 4.5 / gpt-5-nano) for development; document expected $ in plan |

---

## 8. Acceptance Criteria for v1 Ship

The voice subsystem ships when all of the following are true:

- [ ] Plan 8.0 findings document filed at `docs/superpowers/findings/2026-XX-XX-voice-spike-findings.md`
- [ ] All 7 sub-plans report acceptance gates met
- [ ] Manual QA matrix (60 combinations + 5 phrase suite) passes
- [ ] `./scripts/ci-build.sh` passes on a clean checkout
- [ ] **Performance baselines from Plan 8.0 are documented in the findings file.** Spec § 8 was rewritten as "Performance Hypotheses & Measurement Gates" — v1 ship targets are derived from Plan 8.0's measured numbers, not the original hypotheses. Any divergence between hypothesis and measured result is logged in findings + spec. v1 may ship with measurements significantly different from hypotheses (e.g. ASR p50 = 800ms instead of 250ms), as long as the divergence is documented and the UX (e.g. streaming HUD vs batch HUD) was adjusted accordingly.
- [ ] Privacy audit passes (no unexpected network traffic in local-only mode)
- [ ] Onboarding flow tested by a non-implementer
- [ ] Spec doc reflects any divergences uncovered
- [ ] Updated CLAUDE.md with Voice subsystem patterns and gotchas
- [ ] Voice tab in Settings reachable from main app
- [ ] Default hotkey (Fn or fallback) registers without conflict on a fresh Mac install

---

## 9. Execution Sequencing — How To Use This Master Plan

```
╔════════════════════════════════════════════════════════════════════╗
║  Step 1: Execute Plan 8.0                                          ║
║  ─────────────────────────                                          ║
║  Open: docs/superpowers/plans/2026-05-11-08-0-voice-spike.md       ║
║  Use: superpowers:subagent-driven-development                       ║
║  Output: docs/superpowers/findings/<date>-voice-spike-findings.md   ║
╚════════════════════════════════════════════════════════════════════╝
                                  │
                                  ▼ (spike findings inform 8a details)
╔════════════════════════════════════════════════════════════════════╗
║  Step 2: Re-invoke writing-plans for Plan 8a                       ║
║  ─────────────────────────────────────                              ║
║  Input: spike findings + spec § 4 + § 5                             ║
║  Output: docs/superpowers/plans/2026-05-11-08-a-voice-mvp.md       ║
║  Then execute via subagent-driven-development                       ║
╚════════════════════════════════════════════════════════════════════╝
                                  │
                                  ▼ (8a freezes protocols)
╔════════════════════════════════════════════════════════════════════╗
║  Step 3: Re-invoke writing-plans for Plans 8b, 8c, 8e (3x)         ║
║  ─────────────────────────────────────────────────                  ║
║  Output: 3 detailed plan files                                      ║
║  Then dispatch 3 parallel sub-agents in single message              ║
║  Wait for all 3 to return                                           ║
║  Run wave-2 cross-integration tests                                 ║
║  Tag: git tag voice-wave-2-complete                                 ║
╚════════════════════════════════════════════════════════════════════╝
                                  │
                                  ▼
╔════════════════════════════════════════════════════════════════════╗
║  Step 4: Re-invoke writing-plans for Plan 8d                       ║
║  Plan 8d is single sub-agent at the master level, but internally   ║
║  dispatches 4 engine-implementing sub-agents in parallel            ║
║  Tag: git tag voice-wave-3-complete                                 ║
╚════════════════════════════════════════════════════════════════════╝
                                  │
                                  ▼
╔════════════════════════════════════════════════════════════════════╗
║  Step 5: Re-invoke writing-plans for Plan 8f                       ║
║  Single sub-agent (high integration risk)                           ║
║  Tag: git tag voice-wave-4-complete = voice-v1-ready               ║
╚════════════════════════════════════════════════════════════════════╝
                                  │
                                  ▼
╔════════════════════════════════════════════════════════════════════╗
║  Step 6: Final ship gate — Section 8 acceptance criteria            ║
║  Manual QA + privacy audit + spec sync + CLAUDE.md update           ║
╚════════════════════════════════════════════════════════════════════╝
```

---

## 10. Open Items (Master Plan Scope)

These items pertain to the **master plan itself** (not individual sub-plans):

- Decide whether sub-plan 8b's detailed plan should land before or after 8a's protocols freeze. **Default: after**, so onboarding screens can reference real types instead of placeholders.
- Confirm that running 3 parallel worktrees on M-series Mac doesn't exhaust dev resources (xcodebuild memory + simulator usage). If it does, downgrade Wave 2 to 2 parallel.
- Decide whether Plan 8.0 spike findings get merged to `main` or live only on a `voice-spike` branch. **Default: merge findings doc to main** so the spec can reference it; keep the throwaway code on the spike branch.
