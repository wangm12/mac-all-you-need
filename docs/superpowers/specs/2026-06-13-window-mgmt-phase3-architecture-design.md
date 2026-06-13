# Window Mgmt Phase 3 — Architecture

**Date:** 2026-06-13
**Status:** Approved (design)
**Parent:** [`2026-06-13-window-management-overview-design.md`](./2026-06-13-window-management-overview-design.md)
**Nature:** Behavior-neutral refactor. No user-visible change.

## Goal

Replace the ad-hoc frame math in `WindowGeometryCalculator` with Rectangle's
proven, testable abstraction: a `WindowCalculation` protocol + factory, plus a
`RepeatedExecutionsCalculation` protocol for cycling. This makes the engine
easier to reason about and unit-test, and makes future layouts (thirds, sixths,
gaps, cycling) cheap to add *if ever wanted* — none are built in this phase.

## Why

- Today, adding any new layout means hand-writing geometry inside one calculator;
  there is no isolation per action and no shared cycling machinery.
- Rectangle's pattern (researched 2026-06-13) decouples action dispatch from
  position math: each action is an isolated, independently testable unit; new
  algorithms are new small types, not edits to a growing switch.
- The user prioritized "cleaner architecture." This phase delivers it without
  changing behavior, so risk is contained and verifiable by tests.

## Design

### 1. Core abstractions (in `Shared/Sources/Core/WindowControl/`)

```swift
struct WindowCalculationParameters {
    let currentFrame: CGRect
    let visibleFrame: CGRect
    let action: WindowAction
    let preserveSize: Bool
    // room to grow: lastAction (cycling), gaps, etc. — not populated now
}

struct WindowCalculationResult {
    let rect: CGRect
    let resultingAction: WindowAction
}

protocol WindowCalculation {
    func calculate(_ params: WindowCalculationParameters) -> WindowCalculationResult?
}
```

- A `WindowCalculationFactory` maps each existing `WindowAction` to a calculation
  instance (singleton pool), giving O(1) dispatch.
- `RepeatedExecutionsCalculation` (protocol + extension) provides shared cycling
  logic for future divisional layouts. **Not wired to any user action now** — it
  exists so thirds/fourths cycling is a small addition later.

### 2. Refactor `WindowGeometryCalculator` behind the new types

- `WindowGeometryCalculator.rect(for:visibleFrame:currentSize:)` and
  `rectForMovingDisplay(...)` become thin facades that delegate to the factory,
  **or** the factory is introduced and `WindowMover` is pointed at it while the
  old calculator is reduced to the per-action calculations. Exact seam chosen so
  that the public surface `WindowMover` depends on stays stable.
- Every current action (`leftHalf`, `rightHalf`, `topHalf`, `bottomHalf`, four
  quarters, `maximize`, `almostMaximize`, `center`, `restore`, display moves) maps
  to a calculation that produces **byte-identical frames** to today.

### 3. Preserve the radial-preview parity guarantee

- `WindowMover.proposedFrame(for:element:)` (used by the radial live preview) must
  return identical rects. `RadialProposedFrameParityTests` is the guardrail and
  must stay green unchanged.

## Verification strategy (this is the whole point)

- **Golden-frame tests:** before refactoring, snapshot the output of
  `WindowGeometryCalculator` for every action across a representative matrix of
  visible frames and window sizes. After refactoring, assert the factory produces
  identical rects. This is the primary safety net for "behavior-neutral."
- Existing `WindowGeometryCalculatorTests`, `WindowActionTests`,
  `RadialProposedFrameParityTests`, `WindowMoverTests` all stay green.
- No new settings, no UI changes, no signpost budget change (reads/writes per
  action unchanged from Phase 1).

## Files touched (anticipated)

- New: `Shared/Sources/Core/WindowControl/WindowCalculation.swift`,
  `WindowCalculationFactory.swift`, `RepeatedExecutionsCalculation.swift`,
  per-action calculation types (small).
- Modified: `Shared/Sources/Core/WindowControl/WindowGeometryCalculator.swift`
  (becomes facade / delegates), `WindowMover.swift` (points at factory if the
  seam moves there).
- New tests: `WindowCalculationFactoryTests`, golden-frame table tests.

## Success criteria

- All actions produce identical frames to pre-refactor (golden tests prove it).
- Full suite green; `swiftlint --strict` clean.
- Adding a hypothetical new layout is demonstrably a new small type + one factory
  entry (validated by a throwaway spike or a documented example in the PR, not
  shipped).
- No user-visible behavior change.

## Out of scope (Phase 3)

- Actually shipping thirds/sixths/ninths/gaps/cycling (not requested; this phase
  only makes them cheap).
- Any performance change (Phase 1 owns perf; this phase must not regress the
  round-trip budget).
- Any UI change (Phase 2 owns UX).
