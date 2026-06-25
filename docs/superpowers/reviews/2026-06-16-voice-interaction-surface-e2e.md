# Voice Interaction Surface — E2E Review Report

**Date:** 2026-06-16  
**Reviewer:** code-reviewer subagent + implementation pass  
**Build:** `MacAllYouNeed` target **BUILD SUCCEEDED** (arm64)

## Summary

**Overall: Pass with gaps**

Core Phase 1/2 goals are implemented: three-layer chrome, `Starting…`, full-span processing wipe with Typeless-style boot curve, Cancel/Restore semantics, alert toasts, partial policy, and success hold dismiss. Remaining gaps are mostly Phase 2 polish (blocking pending UI, education hints) and test-target compile drift unrelated to this feature.

### P0 blockers

None identified in code review.

### P1 gaps

1. **G — Previous pending** shows a soft toast only; no blocking alert with **Cancel previous / Keep waiting** actions.
2. **Paste target toast** fires on every session start when frontmost app exists; plan called for conditional display (first use / app change).
3. **`VoiceAlertPresenter.Kind.blocking`** exists but has no action buttons wired.
4. **Education hints** (`Release to finish`, first toggle) not implemented.
5. **Test target** does not compile (`SettingsDestinationTests` etc.) after `xcodegen generate` — blocks automated `MiniVoiceHUDTests` CI until fixed separately.

---

## Flow matrix

| Flow | Expected | Code path | Verdict | Notes |
|------|----------|-----------|---------|-------|
| A Hold happy | Starting → Listening → release → Transcribing+wipe@0 → hold dismiss | `startRecording` → `showStartingMic`; `audio.start` → `showRecording`; `handleActivationRelease` → `showTranscribingPhase(.finalizing)` → `processCapturedAudio` → `dismissAfterSuccessHold` | **Pass** | Wipe begins on first `.transcribing` show |
| B Toggle happy | Finish ends recording | `onFinish` → `finishRecordingFromToggle`; pill shows Finish+Cancel | **Pass** | Second hotkey press also finishes (toggle) |
| C Progress | Boot 50%@1s, ~63%@10s; wipe all phases | `MiniVoiceThinkingProgressBridge.bootKeyframes`; `showsTranscribingProgressWipe` for all `.transcribing` | **Pass** | Stream max-merge in `applyStreamProgress` |
| C Slow | Pill `Still working…`; alert `Taking longer…` | `startSlowProcessingWatch` @3.5s / @8.5s | **Pass** | |
| D Cancel | Processing Cancel (X), not Stop | `VoicePillActionAvailability.cancel` | **Pass** | |
| D Restore | Cancelled + Restore | `showCancelled` + `onUndo` / Return | **Pass** | Label **Restore** in a11y |
| E Errors | Specific pill + alert | `VoicePillErrorLabels` | **Partial** | Generic messages still possible for unknown errors |
| F Clipboard fallback | Pill + alert | `showClipboardFallbackNotice` | **Pass** | |
| G Pending | Block new recording + alert | `handleActivationPress` returns + `showPendingRecordingAlert` | **Partial** | Soft only, no actions |
| H Esc | Cancel / dismiss restore / terminal | `VoiceHUDPresenter.handleEscKey` | **Pass** | |
| H Return | Restore while Cancelled | `handleEnterKey` when `hasPendingUndo` | **Pass** | |

---

## Adopt / Modify / Avoid checklist

| Item | Verdict | Evidence |
|------|---------|----------|
| Release-immediate wipe | **Adopt** | `isTranscribingSessionActive` + `beginThinkingSession` on first transcribing |
| Typeless boot curve | **Adopt** | `bootKeyframes` 0→30%@0.4s→50%@1s→63%@10s |
| Keep Transcribing label | **Modify** | `VoicePillContentModel` |
| Keep sparkle | **Modify** | `AISparkleIcon` |
| Alert layer concept | **Adopt** | `VoiceAlertPresenter` |
| Using {mic} | **Adopt** | `showMicDeviceToastIfNeeded` |
| Clearer mic | **Defer** | Not implemented |
| No hover bar clone | **Avoid** | `VoiceInsertionAnchorPresenter` one-shot only |
| Listening label | **Keep** | |
| Constrained partial | **Keep** | `VoicePartialDisplayPolicy` |
| Full processing wipe | **Change** | All transcribing subphases |
| Cancel not Stop | **Change** | `CancelButton` |
| Specific errors | **Change** | `VoicePillErrorLabels` |
| Clipboard fallback explain | **Keep+** | Dual pill + alert |

---

## Post-review fixes (2026-06-16)

Applied after code-reviewer E2E pass:

1. **`Starting…` + Esc** — `isPreparingRecording` gate; cancel bumps `operationGeneration` and aborts async warmup.
2. **Paste timeout label** — `"Paste timed out"` → pill **Couldn't paste** (not `Still working…`).
3. **Reduce Motion wipe** — boot curve still advances (instant jump to ~30%, slower ticks); sparkle remains damped in view.

**Still open (P1 defer):** blocking pending alert with actions, blocking error buttons, education toasts, gated paste/mic toasts.

1. Wire **blocking** pending alert with actions when hotkey pressed during transcribing.
2. Gate **paste target** / **Using mic** toasts per plan (device change, first use).
3. Add **education** toasts with UserDefaults frequency caps.
4. Fix **test target** compile failures so `MiniVoiceHUDTests` runs in CI.
5. Add coordinator tests for `Starting…` → `Listening` transition timing.

---

## Files touched (implementation)

- `MacAllYouNeed/Voice/UI/MiniVoiceHUD.swift` — states, wipe, chrome, boot curve
- `MacAllYouNeed/Voice/UI/VoiceSessionChrome.swift` — composition root
- `MacAllYouNeed/Voice/UI/VoiceAlertPresenter.swift` — toast layer
- `MacAllYouNeed/Voice/UI/VoicePartialDisplayPolicy.swift` — partial gating
- `MacAllYouNeed/Voice/UI/VoicePillErrorLabels.swift` — error copy
- `MacAllYouNeed/Voice/UI/VoiceLongRecordingSupport.swift` — long recording + privacy
- `MacAllYouNeed/Voice/UI/VoiceInsertionAnchorPresenter.swift` — first-use anchor
- `MacAllYouNeed/Voice/VoiceHUDPresenter.swift` — orchestration
- `MacAllYouNeed/Voice/VoiceCoordinator.swift` — session lifecycle
- `MacAllYouNeed/Voice/VoicePipelineController.swift` — success hold dismiss
- `MacAllYouNeed/Voice/Audio/AudioCaptureService.swift` — v8 RMS envelope
- `design.md` §7.5, `design/voice_pill/processing_pill_v8_spec.md`
