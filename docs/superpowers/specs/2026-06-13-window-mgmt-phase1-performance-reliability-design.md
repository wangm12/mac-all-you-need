# Window Mgmt Phase 1 — Performance & Reliability

**Date:** 2026-06-13
**Status:** Approved (design)
**Parent:** [`2026-06-13-window-management-overview-design.md`](./2026-06-13-window-management-overview-design.md)
**Engine approach:** Option C (Hybrid) — chosen during brainstorming.

## Goal

Make every window action land correctly and instantly, with no main-thread
stalls, and with evidence (instrumentation) that proves it. No new layouts, no
UI redesign. This phase is the engine.

## Measured problems this phase fixes

From the source-level trace (see overview "Why"):

| # | Problem | Evidence (file:line) |
|---|---|---|
| P1 | ~25–30 redundant AX round-trips per action; `frame` = 2 IPC calls, read 4+ times | `WindowAccessibilityElement.frame` (23–30); `WindowMover.move`/`moveValidated`/`clampOffscreenWindow`/`result` re-read frame & bools |
| P2 | Main-thread stall: `Thread.sleep` animation loop on `@MainActor` | `WindowMover.applyAnimatedMove` (363–391) |
| P3 | No cross-display retry → height clamp leaves wrong size | `WindowMover.targetFrame` `.nextDisplay`/`.previousDisplay` (216–241); single write in `moveValidated` |
| P4 | Synchronous, no coalescing; held repeats back up main actor | `WindowControlCoordinator.perform(action:)` → `WindowKeyboardActionPerformer.perform` synchronous |

## Design

### 1. `WindowSnapshot` — one read per action (fixes P1)

Introduce a value type capturing everything the move path needs, read **once**:

```swift
public struct WindowSnapshot: Equatable, Sendable {
    public let frame: CGRect
    public let isResizable: Bool
    public let isMovable: Bool
    public let isSupportedForWindowControl: Bool
    public let enhancedUserInterfaceEnabled: Bool?
}
```

- Add `func snapshot() -> WindowSnapshot` to the `WindowMovableElement` protocol
  (and `WindowAccessibilityElement`), implemented as a single batched read pass.
  Where possible, read position/size/role/subrole/settable flags consecutively to
  minimize IPC; cache the role-derived `isSupportedForWindowControl` result.
- `WindowMover.move(...)` captures `let snap = element.snapshot()` at entry and
  threads `snap` through `targetFrame`, `moveValidated`, the resize/preserve
  decision, and `result()`. These stop calling `element.frame` / `element.isResizable`
  / `element.enhancedUserInterfaceEnabled` repeatedly.
- **Reads that must stay live:** exactly one post-write `element.frame` to compute
  `resultingFrame`/validate the write, and the `clampOffscreenWindow` read of the
  *actual* landed frame (the write may have been clamped by the app). These are
  intentional, not redundant. Everything else uses `snap`.
- `resolveFocusedWindow` (`WindowKeyboardActionPerformer`) also takes one
  snapshot and reuses it for identity (`frameFingerprint`, support check) instead
  of separate `frame` + `isSupportedForWindowControl` + `frameFingerprint` reads.

**Budget:** ≤8 AX round-trips per keyboard action (down from ~25–30): 1 batched
read pass (~3–4 IPC), 3 writes (size/position/size), 1 post-write frame read,
optional 1 clamp write, optional enhancedUI toggle pair.

### 2. Non-blocking move path (fixes P2)

- Remove the `Thread.sleep`-based `applyAnimatedMove` from the synchronous move
  path entirely. Phase 1's move is **always instant** (the
  `AXEnhancedUserInterface`-off instant write, which is already smooth and is
  what Rectangle ships).
- The `animateMoves` flag and `animateWindowMoves` setting are **retained** but in
  Phase 1 the animated branch is a no-op alias for the instant path (documented),
  so no behavior regression and no main-thread block. Real non-blocking smooth
  animation is delivered in Phase 2, which re-implements the animated branch with
  a timer/displaylink driver off the blocking path.
- Rationale: animation is polish (Phase 2). The *blocking* is a perf defect and is
  removed now.

### 3. Cross-display retry (fixes P3)

- After a `.nextDisplay` / `.previousDisplay` move (and any move where the target
  screen differs from the source screen), compare the landed frame's size against
  the proposed size. If height (or width) differs beyond tolerance, re-issue the
  size/position/size write once.
- If still mismatched, schedule **one** retry via `DispatchQueue.main.asyncAfter`
  at 25ms (Rectangle's value) that re-applies the proposed frame using the cached
  proposed rect (no new AX reads needed for the proposal). This is the only
  asynchronicity added in Phase 1 and it is bounded (single retry).
- Encapsulate as a small helper on `WindowMover` so it is unit-testable via a fake
  element that simulates height clamping.

### 4. Per-window coalescing guard (fixes P4)

- A lightweight guard in `WindowKeyboardActionPerformer` (or coordinator): track
  an in-flight marker keyed by resolved `WindowIdentity`. If a new action for the
  *same* window arrives while a move is still settling (within a short window),
  drop/replace the superseded action rather than queueing both.
- This is a **guard, not a full async actor.** It prevents serial backup on held
  repeats without introducing per-`CGWindowID` cancellable Tasks or AX threading
  concerns. The decision logic (supersede vs. run) is pure and unit-testable.
- **Escalation path (deferred, not built):** if signpost data later shows the
  main actor still backs up under sustained rapid input, escalate to the full
  Loop-style async cancellable engine. Phase 1 explicitly does not build this.

### 5. Instrumentation (new; consumed by all phases)

- Add `os_signpost` intervals around: focused-window resolve, frame calculate,
  and the AX write block. Subsystem `com.macallyouneed.windowcontrol`.
- Add a debug-only per-move metric (AX round-trip count, wall-clock ms) surfaced
  in `WindowControlDiagnosticsView` (it already shows recent movement results).
- Round-trip counting: increment a counter in `WindowAccessibilityElement`'s AX
  read/write wrappers behind a debug flag, or wrap via the test seam. Must be
  zero-cost in release.

## Files touched (anticipated)

- `Shared/Sources/Platform/WindowControl/WindowMover.swift` — snapshot threading,
  remove blocking animation, cross-display retry helper.
- `Shared/Sources/Platform/WindowControl/WindowAccessibilityElement.swift` —
  `snapshot()`, batched read pass, debug round-trip counter.
- `Shared/Sources/Platform/WindowControl/WindowMover+Geometry.swift` — if helpers
  needed for retry/size comparison.
- `MacAllYouNeed/WindowControl/WindowKeyboardActionPerformer.swift` — snapshot
  reuse in resolve, coalescing guard.
- `MacAllYouNeed/WindowControl/WindowControlCoordinator.swift` — wire signposts;
  possibly host the coalescing marker.
- `MacAllYouNeed/WindowControl/WindowControlDiagnosticsView.swift` — surface metrics.
- Protocol `WindowMovableElement` gains `snapshot()`.

## Testing

- **`WindowSnapshot` read-count:** extend the fake element in `WindowMoverTests`
  to count AX reads/writes; assert a single move stays within the ≤8 budget and
  that `frame` is read at most the intended number of times.
- **Cross-display retry:** fake element that clamps height on first write; assert
  the retry corrects it and that exactly one async retry is scheduled.
- **Coalescing decision:** pure unit test — same-window newer action supersedes;
  different-window action does not.
- **No-regression:** all existing `WindowMoverTests`, `WindowGeometryCalculatorTests`,
  `WindowScreenDetectorTests`, `RadialProposedFrameParityTests` stay green
  (the radial preview uses `proposedFrame(...)`, which must remain unchanged).
- **Manual matrix:** Chrome / Slack / Office (slow AX, triple-write correctness),
  2-display next/prev display, fixed-size dialog, rapid-repeat hold.

## Success criteria

- Signpost/diagnostics show ≤8 AX round-trips per keyboard action (was ~25–30).
- `animateWindowMoves` on → no main-thread stall (no `Thread.sleep` on the path).
- Cross-display move lands at correct size on first user-perceived attempt.
- No regression in existing tests; `swiftlint --strict` clean.
- Radial live preview frames identical to before (parity test green).

## Risks & mitigations

- **Snapshot staleness:** the window could move between snapshot and write. Mitigation:
  snapshot is taken immediately before the move; the post-write live read +
  clamp handles the actual landed state. Identity matching already tolerates this.
- **Batched read correctness:** ensure `isSupportedForWindowControl` semantics
  (role/subrole/fullscreen exclusions) are preserved exactly. Covered by reusing
  the existing predicate over snapshot-captured raw attributes.
- **Coalescing dropping a wanted action:** scope the guard to same-window +
  short window only; never drop across different windows. Unit-tested.

## Out of scope (Phase 1)

- Smooth animation (Phase 2), failure-state UI feedback (Phase 2), haptics
  (Phase 2), full async cancellable engine (deferred escalation),
  `WindowCalculation` refactor (Phase 3).
