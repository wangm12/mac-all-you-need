# Window Mgmt Phase 1 — Performance & Reliability Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cut AX round-trips per keyboard action from ~25–30 to ≤8, remove main-thread `Thread.sleep` from the move path, add cross-display retry, per-window coalescing, and signpost instrumentation — with tests and diagnostics proving it.

**Architecture:** Introduce `WindowSnapshot` read once per action and thread it through `WindowMover` / `WindowKeyboardActionPerformer`. Phase 1 makes `animateMoves` an instant-path alias (real animation in Phase 2). Cross-display retry is a bounded helper on `WindowMover`. Coalescing is a pure guard in the performer. Instrumentation follows existing `PerformanceSignpost` patterns.

**Tech Stack:** Swift 5.9, ApplicationServices AX, `os_signpost`, XCTest (`Shared` Platform tests + main-app diagnostics).

**Spec:** [`docs/superpowers/specs/2026-06-13-window-mgmt-phase1-performance-reliability-design.md`](../specs/2026-06-13-window-mgmt-phase1-performance-reliability-design.md)

---

## File Map

**Create**
- `Shared/Sources/Platform/WindowControl/WindowSnapshot.swift` — value type + `WindowMovableElement.snapshot()` default.
- `Shared/Sources/Platform/WindowControl/WindowMoveCoalescing.swift` — pure coalescing decision (testable).
- `Shared/Tests/PlatformTests/WindowControl/WindowSnapshotReadBudgetTests.swift` — AX read budget assertions.
- `Shared/Tests/PlatformTests/WindowControl/WindowCrossDisplayRetryTests.swift` — height-clamp retry.
- `Shared/Tests/PlatformTests/WindowControl/WindowMoveCoalescingTests.swift` — supersede logic.

**Modify**
- `Shared/Sources/Platform/WindowControl/WindowMover.swift` — snapshot threading, remove blocking animation, retry helper.
- `Shared/Sources/Platform/WindowControl/WindowAccessibilityElement.swift` — batched `snapshot()`, debug round-trip counter.
- `MacAllYouNeed/WindowControl/WindowKeyboardActionPerformer.swift` — snapshot reuse in resolve, coalescing guard.
- `MacAllYouNeed/WindowControl/WindowControlCoordinator.swift` — signpost wiring.
- `MacAllYouNeed/WindowControl/WindowControlDiagnosticsView.swift` — surface debug metrics.
- `Shared/Sources/Core/PerformanceSignpost.swift` — `WindowControl` signpost enum.
- `Shared/Tests/PlatformTests/WindowControl/WindowMoverTests.swift` — extend `FakeWindowElement` with read counters.

---

## Chunk 1: WindowSnapshot + Read Budget

### Task 1: `WindowSnapshot` type and protocol

**Files:**
- Create: `Shared/Sources/Platform/WindowControl/WindowSnapshot.swift`
- Modify: `Shared/Sources/Platform/WindowControl/WindowMover.swift` (protocol)
- Modify: `Shared/Tests/PlatformTests/WindowControl/WindowMoverTests.swift` (`FakeWindowElement`)

- [ ] **Step 1: Add `WindowSnapshot` struct and `snapshot()` to `WindowMovableElement`**
- [ ] **Step 2: Implement batched `snapshot()` on `WindowAccessibilityElement`**
- [ ] **Step 3: Add read counters to `FakeWindowElement`; implement `snapshot()`**
- [ ] **Step 4: Thread `snap` through `WindowMover.move` / `moveValidated` / `proposedFrame`**
- [ ] **Step 5: Add `testMoveUsesSingleSnapshotAndBoundedFrameReads`**
- [ ] **Step 6: Run tests**

```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter 'WindowMoverTests|WindowSnapshotReadBudgetTests'
```

Expected: PASS; `frame` property reads during one `leftHalf` move ≤ 3 (1 snapshot + post-write + optional clamp).

---

## Chunk 2: Remove Blocking Animation

### Task 2: Neutralize `animateMoves` in Phase 1

**Files:**
- Modify: `Shared/Sources/Platform/WindowControl/WindowMover.swift`

- [ ] **Step 1: Replace `applyAnimatedMove` body with instant write path (same as non-animated branch)**
- [ ] **Step 2: Add `testAnimateMovesDoesNotBlockMainThread` — assert no `Thread.sleep` in animated branch (operations identical to instant)**
- [ ] **Step 3: Run `WindowMoverTests`**

```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter WindowMoverTests
```

---

## Chunk 3: Cross-Display Retry

### Task 3: Bounded retry after display moves

**Files:**
- Modify: `Shared/Sources/Platform/WindowControl/WindowMover.swift`
- Create: `Shared/Tests/PlatformTests/WindowControl/WindowCrossDisplayRetryTests.swift`

- [ ] **Step 1: Write failing test — fake element clamps height on first write, retry corrects**
- [ ] **Step 2: Implement `retryCrossDisplayIfNeeded` helper after write block**
- [ ] **Step 3: Schedule single 25ms `DispatchQueue.main.asyncAfter` retry when still mismatched**
- [ ] **Step 4: Run cross-display + existing `nextDisplay` tests**

```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter 'WindowCrossDisplayRetryTests|WindowMoverTests/testNextDisplay'
```

---

## Chunk 4: Coalescing Guard

### Task 4: Per-window action supersede

**Files:**
- Create: `Shared/Sources/Platform/WindowControl/WindowMoveCoalescing.swift`
- Modify: `MacAllYouNeed/WindowControl/WindowKeyboardActionPerformer.swift`
- Create: `Shared/Tests/PlatformTests/WindowControl/WindowMoveCoalescingTests.swift`

- [ ] **Step 1: Pure `shouldSupersedeInFlightMove(incoming:existing:now:)` with 50ms window**
- [ ] **Step 2: Unit test same-window supersede vs different-window pass-through**
- [ ] **Step 3: Wire guard in performer (drop superseded action)**
- [ ] **Step 4: Run coalescing tests**

---

## Chunk 5: Instrumentation

### Task 5: Signposts + diagnostics

**Files:**
- Modify: `Shared/Sources/Core/PerformanceSignpost.swift`
- Modify: `MacAllYouNeed/WindowControl/WindowControlCoordinator.swift`
- Modify: `MacAllYouNeed/WindowControl/WindowKeyboardActionPerformer.swift`
- Modify: `MacAllYouNeed/WindowControl/WindowControlDiagnosticsView.swift`
- Modify: `Shared/Sources/Platform/WindowControl/WindowAccessibilityElement.swift` (debug counter)

- [ ] **Step 1: Add `PerformanceSignpost.WindowControl` (resolve / calculate / write)**
- [ ] **Step 2: Wrap performer + mover hot paths**
- [ ] **Step 3: Debug-only AX round-trip counter surfaced in diagnostics**
- [ ] **Step 4: Full verification**

```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test
./scripts/ci-build.sh
```

---

## Manual verification matrix (before PR)

- [ ] Chrome / Slack / Office — triple-write lands correct size
- [ ] 2-display `nextDisplay` / `previousDisplay` — correct size first try
- [ ] Fixed-size dialog — `.fixedSizeWindow`, no spurious writes
- [ ] Rapid-repeat keyboard hold — no main-actor backup
- [ ] `animateWindowMoves` on — no UI freeze (instant path in Phase 1)
- [ ] `RadialProposedFrameParityTests` green

---

## Commit strategy

One commit per chunk after tests pass:
1. `feat(window-control): add WindowSnapshot and bound AX reads per move`
2. `fix(window-control): remove Thread.sleep from animateMoves path`
3. `fix(window-control): cross-display size retry after clamp`
4. `feat(window-control): coalesce in-flight moves for same window`
5. `feat(window-control): signposts and diagnostics for move performance`
