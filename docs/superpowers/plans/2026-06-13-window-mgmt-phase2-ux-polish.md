# Window Mgmt Phase 2 — UX Polish Implementation Plan

> **For agentic workers:** Execute in order; steps use checkbox syntax.

**Goal:** Smooth non-blocking move animation, failure toasts, optional haptics, user-configurable radial keys and snap thresholds.

**Depends on:** Phase 1 complete.

**Spec:** [`docs/superpowers/specs/2026-06-13-window-mgmt-phase2-ux-polish-design.md`](../specs/2026-06-13-window-mgmt-phase2-ux-polish-design.md)

---

## Chunk 1: Non-blocking move animation

- `WindowMoveAnimationConfiguration` + timer driver on `WindowMover`
- Wire `MAYNMotionBridge` durations via coordinator `applySettings`
- Cancel on supersede (performer)
- Tests: no `Thread.sleep`; reduce-motion → instant

## Chunk 2: Failure feedback + haptics

- `WindowControlMovementFeedback` (debounced `CopyHUD`)
- `snapHapticsEnabled` setting; fire on `.moved` in `recordMovement`

## Chunk 3: Radial key bindings

- `RadialMenuKeyBindings` in settings + `RadialMenuLayout` resolver
- Settings UI key editor in radial tab
- Event tap uses runtime bindings

## Chunk 4: Snap threshold settings

- `WindowSnapIntentConfiguration.validated()`
- Settings UI in snap tab + reset defaults
- Event tap refreshes tracker on `updateRuntime`

## Chunk 5: Verify overlay fades (already MAYNMotion-backed)

- Confirm reduce-motion instant path in overlay panels (no code if already correct)
