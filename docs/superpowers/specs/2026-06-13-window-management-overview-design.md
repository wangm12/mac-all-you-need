# Window Management Enhancement — Overview & Hierarchy Plan

**Date:** 2026-06-13
**Status:** Approved (design); phases not yet implemented
**Role:** This is the *controller* document. It organizes and sequences three
phase specs, defines the invariants they all share, and tracks their status.
Each phase spec is self-contained and links back here.

## Related specs

- Baseline (existing feature): [`2026-05-16-window-control-design.md`](./2026-05-16-window-control-design.md)
- Phase 1: [`2026-06-13-window-mgmt-phase1-performance-reliability-design.md`](./2026-06-13-window-mgmt-phase1-performance-reliability-design.md)
- Phase 2: [`2026-06-13-window-mgmt-phase2-ux-polish-design.md`](./2026-06-13-window-mgmt-phase2-ux-polish-design.md)
- Phase 3: [`2026-06-13-window-mgmt-phase3-architecture-design.md`](./2026-06-13-window-mgmt-phase3-architecture-design.md)

## Background

The app already ships a window management surface (Window Layouts + Window Grab)
that is broader in interaction than base Rectangle: modifier-drag-anywhere,
native title-bar edge snap, double-click toggle, a Loop-style radial menu,
scroll-wheel resize, active-window border, and per-app rules. Engine: AX
(`AXUIElement`) for reads/writes, `CGEventTap` for gestures,
`WindowGeometryCalculator` for frame math.

This effort does **not** add new snap layouts. The explicit goal (from
brainstorming on 2026-06-13) is to make the existing feature **faster, more
reliable, more polished, and easier to maintain** — in that priority order.

## Why (measured, not assumed)

A source-level trace of the live move path (`WindowKeyboardActionPerformer.perform`
→ `WindowMover.move` → `WindowAccessibilityElement`) found:

1. **AX round-trip redundancy.** `WindowAccessibilityElement.frame` is two AX IPC
   calls (position + size). One shortcut press makes ~25–30 synchronous AX
   round-trips, most redundant (frame read 4+ times; role/subrole/fullscreen/
   resizable/movable/enhancedUI re-queried). AX IPC spikes to milliseconds on
   Electron/Chrome/Office → the reported "lag with Chrome/Slack."
2. **Main-thread stall on animation.** `WindowMover.applyAnimatedMove` uses
   `Thread.sleep` in a 6-step loop on the `@MainActor` path; enabling
   `animateWindowMoves` freezes the UI/event loop ~100ms per move.
3. **No cross-display retry.** Single write on `nextDisplay`/`previousDisplay`;
   macOS clamps height on cross-display moves → the reported "unreliable
   multi-display snaps."
4. **Fully synchronous, no coalescing.** Held repeat shortcuts on a slow app
   serially back up the main actor.

These map one-to-one onto the three symptoms the user reported (lag/jank,
unreliable snaps, unpolished feel).

## Three pillars (priority order)

1. **Performance & Reliability** (Phase 1) — the engine. Invisible-but-felt:
   every snap lands correctly, instantly, every time.
2. **UX Polish** (Phase 2) — the felt layer: animation, feedback, haptics,
   customization of currently-hardcoded knobs.
3. **Architecture** (Phase 3) — maintainability: adopt Rectangle's
   `WindowCalculation` factory + cycling protocol behind the current geometry
   calculator. Pure refactor; unlocks future layouts cheaply if ever wanted.

## Phase sequence & dependencies

```
Phase 1 (perf + reliability)  ──►  Phase 2 (UX polish)  ──►  Phase 3 (architecture)
        │                                  │                          │
   independent;                   depends on Phase 1's          independent of 1 & 2
   ships alone                    non-blocking move path        (pure refactor); may
                                  + signpost instrumentation    be reordered if desired
```

- Phase 1 ships value on its own (no 2 or 3 required).
- Phase 2's smooth animation builds on Phase 1 removing the blocking sleep, and
  uses Phase 1's signpost instrumentation to confirm it stays non-blocking.
- Phase 3 is behavior-neutral and could in principle run before Phase 2, but is
  sequenced last because no new layouts are planned, so its payoff is latent.

Each phase is its own spec → implementation plan → PR.

## Shared invariants (every phase must uphold)

- **No main-thread blocking in the move path.** No `Thread.sleep`, no synchronous
  waits on the `@MainActor` execution path. (Phase 1 establishes this; 2 and 3
  must not regress it.)
- **AX round-trips per action are budgeted and instrumented.** Phase 1 sets the
  budget (~8 reads/action) and adds `os_signpost`. No later phase may silently
  exceed it.
- **No behavior change without a setting.** All user-visible behavior changes are
  gated by existing or new settings in `WindowControlSettings`, defaulting to
  current behavior unless explicitly stated.
- **Geometry stays test-covered and green.** Existing tests under
  `Shared/Tests/.../WindowControl/` and `WindowGeometryCalculatorTests` must pass
  before and after every phase. New logic ships with tests.
- **`design.md` compliance.** Any UI work (Phase 2 especially) routes through
  `MAYNTheme` / `MAYNControlMetrics` / `MAYNMotion` / `MAYNMotionBridge`, honors
  Reduce Motion, and passes `swiftlint --strict`. The existing documented
  exception for `WindowSnapOverlayPanel.swift` (raw black/gray OS-style overlay)
  is preserved; no new raw-color/animation exceptions without a `design.md` entry.
- **Surgical changes.** Per project guidelines: touch only what each phase
  requires; no opportunistic refactoring outside the phase scope (Phase 3 is the
  sanctioned refactor and is itself behavior-neutral).

## Cross-cutting concerns

- **Instrumentation (owned by Phase 1, used by all):** `os_signpost` intervals
  around resolve / calculate / write, plus a debug-only counter (round-trips per
  move, ms per move) surfaced in `WindowControlDiagnosticsView`. This is how
  "is it actually faster/non-blocking" is answered with evidence, not vibes.
- **Testing strategy:** Pure logic (geometry, snapshot read-count, coalescing
  decision, retry decision) is unit-tested in `Shared/Tests`. AX-touching code is
  kept behind the existing `WindowMovableElement` protocol so it remains fakeable
  (see `WindowMoverTests`). Manual verification matrix per phase covers
  Chrome/Slack/Office (slow AX), multi-display, fixed-size windows, and Reduce
  Motion.
- **Risk register:** AX threading affinity (relevant only if Phase 1 escalates to
  full async — deferred); private-API fragility (`WindowControlPrivateAPI`,
  unchanged by this effort); Stage Manager interaction (out of scope, noted).

## Success criteria (whole effort)

- Median AX round-trips per keyboard action drop from ~25–30 to ≤8 (signpost
  evidence).
- No measurable main-thread stall when animation is enabled (Phase 2 animation
  is non-blocking; Phase 1 removes the blocking path).
- Cross-display moves land at the correct size on the first user-perceived
  attempt across a 2-display setup.
- Failure states (`fixedSizeWindow`, `writeFailed`) produce visible feedback
  instead of silence.
- New geometry/engine logic is unit-tested; full suite green; `swiftlint --strict`
  clean.

## Status table

| Phase | Spec | Status | Plan | PR |
|---|---|---|---|---|
| Overview | this file | Approved | — | — |
| 1 — Perf & Reliability | phase1 | Designed (approved) | TBD | TBD |
| 2 — UX Polish | phase2 | Designed (approved) | TBD | TBD |
| 3 — Architecture | phase3 | Designed (approved) | TBD | TBD |

## Out of scope (whole effort)

- New snap layouts (thirds, sixths, ninths, gaps, cycling) — not requested;
  Phase 3 only makes them *cheap to add later*.
- Stage Manager–specific behavior, Todo mode, window stashing/focus navigation
  (Loop/Rectangle features not currently present and not requested).
- The full async per-window cancellable engine (Loop-style) — held as a measured
  escalation in Phase 1, not committed.
