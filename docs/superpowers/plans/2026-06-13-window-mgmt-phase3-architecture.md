# Window Mgmt Phase 3 — Architecture Implementation Plan

> **Status:** Complete

**Goal:** Behavior-neutral refactor — `WindowCalculation` protocol + factory replacing ad-hoc switch in `WindowGeometryCalculator`.

**Spec:** [`docs/superpowers/specs/2026-06-13-window-mgmt-phase3-architecture-design.md`](../specs/2026-06-13-window-mgmt-phase3-architecture-design.md)

## Delivered

- `WindowCalculation`, `WindowCalculationParameters`, `WindowCalculationResult`
- Per-action calculation types in `WindowActionCalculations.swift`
- `WindowCalculationFactory` singleton pool + O(1) dispatch
- `RepeatedExecutionsCalculation` protocol (cycling scaffold, not wired)
- `WindowGeometryCalculator` thin facade delegating to factory
- Golden-frame tests + factory parity tests
- All existing geometry/mover/radial parity tests green
