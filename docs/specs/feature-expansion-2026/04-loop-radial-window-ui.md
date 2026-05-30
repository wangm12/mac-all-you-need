# 04 — Loop Radial Window UI

Status: Draft (design spec, implementation-ready)
Owner: Window Control
Feature gate: optional `FeatureDescriptor` + settings toggle (`Radial window menu`)
Last verified against source: 2026-05-30

---

## 1. Summary

Loop Radial Window UI adds an **optional, settings-gated** radial (pie) window-management
overlay to Mac All You Need, inspired by the UI/UX layer of
`reference-projects/Loop-develop`. The user holds a trigger key; a radial menu and a
live preview overlay appear; the user picks a direction (cursor or keyboard); on release
the chosen layout commits.

The defining constraint: **we adopt only Loop's presentation layer.** Loop's radial menu
and preview window views resolve to *a single window action plus a preview frame*. We take
that pair and route it straight into MAYN's existing window engine. We do **not** adopt
Loop's `WindowActionEngine`, `WindowAction` model, `ResizeContext`, `KeybindTrigger`,
`ActiveEventMonitor`/`PassiveEventMonitor` stack, `Defaults`, `Scribe`/`@Loggable`, or
`AnimationConfiguration`. Snapping geometry and the AX write path remain MAYN's
(`WindowGeometryCalculator`, `WindowMover`, `WindowControlCoordinator`).

When the toggle is off, window behavior is byte-for-byte today's behavior: the held-trigger
event path is never armed and no overlays are constructed.

---

## 2. Goals / Non-goals

### Goals

- A held-trigger lifecycle (hold → overlays appear → select → release → commit) built on
  MAYN's existing `WindowControlEventTap`, not a ported trigger stack.
- A re-skinned radial menu overlay (borderless non-activating `NSPanel` + SwiftUI
  `NSHostingView`) positioned at the cursor or locked to screen center, animated, and
  reusable inside Settings as a live preview via an `isSettingsPreview` flag.
- A re-skinned preview overlay (screen-sized panel, one window level below the radial menu)
  drawing the resolved target frame, animated.
- Selection via **both** cursor angle/distance mapping (porting the math from Loop's
  `MouseInteractionObserver`) **and** keyboard (arrow / paired directional keys). Keyboard
  selection may ship first.
- A thin `RadialMenuCoordinator` (the MAYN analogue of Loop's `LoopManager`, minimal) that
  owns open/update/commit/cancel and holds the current `MAYN.WindowAction`; on commit it
  calls `WindowControlCoordinator.perform(action:)`.
- A read-only "resolve frame for action" call exposed from MAYN's frame layer so the
  preview overlay draws exactly the frame the commit will produce (no preview/commit drift).
- A single settings toggle that gates a dedicated `FeatureDescriptor`.

### Non-goals

- **Adopting Loop's window logic.** Loop's `WindowActionEngine`, `ResizeContext`, edge
  nudging (`.smaller`/`.larger`), cycle actions, stashing, padding configuration, and
  multi-window focus navigation are all out of scope. The radial menu only ever emits a
  `MAYN.WindowAction`.
- **Extending MAYN's action vocabulary.** `WindowAction`
  (`Shared/Sources/Core/WindowControl/WindowAction.swift:3`) stays at its current 15 cases.
  We hardcode/simplify the radial layout to those cases. Adding new actions (thirds,
  custom percentages, smaller/larger, screen-directional focus) is explicitly deferred.
- New TCC permissions. Accessibility is already held by Window Control.
- Touching modifier-drag grab, edge-snap, or double-click-zoom behavior. Those paths are
  unchanged.
- Loop's `Defaults`, `Scribe`/`@Loggable`, `AccentColorController`/wallpaper processor,
  haptics config surface, updater hooks, and icon-unlock gamification.

---

## 3. Full feature scope

### 3.1 Held-trigger lifecycle

1. **Idle.** Toggle on, but no trigger held. The event tap behaves exactly as today.
2. **Open.** The configured trigger key goes down (and stays down past a short debounce).
   `RadialMenuCoordinator.open()` captures the focused window, its current frame, the
   cursor position, and the locked target screen, then shows both overlays with an initial
   `currentAction == nil` (no selection).
3. **Update.** While the trigger is held, selection changes (cursor movement or directional
   key) update `currentAction`. Each change re-resolves the preview frame and re-animates
   the radial angle and the preview rectangle.
4. **Commit.** Trigger release with a non-nil `currentAction` → `commit()` → exactly one
   `WindowControlCoordinator.perform(action:)` call → both overlays dismiss.
5. **Cancel.** Trigger release with no selection, Esc, or focus/space change → `cancel()` →
   overlays dismiss with no window mutation.

Lifecycle ownership lives in `RadialMenuCoordinator`. The trigger key transitions are
detected by `WindowControlEventTap`, which forwards open/update/commit/cancel intents to
the coordinator (see §4.4 and §6). We do **not** port Loop's `KeybindTrigger`,
`TriggerKeyTimeoutTimer`, or `MiddleClickTrigger`.

### 3.2 Radial menu overlay

- Borderless, non-activating `NSPanel` (`[.borderless, .nonactivatingPanel]`), `hasShadow`
  false, clear background, `ignoresMouseEvents = true`, mirroring Loop's
  `RadialMenuController.swift:35-48` but built through MAYN's
  `NonActivatingFloatingPanelController` (`Shared/Sources/UI/NonActivatingFloatingPanelController.swift:7`,
  `present(rootView:size:animated:)` at `:54`, `update(rootView:)` at `:100`) the same way
  `WindowSnapOverlayPanel` does (`MacAllYouNeed/WindowControl/WindowSnapOverlayPanel.swift:44-67`).
- Fixed compact size (Loop uses `100 + 80`; we hardcode a MAYN-tokenized diameter). Hosts a
  ported `RadialMenuView` driven by a `RadialMenuViewModel` (ObservableObject) carrying
  `currentAction`, an animated `angle`, `isShown`, and `isSettingsPreview`.
- Position: at cursor by default; at the locked target screen center when the
  "lock to center" preference is on (Loop `RadialMenuController.swift:51-68`).
- Window level: above the preview overlay (Loop uses `.screenSaver`; we reuse MAYN's
  `FloatingHUDWindowLayering` level so it sits with other MAYN HUDs).
- **Re-skin to MAYNTheme.** Segment fill/stroke, selected-segment highlight, center glyph,
  and angle indicator use `MAYNTheme` colors and `MAYNMotion`/`MAYNMotionBridge` durations
  and timing — no Loop palette, no `.smooth(duration:)`, no raw springs.
- The same `RadialMenuView` + view model are mounted inside Settings with
  `isSettingsPreview == true` for the live preview (mirrors Loop's reuse rationale in
  `RadialMenuViewModel.swift:13-27`).

### 3.3 Preview overlay

- Screen-sized borderless non-activating `NSPanel`, one window level **below** the radial
  menu (Loop `PreviewController.swift:56` uses `screenSaver.rawValue - 1`; we use the MAYN
  HUD level minus one), `ignoresMouseEvents = true`, `hasShadow` false.
- Draws the resolved target frame as a rounded rect, reusing the visual language already
  approved for the drag overlay (`WindowSnapOverlayPanel` → `WindowSnapOverlayView`,
  black fill + light-gray border, corner radius from `WindowSnapOverlayPresentation`).
  This keeps one consistent "where the window will land" affordance across drag-snap and
  radial selection and avoids inventing a second overlay style.
- The preview rect animates between selections using `MAYNMotionBridge` durations/timing,
  not Loop's `AnimationConfiguration`.
- **The preview frame is supplied by the read-only resolver (§6), never recomputed in the
  view.** This is the anti-drift guarantee.

### 3.4 Selection modes

Both modes converge on "set `currentAction` to one of the 15 `WindowAction` cases, or nil":

- **Keyboard (ships first).** A local `NSEvent` key monitor active only while the trigger
  is held. Arrow keys / paired directional keys map to the directional actions; modifier
  combos or a center key map to maximize/almost-maximize/center; dedicated keys map to
  next/previous display and restore. Esc cancels.
- **Cursor angle/distance.** Port the geometry from Loop's
  `MouseInteractionObserver.swift:116-167`: compute `angleToMouse` and `distanceToMouse`
  from the initial cursor position; below `noActionDistance` → center/no-selection band;
  beyond the directional threshold → bucket the normalized angle into the directional
  segment count. We keep the math and the edge-clamping compensation
  (`computeLatestMousePosition`, `:177-214`) but **swap the event plumbing** for a MAYN
  `PassiveEventMonitor`-equivalent (a local `NSEvent.mouseMoved` monitor scoped to the held
  trigger). We drop Loop's cycle/left-click-advance branch (`:216-231`) entirely — MAYN has
  no cycle actions.

Segment count and angle spans derive from the hardcoded MAYN radial layout (§5), not from
Loop's `RadialMenuAction.userConfiguredActions`.

### 3.5 Settings live preview

The Settings page for this feature renders a non-interactive `RadialMenuView`
(`isSettingsPreview == true`) that animates through a few representative actions so the user
sees the look before enabling it. No panel, no event monitors — pure SwiftUI inside the
settings layout, using `MAYNSection`/`MAYNSettingsRow` chrome.

---

## 4. Architecture & components

All new files live under `MacAllYouNeed/WindowControl/Radial/` unless noted. Ported views
are **re-implemented against MAYN tokens**, not copied.

### 4.1 RadialMenuController / RadialMenuView / RadialMenuViewModel

- `RadialMenuController` (port of Loop `RadialMenuController.swift`): owns the radial
  `NSPanel` via `NonActivatingFloatingPanelController<RadialMenuView>`; `open(...)`,
  `update(...)`, `close()`. Strips `Defaults`, `Scribe`, `@Loggable`, `ActivePanel`. Uses
  MAYN HUD layering and `MAYNMotionBridge` for fade in/out (same pattern as
  `WindowSnapOverlayPanel.swift:114-126`).
- `RadialMenuView` (port of Loop `RadialMenuView.swift` + `RadialLayout`,
  `DirectionSelectorCircleSegment`, `DirectionSelectorSquareSegment`): SwiftUI radial
  layout + animated direction selector. Re-skinned: every color → `MAYNTheme`, every
  animation → `MAYNMotion.animation(_:reduceMotion:)`.
- `RadialMenuViewModel` (port of Loop `RadialMenuViewModel.swift`): `@Published`
  `currentAction: WindowAction?`, animated `angle: Double`, `isShown`, `isSettingsPreview`.
  Drops `parentAction`/cycle logic, `Window`, and `ResizeContext`. Angle computation keeps
  the "index × span − 90°" formula (`RadialMenuViewModel.swift:128-137`) but over the
  hardcoded MAYN directional layout.

### 4.2 PreviewController / PreviewView / PreviewViewModel

- `RadialPreviewController` (port of Loop `PreviewController.swift`): screen-sized panel,
  level below the radial menu, `setFrame(screen.frame)`, re-skinned dismiss timing.
- `RadialPreviewView` / `RadialPreviewViewModel`: draws the resolved target frame. The view
  model holds the **resolved `CGRect` from the read-only resolver** plus `isShown`; it does
  not own a `WindowAction` resolver of its own.

### 4.3 RadialMenuCoordinator (analogue of LoopManager, minimal)

A `@MainActor` `@Observable` (matching `WindowControlCoordinator`'s style) that owns the
lifecycle. Responsibilities, distilled from `LoopManager.openLoop`/`changeAction`/
`closeLoop` but stripped to the essentials:

- `open()` — capture focused-window identity, current frame, initial cursor position, and
  the locked target screen; set `currentAction = nil`; show both overlays.
- `update(action:)` — set `currentAction`, ask the read-only resolver for the preview
  `CGRect`, push the action to `RadialMenuViewModel` and the rect to `RadialPreviewViewModel`.
- `commit()` — if `currentAction != nil`, call
  `windowControlCoordinator.perform(action: currentAction)` exactly once, then dismiss.
- `cancel()` — dismiss both overlays, mutate nothing.

It owns the `RadialMenuController` and `RadialPreviewController` (the MAYN analogue of Loop's
`WindowActionIndicatorService.swift:12-35`, which we fold into the coordinator rather than a
separate service). It does **not** own the event tap; the tap drives it (§4.4). It holds no
`ResizeContext`, no `WindowActionCache`, no updater, no haptics config.

### 4.4 Integration into WindowControl

- `WindowControlEventTap` gains a radial-trigger state, fed by the same runtime flags it
  already receives via `updateRuntime(...)`
  (`MacAllYouNeed/WindowControl/WindowControlEventTap.swift:65-80`). A new
  `radialMenuEnabled` runtime flag joins `layoutsRuntimeEnabled`/`grabRuntimeEnabled`.
- The trigger is a held key. Because the existing tap only subscribes to mouse +
  recovery masks (`WindowControlEventTap.swift:98-106`), enabling the radial feature must
  **add `keyDown`/`keyUp`/`flagsChanged` to the event mask** (a held modifier-only trigger
  uses `flagsChanged`; a held key uses `keyDown`/`keyUp`). This is the one mask change.
- The tap forwards radial intents to `RadialMenuCoordinator` via a closure pair set the same
  way the snap overlay closures are injected today
  (`WindowControlCoordinator.swift:110-119`, `WindowControlEventTap.setSnapOverlay`). The
  coordinator constructs and wires the `RadialMenuCoordinator`, analogous to how it
  constructs `WindowSnapOverlayPanel` today.
- Commit calls `WindowControlCoordinator.perform(action:)`
  (`WindowControlCoordinator.swift:202`), reusing all of its guards: layouts-runtime gate,
  AX trust, hotkey-recording suspension, ignored-app suspension, and movement recording
  (`:202-235`). The radial path therefore inherits ignored-app and restore-history behavior
  for free.

Component ownership summary:

```
WindowControlCoordinator (existing)
 ├─ WindowControlEventTap (existing; +radial trigger detection, +key mask)
 │     └─ forwards open/update/commit/cancel ──▶ RadialMenuCoordinator
 ├─ RadialMenuCoordinator (new, thin)
 │     ├─ RadialMenuController ──▶ RadialMenuView / RadialMenuViewModel
 │     ├─ RadialPreviewController ──▶ RadialPreviewView / RadialPreviewViewModel
 │     ├─ cursor selection monitor (Loop MouseInteractionObserver math, MAYN plumbing)
 │     ├─ keyboard selection monitor (local NSEvent)
 │     └─ frame resolver (read-only, §6)
 └─ perform(action:) ◀── commit
```

---

## 5. Action mapping (Loop zones → MAYN.WindowAction)

The radial layout is **hardcoded** to MAYN's 15 cases
(`Shared/Sources/Core/WindowControl/WindowAction.swift:4-17`). Eight directional segments
form the ring; non-directional actions occupy the center band and dedicated keys. Loop zones
with no MAYN equivalent are dropped (non-goal: extending the vocabulary).

| Radial position / Loop concept              | Loop direction (approx.)        | MAYN.WindowAction      |
| ------------------------------------------- | ------------------------------- | ---------------------- |
| Ring W                                      | `.leftHalf`                     | `.leftHalf`            |
| Ring E                                      | `.rightHalf`                    | `.rightHalf`           |
| Ring N                                      | `.topHalf`                      | `.topHalf`             |
| Ring S                                      | `.bottomHalf`                   | `.bottomHalf`          |
| Ring NW                                     | `.topLeftQuarter`               | `.topLeft`             |
| Ring NE                                     | `.topRightQuarter`              | `.topRight`            |
| Ring SW                                     | `.bottomLeftQuarter`            | `.bottomLeft`          |
| Ring SE                                     | `.bottomRightQuarter`           | `.bottomRight`         |
| Center band (full)                          | `.maximize`                     | `.maximize`            |
| Center band (inset) / key                   | `.almostMaximize` (no native)   | `.almostMaximize`      |
| Center band (centered) / key                | `.center`                       | `.center`              |
| Dedicated key                               | `.nextScreen`                   | `.nextDisplay`         |
| Dedicated key                               | `.previousScreen`               | `.previousDisplay`     |
| Dedicated key (Esc-adjacent / restore key)  | `.initialFrame` / undo          | `.restore`             |
| No-selection band (< `noActionDistance`)    | `.noSelection`                  | `nil` (no commit)      |

Dropped Loop zones (not mapped): thirds, two-thirds, custom percentages, `.smaller`/
`.larger` nudges, `.cycle`, `.stash`, directional **window-focus** actions, and `.center`
with size manipulation. Directional segments occupy the ring; maximize/almost-maximize/
center share the center band keyed off cursor distance (Loop's `noActionDistance` vs
`directionalActionDistance`, `MouseInteractionObserver.swift:14-15`); display/restore are
keyboard-only to keep the ring uncluttered at 8 segments.

---

## 6. Integration seams (real file:line refs)

### 6.1 Commit seam — `perform(action:)`

- `WindowControlCoordinator.perform(action:)` —
  `MacAllYouNeed/WindowControl/WindowControlCoordinator.swift:202`. The radial commit calls
  this with the selected `WindowAction`. All guards and movement recording at `:202-235`
  apply unchanged.
- The underlying protocol seam:
  `WindowControlActionPerforming.perform(_:restoreFrame:)` —
  `WindowControlCoordinator.swift:18` (declared at protocol `:15-19`, implemented by
  `WindowKeyboardActionPerformer.perform` `:338-356`). We do **not** call this directly;
  going through the coordinator keeps restore-history and identity bookkeeping intact.

### 6.2 Read-only frame resolver (anti-drift)

The preview must match the committed result exactly. The frame logic lives in two pure,
already-side-effect-free places:

- `WindowGeometryCalculator.rect(for:visibleFrame:currentSize:)` —
  `Shared/Sources/Core/WindowControl/WindowGeometryCalculator.swift:11`. Pure; returns the
  target rect for half/quarter/maximize/almost-maximize/center.
- For `.nextDisplay`/`.previousDisplay`/`.restore`, the resolution lives in
  `WindowMover.targetFrame(...)` (`Shared/Sources/Platform/WindowControl/WindowMover.swift:188-234`)
  and the restore-history lookup
  (`WindowControlCoordinator.swift:227`, `restoreHistory.restoreFrame(for:)`).

**Proposed seam:** add a single read-only entry point that returns the *proposed* frame for
an action against the focused window — without writing. Two viable shapes:

1. A `resolveProposedFrame(for action: WindowAction) -> CGRect?` on
   `WindowControlActionPerforming` (default-implemented in `WindowKeyboardActionPerformer`),
   which reuses `WindowMover.targetFrame(...)` by exposing it (or a thin
   `WindowMover.proposedFrame(for:element:previousResult:)` that returns `proposedFrame`
   without calling `moveValidated`). `WindowControlCoordinator` exposes
   `proposedFrame(for:)` that the `RadialMenuCoordinator` calls on each `update`.
2. If display/restore previews are deferred to a later phase, the resolver can call
   `WindowGeometryCalculator.rect(...)` directly for the on-screen cases and return `nil`
   for `.nextDisplay`/`.previousDisplay`/`.restore` (preview simply not shown for those).

Either way, the resolver is **read-only** and shares `WindowMover`'s code path so the
preview can never disagree with the commit. The preview frame is then converted to AppKit
coordinates exactly as the snap overlay does today
(`WindowControlEventTap.appKitOverlayFrame(for:screenID:)`,
`WindowControlEventTap.swift:373-384`, via
`WindowScreenDetector.convertCGDisplayRectToAppKitCoordinates`).

### 6.3 Overlay panel pattern to mirror

- `WindowSnapOverlayPanel` —
  `MacAllYouNeed/WindowControl/WindowSnapOverlayPanel.swift` (panel construction `:44-67`,
  show/animate `:70-126`, view `:129-141`). Both new controllers follow this exact pattern:
  `NonActivatingFloatingPanelController`, `FloatingHUDWindowLayering`, `MAYNMotionBridge`
  fades, `ignoresMouseEvents`.

### 6.4 Event tap extension point

- `WindowControlEventTap.updateRuntime(...)` — `WindowControlEventTap.swift:65-80` (add
  `radialMenuEnabled`).
- Event mask — `WindowControlEventTap.swift:98-106` (add key/flags events when radial is on).
- Closure injection precedent —
  `WindowControlEventTap.setSnapOverlay(show:hide:)` `:86-92`, wired in
  `WindowControlCoordinator.swift:110-119`. Radial intents are wired the same way.
- The synthetic-event marker and recovery handling
  (`WindowControlEventTap.swift:137-151`) are reused; radial key handling must respect the
  same early-outs.

### 6.5 Settings store / view

- Toggle persisted in `WindowControlSettings`
  (`Shared/Sources/Core/WindowControl/WindowControlSettings.swift:3-46`) as a new
  `radialMenuEnabled: Bool = false` (and any sub-options: lock-to-center, preview-visible,
  cursor-selection-enabled), loaded/saved by
  `WindowControlSettingsStore` (`MacAllYouNeed/WindowControl/WindowControlSettingsStore.swift:7,21`).
  Adding a field with a default keeps existing decoded payloads valid.
- UI added to `WindowControlSettingsView`
  (`MacAllYouNeed/WindowControl/WindowControlSettingsView.swift`) under a new
  `WindowControlSettingsScope` case (e.g. `.layoutsRadial`), rendered with `MAYNSection` /
  `MAYNSettingsRow` and hosting the live preview.

---

## 7. Permissions

No new permissions. The held-trigger key interception and the AX window writes both run
inside the existing Window Control surface, which already requires and holds **Accessibility**
(`AXIsProcessTrusted()`, gated in `WindowControlCoordinator` via `axTrusted`,
`WindowControlCoordinator.swift:106,123,180-187`). The radial path inherits the same
`needsAccessibility` state and never arms when AX is untrusted (the tap's runtime gate at
`WindowControlEventTap.swift:178-187`). No microphone, screen recording, or input-monitoring
prompt is introduced — the CGEvent tap already in use covers key events.

---

## 8. UI / UX

### 8.1 Overlays

- **Radial menu:** compact pill-free disc at cursor (or locked center). Eight directional
  segments around a center band; the selected segment and the animated angle indicator are
  the only highlighted elements. Center glyph reflects the current action's SF Symbol
  (`WindowAction.symbolName`, `WindowAction.swift:52`).
- **Preview:** translucent rounded rectangle at the resolved target frame, matching the
  existing drag-snap overlay so the two affordances read as one system.

### 8.2 MAYNTheme re-skin (hard requirement)

Ported Loop views must be genuinely restyled, per `MacAllYouNeed/CLAUDE.md` and `design.md`:

- Colors: `MAYNTheme.*` only. No `Color(red:green:blue:)`, no Loop accent palette. The
  preview overlay's documented black/light-gray exception
  (`WindowSnapOverlayPresentation`) may be reused since the preview shares that visual; the
  radial menu uses standard `MAYNTheme` surface/border/accent tokens.
- Motion: `MAYNMotion.animation(_:reduceMotion:)` and `MAYNMotionBridge.effectiveDuration`/
  `timingFunction` (`MacAllYouNeed/Settings/MAYN/MAYNTokens.swift:39-131`). No
  `.smooth(duration:)`, `.easeInOut(duration:)`, or raw `.spring(...)` — Loop's
  `RadialMenuViewModel.swift:93,123` springs/linear are replaced.
- Fonts/dividers/inputs in the Settings surface follow the `MAYN*` component table.
- Segmented choices in Settings use `FunctionSegmentedTabStrip`, never
  `.pickerStyle(.segmented)`.

### 8.3 Settings toggle + live preview

A "Radial window menu" toggle (off by default) in the Window Layouts settings. Below it, the
live `RadialMenuView(isSettingsPreview: true)` animates through a few actions. Sub-options
(lock to center, show preview, cursor selection) appear only when the toggle is on.

### 8.4 Reduce Motion

Every radial angle tween, segment highlight, and preview-rect move routes through
`MAYNMotion.animation(_:reduceMotion:)` / `MAYNMotionBridge.effectiveDuration(_:)`, which
collapse to zero duration under Reduce Motion (`MAYNTokens.swift:104-117`). Under Reduce
Motion the overlays still appear and update — they just snap instead of animate, matching
`WindowSnapOverlayPanel`'s `respectsReduceMotion` behavior.

---

## 9. Edge cases & error handling

- **Held-trigger vs modifier-drag grab.** The grab path keys off mouse-down with a held
  drag modifier (`WindowControlEventTap.handleMouseDown`, `:167-247`); the radial trigger is
  a key/flags event. They must not collide: (a) the radial trigger key should not be a bare
  modifier already used by grab/edge-snap/double-click
  (`WindowControlSettings.dragModifier`/`edgeSnapModifier`/`doubleClickModifier`); the
  Settings UI must validate against reuse. (b) While the radial trigger is held,
  `flagsChanged`/`keyDown` handling must not perturb the existing mouse gesture state
  machine — radial key handling returns early before reaching `handleMouseDown`. (c) If a
  mouse gesture is already active (`gestureMode != .none`), opening the radial menu is
  suppressed.
- **Preview/commit drift.** Eliminated by §6.2: preview frame and commit frame come from the
  same `WindowMover` resolution. A regression test asserts equality (see §10).
- **Multi-display.** The target screen is locked at `open()` (Loop's `screen`-in-context
  idea, our locked `targetScreen`), so cursor drift to another display does not move the
  overlays mid-selection. `.nextDisplay`/`.previousDisplay` previews (if shown) resolve on
  the destination screen via `WindowMover.targetFrame` (`WindowMover.swift:208-226`).
  AppKit/CG coordinate conversion uses the existing
  `convertCGDisplayRectToAppKitCoordinates` helper so overlays land correctly on non-primary
  displays.
- **No focused window.** If no supported window is focused at `open()`, the radial menu still
  shows (cursor-anchored) but the preview is suppressed and commit is a no-op (the existing
  `perform` path resolves `nil` and records nothing, `WindowControlCoordinator.swift:226-234`).
  This mirrors Loop's exclamation-triangle empty state (`RadialMenuViewModel.swift:75-76`),
  re-skinned.
- **Ignored / fixed-size / unsupported windows.** Inherited from `perform`/`WindowMover`
  (`unsupportedWindow`, `fixedSizeWindow`, ignored-app suspension). The preview should not
  draw for windows the resolver returns `nil` for.
- **AX trust lost / hotkey recording / feature disabled mid-hold.** The tap's runtime gates
  (`WindowControlEventTap.swift:178-187`) and coordinator suspension
  (`WindowControlCoordinator.swift:189-200`) cancel the radial session; `cancel()` dismisses
  overlays.
- **Tap recovery.** On `tapDisabledByTimeout`/`tapDisabledByUserInput`
  (`WindowControlEventTap.swift:137-147`), any in-flight radial session is cancelled along
  with the gesture.
- **Rapid re-trigger / double open.** `RadialMenuCoordinator` ignores `open()` while already
  open (it just continues updating), echoing Loop's `isLoopActive` guard
  (`LoopManager.swift:163-173`) without the Karabiner-specific complexity.
- **Toggle off mid-session.** Settings change → `applySettings` → runtime update → cancel.

---

## 10. Testing strategy

- **Action mapping (unit).** Table-driven test asserting each ring segment index and each
  keyboard key resolves to the expected `WindowAction`, and the no-selection band resolves
  to `nil`. Pure, no AppKit.
- **Angle/distance selection (unit).** Port Loop's `MouseInteractionObserver` math into a
  pure helper and test angle→segment bucketing and the `noActionDistance`/
  `directionalActionDistance` bands, including the edge-clamp compensation. No event monitor
  needed.
- **Preview/commit parity (unit, critical).** For each on-screen action and a fixed
  visible-frame/window-size, assert the read-only resolver's `CGRect` equals
  `WindowMover.move(...).proposedFrame` (use a fake `WindowMovableElement`, as existing
  `WindowControlPresentationTests`/mover tests do). This is the anti-drift guard.
- **Coordinator lifecycle (unit).** With a fake `WindowControlCoordinator`/action performer,
  assert: `open` shows overlays with nil action; `update` resolves a frame and pushes it;
  `commit` calls `perform(action:)` exactly once with the selected action; `cancel` calls it
  zero times.
- **Event-tap gating (unit).** Assert the key/flags mask and radial trigger detection are
  only armed when `radialMenuEnabled` is true and AX is trusted, and that mouse-gesture
  handling is unchanged when radial is off (no behavioral diff vs today).
- **Settings round-trip (unit).** `WindowControlSettings` encode/decode preserves
  `radialMenuEnabled` and sub-options; an old payload without the field decodes to default
  `false`.
- **Manual / Reduce Motion.** Run the held-trigger flow on single and dual displays; toggle
  System Settings → Accessibility → Display → Reduce Motion and confirm overlays snap, not
  animate. Confirm grab/edge-snap/double-click still work with radial on.

---

## 11. Risks & mitigations

- **Key-event interception breaking other apps.** Adding key events to the session tap is
  the riskiest change. Mitigation: only add the mask when `radialMenuEnabled`; the radial
  key handler passes through every event it doesn't own (returns the original event,
  matching the tap's existing default-return discipline); never swallow the trigger key from
  apps when the feature is off.
- **Trigger collision with existing gesture modifiers.** Mitigation: Settings validates the
  trigger against `dragModifier`/`edgeSnapModifier`/`doubleClickModifier`; default trigger is
  a key not already bound.
- **Preview/commit drift creeping back.** Mitigation: single shared resolver (§6.2) + parity
  test (§10). Reviewers reject any preview that recomputes frames in the view layer.
- **Re-skin shortfall (copy-paste Loop look).** Mitigation: `swiftlint --strict` blocks raw
  colors/animations; `design.md §13` checklist; the spec mandates `MAYNTheme`/`MAYNMotion`.
- **Cursor edge-clamping math regressions on notched/multi-display setups.** Mitigation:
  ship keyboard selection first; gate cursor selection behind its own sub-toggle; cover the
  clamp math with unit tests before enabling by default.
- **Scope creep toward Loop's engine.** Mitigation: the non-goals are explicit; the only
  output of the UI layer is `(WindowAction, CGRect)`.

---

## 12. Open questions

1. **Trigger key choice.** A held bare modifier (e.g. a configurable single modifier via
   `flagsChanged`) vs a held non-modifier key (via `keyDown`/`keyUp` with auto-repeat
   filtering)? The former is more Loop-like; the latter avoids modifier collisions. Default
   proposal: a single configurable trigger key, modifier-only allowed but validated against
   existing gesture modifiers.
2. **Display/restore previews.** Ship `.nextDisplay`/`.previousDisplay`/`.restore` as
   keyboard-only with no preview in v1 (resolver returns `nil`), or invest in cross-display
   preview rendering immediately?
3. **Lock-to-center default.** Cursor-anchored (Loop default) vs locked center for a calmer,
   more predictable surface in a productivity app?
4. **FeatureDescriptor granularity.** A standalone "Radial Window UI" feature card, or a
   sub-capability of the existing Window Layouts feature? (Affects Dashboard lifecycle UI.)
5. **Cursor selection in v1.** Ship behind a sub-toggle defaulting off until the
   angle/clamp math is field-tested, or on by default once unit-tested?
6. **Should the preview reuse the exact `WindowSnapOverlayPresentation` constants**, or get a
   distinct (still MAYN-tokenized) treatment so users can tell drag-snap from radial-commit
   apart?
