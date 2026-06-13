# Window Mgmt Phase 2 — UX Polish

**Date:** 2026-06-13
**Status:** Approved (design)
**Parent:** [`2026-06-13-window-management-overview-design.md`](./2026-06-13-window-management-overview-design.md)
**Depends on:** Phase 1 (non-blocking move path + signpost instrumentation)

## Goal

Make the feature *feel* finished: smooth motion, honest feedback when something
fails, optional tactile confirmation, and user control over the knobs that are
currently hardcoded. No new snap layouts. All UI routes through the design
system and honors Reduce Motion.

## Scope

### 1. Non-blocking smooth move animation

Re-implement the animated move branch that Phase 1 neutralized, this time without
blocking the main thread.

- Driver: a timer/`CADisplayLink`-style stepper (or `NSAnimation`/Loop-style
  callback) that interpolates frame toward target across a short duration and
  issues AX writes per tick — **never** `Thread.sleep`.
- Cancel an in-flight animation if a newer action targets the same window
  (coordinate with Phase 1's coalescing marker).
- Duration/curve routed through `MAYNMotion.<kind>Animation(reduceMotion:)` /
  `MAYNMotionBridge.effectiveDuration(_:)`. **Reduce Motion → instant move.**
- Gated by the existing `animateWindowMoves` setting (default unchanged).
- Respect the AX round-trip budget per the overview (animation adds writes, not
  reads; signposts confirm no main-thread stall).

### 2. Footprint / preview animation polish

- Apply a subtle fade in/out to `WindowSnapOverlayPanel` and the radial preview,
  matching Rectangle's footprint fade feel.
- Durations via `MAYNMotion`; Reduce Motion disables the fade (instant show/hide).
- Preserve the documented raw black/light-gray overlay exception
  (`design.md §`, `WindowSnapOverlayPanel.swift`) — only the *animation* is added,
  not new colors.

### 3. Failure-state feedback (currently silent)

Phase 1's engine already returns rich `WindowMovementStatus`. Surface it:

- `.fixedSizeWindow` → quiet `MAYNToast` / mini-HUD: "This window can't be
  resized" (centered-only behavior already happens; tell the user why).
- `.writeFailed` → quiet toast: "Couldn't move this window" (with a hint to check
  Accessibility permission if AX writes are failing wholesale).
- `.unsupportedWindow` on an explicit user action → subtle, non-nagging feedback;
  no toast spam on rapid repeats (debounce identical messages).
- Feedback presentation uses existing `MAYNToast`; placement consistent with the
  app's existing toast conventions. Reduce Motion respected.

### 4. Optional snap haptics

- On a committed drag-snap / keyboard snap, optionally fire
  `NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime:)`.
- New setting `snapHapticsEnabled` in `WindowControlSettings` (default off, to
  match Rectangle which ships it off-by-default for trackpad-only feedback).

### 5. Customize currently-hardcoded knobs

Two things the references expose that this app hardcodes:

- **Radial keyboard shortcuts** (Q/W/E/D/C/S/Z/A/M/F are hardcoded). Add a
  customization surface in the radial settings tab so each ring/center action's
  cheat-sheet key is user-rebindable. Persist in `WindowControlSettings`. Display
  via existing chip components; edit via the existing recorder pattern per the
  `MacAllYouNeed/CLAUDE.md` hotkey rule (no inline recorders on top-level pages).
- **Snap zone thresholds** (`WindowSnapIntentConfiguration`: edge 5px, corner
  20px, side-half 145px, movement 12px are hardcoded). Add advanced settings to
  tune these, with the current values as defaults and a "reset to defaults"
  action. Validate ranges to avoid unusable configs.

## Design-system compliance (hard requirements)

- No `Color(red:green:blue:)`, no `.pickerStyle(.segmented)`, no raw
  `Animation.easeOut/easeInOut/linear/spring`. Use `MAYNTheme`,
  `FunctionSegmentedTabStrip`, `MAYNMotion`/`MAYNMotionBridge`.
- New settings rows use `MAYNSettingsRow` / `MAYNSection` / `MAYNNumericStepper` /
  `MAYNDropdown` per the component table.
- Every added spatial animation honors `@Environment(\.accessibilityReduceMotion)`
  or `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`.
- `swiftlint --strict` passes; run the `design.md §13` checklist before PR.

## Files touched (anticipated)

- `Shared/Sources/Platform/WindowControl/WindowMover.swift` — non-blocking
  animated branch.
- `MacAllYouNeed/WindowControl/WindowSnapOverlayPanel.swift` — fade.
- Radial preview controllers — fade.
- `MacAllYouNeed/WindowControl/WindowControlCoordinator.swift` (+ movement
  handler) — route statuses to feedback, fire haptics.
- A small feedback presenter (reuse `MAYNToast`).
- `Shared/Sources/Core/WindowControl/WindowControlSettings.swift` — `snapHapticsEnabled`,
  radial key overrides, snap-threshold overrides.
- `MacAllYouNeed/WindowControl/RadialMenuSettingsTabView.swift`,
  `WindowControlSettingsView.swift` — new controls.
- `Shared/Sources/Core/WindowControl/WindowSnapIntent.swift` /
  `WindowSnapZone.swift` — accept configurable thresholds.

## Testing

- Animation: assert no `Thread.sleep`; Reduce Motion path returns instant;
  signposts show no main-thread stall (carried from Phase 1).
- Feedback: status → message mapping unit-tested; duplicate-message debounce
  tested.
- Settings: threshold validation/clamping unit-tested; snap-zone logic with
  custom thresholds covered by extending `WindowSnapIntentTests` /
  `SnapAssistZoneTests`.
- Manual: Reduce Motion on/off, haptics on a trackpad, fixed-size dialog toast,
  rebind a radial key and confirm cheat sheet + dispatch update.

## Success criteria

- Animation is visibly smooth and provably non-blocking (signpost evidence).
- Fixed-size / write-failure actions produce visible, non-spammy feedback.
- Radial keys and snap thresholds are user-configurable with safe defaults and
  reset.
- All design-system rules satisfied; `swiftlint --strict` clean; tests green.

## Out of scope (Phase 2)

- New snap layouts/gaps/cycling (none planned).
- The `WindowCalculation` refactor (Phase 3).
- Full async cancellable engine (deferred escalation from Phase 1).
