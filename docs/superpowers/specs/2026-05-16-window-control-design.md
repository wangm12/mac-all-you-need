# Window Control Design Spec

**Status:** Review-hardened draft approved in chat on 2026-05-16
**Owner:** mingjie-father
**Project:** mac-all-you-need

---

## 1. Problem

Mac All You Need already helps with clipboard recall, folder preview, media downloads, snippets, and voice input. Window movement is still left to macOS title bars or third-party utilities. The target feature is a native window-control subsystem that lets users move and snap windows quickly without leaving MAYN or installing a separate window manager.

The feature should combine the strongest parts of AnyDrag and Rectangle without importing their product model:

- AnyDrag's useful idea: modifier-drag any visible part of a window with native-feeling movement.
- Rectangle's useful idea: mature window action geometry, restore history, app ignore behavior, and debug-friendly movement.

## 2. Product Principle

Window Control is a MAYN workflow, not an embedded clone of a window manager. It must live beside existing tools, use the shared MAYN UI language, and keep all user-facing keyboard shortcuts and gesture modifiers configurable.

The user model should stay simple:

```text
Main sidebar = product tools
Windows page = status, actions, gestures, settings
Windows settings = shortcut editing, gesture modifiers, snapping, ignored apps, diagnostics
Global Hotkeys settings = grouped secondary view of the same app hotkey store
Accessibility = one shared macOS permission for paste, snippets, voice, and windows
```

The main app must remain non-sandboxed for this feature. `MacAllYouNeed.entitlements` currently does not enable `com.apple.security.app-sandbox`, which is a load-bearing precondition for the active event tap. Any future sandboxing work must re-evaluate Window Control before shipping.

## 3. Source Research Decisions

### 3.1 AnyDrag

Use AnyDrag as behavioral inspiration only. Its README declares GPL-3.0, so direct source import is not acceptable unless the app distribution strategy becomes GPL-compatible. AnyDrag also has recent release-note evidence around event-tap and Accessibility revocation fragility, including prior system-wide click freezes. Those are design risks to avoid, not code to copy.

### 3.2 Rectangle

Use Rectangle as the preferred reference for geometry and AX behavior because it is MIT licensed and has a much larger window-management surface. Still, do not copy its entire feature set. Rectangle has known edge-case caveats around drag snapping, other window managers, Notification Center, Stage Manager, and app-specific failures.

### 3.3 Implementation License Rule

The default implementation path is clean-room for AnyDrag-style drag behavior, with optional MIT-compatible Rectangle-derived code only where attribution is retained and the code fits MAYN architecture. Clean-room tests must assert user-observable behavior on fake windows and events, not a source-level event rewrite sequence copied from AnyDrag.

## 4. Information Architecture

### 4.1 Main App

Add a first-level product destination:

- Dashboard
- Clipboard
- Voice
- Downloads
- Folder Preview
- Snippets
- Windows

Insert Windows after Snippets in `MainAppDestination.primarySidebarDestinations` and before Settings in the sidebar model. The Windows page uses the same `FunctionPageShell` and `FunctionSegmentedTabStrip` pattern as other tool pages.

### 4.2 Windows Child Tabs

Windows child tabs:

- Overview: feature status, Accessibility state, enabled state, active modifier summary, shortcut coverage, quick enable/disable.
- Actions: compact list of supported keyboard-triggered window actions and their current shortcuts, with edit affordances that route to the Windows Settings shortcut editor.
- Gestures: drag-anywhere, edge snap, double-click, and optional panel gesture behavior.
- Settings: editable shortcut rows, feature settings, gesture modifiers, ignored apps, diagnostics, and reset controls.

Shortcut editing belongs in the Windows tool's Settings tab to match MAYN's rule that function pages may display shortcuts but editing lives in each tool's Settings page. Global Settings -> Hotkeys may expose the same actions in grouped form, but it must not be the only place to edit window shortcuts.

Do not add a new standalone Settings-window tab for Windows in the MVP. Window Control settings live in the Windows product page. If a deep link is needed, route it by selecting `MainAppDestination.windows` and `WindowControlFunctionTab.settings`, not by adding `SettingsDestination.windows`.

## 5. Feature Scope

### 5.1 MVP

- Feature disabled by default.
- Enable/disable Window Control globally.
- Configurable keyboard shortcuts for all MVP window actions.
- Configurable gesture modifiers for drag-anywhere and snap behavior.
- Modifier-drag any visible part of a normal window.
- Modifier double-click maximize/restore, if enabled.
- Edge/corner snap preview and snap on release.
- Restore previous frame.
- Ignored apps list.
- Diagnostics: title-bar Y offset, event-tap status, last movement result, debug logging toggle.
- Keyboard actions target the focused/frontmost normal window and use that window's current display. Pointer gestures use the cursor's current display.

MVP window actions:

- Left half
- Right half
- Top half
- Bottom half
- Top left
- Top right
- Bottom left
- Bottom right
- Maximize
- Almost maximize
- Center
- Restore
- Next display
- Previous display

`Almost maximize` means 90 percent of the target visible frame, centered. `Next display` and `Previous display` preserve the current frame's normalized position and size within the source visible frame, then clamp to the target visible frame.

Default keyboard shortcuts should be useful without capturing keys while the feature is off. Window action shortcuts are stored in the hotkey map by default, but only registered while Window Control is enabled:

- Left half: Control + Option + Left Arrow
- Right half: Control + Option + Right Arrow
- Top half: Control + Option + Up Arrow
- Bottom half: Control + Option + Down Arrow
- Maximize: Control + Option + Return
- Center: Control + Option + C
- Restore: Control + Option + R
- Corners, almost maximize, next display, and previous display: visible but disabled by default

Discoverability for existing users comes from the Dashboard tile and the new Windows sidebar destination. The Dashboard tile should announce the feature with a concise disabled/needs-access state and route to Windows -> Overview; do not add a separate onboarding wizard for MVP.

### 5.2 Deferred

- Thirds, sixths, eighths, ninths, twelfths, sixteenths.
- Multi-window tile all / cascade all.
- URL command scheme.
- Menu-bar-only command palette.
- User-defined snap-zone editor.
- Per-app action remapping.
- AnyDrag-style right-click panel unless MVP quality is already stable.

## 6. Configurability

### 6.1 Keyboard Shortcuts

Every keyboard-triggered window action must be configurable through the existing hotkey UI model. No keyboard shortcut may be hardcoded as the only path.

The current V2 hotkey model treats missing or empty descriptors as default restoration. V3 must make disabled shortcuts possible without breaking existing users:

```text
V2 missing action key = use product default
V2 present empty descriptor array = migrate to product default for legacy actions
V3 missing action key = use product default
V3 present empty descriptor array = action disabled
V3 present non-empty descriptor array = explicit shortcuts
```

This requires `HotkeyMapStore` V3 before adding window actions. V3 applies to all `HotkeyAction` cases, but the forward migration must preserve the old V2 "empty means default" behavior for existing `.clipboard` and `.browseFolder` users.

`HotkeyAction` must no longer assume every action has exactly one non-optional default shortcut. Replace the current single `defaultDescriptor` contract with a multi-descriptor model such as:

```swift
var defaultDescriptors: [HotkeyDescriptor]
var primaryDefaultDescriptor: HotkeyDescriptor?
```

Legacy clipboard and folder actions keep one default descriptor. Window actions can have one default descriptor or no default descriptors when disabled by default.

### 6.2 Gesture Modifiers

Mouse gestures are not Carbon hotkeys and need separate settings:

- Drag-anywhere modifier combination.
- Edge-snap modifier requirement.
- Double-click modifier requirement.
- Optional middle/right gesture behavior if included later.

Gesture modifier options must support common modifier combinations, including Option, Command, Control, Shift, fn, and multi-modifier combinations. Default should be conservative and editable.

### 6.3 Conflict Rules

Keyboard shortcut validation must check:

- Existing app hotkeys.
- Voice activation shortcut.
- macOS symbolic hotkeys.
- Duplicate window action shortcuts.
- Only currently registered actions when checking runtime registration, while still validating saved conflicts in settings.

Gesture modifier validation must warn, not block, when a modifier is likely to conflict with system tiling or common app behavior. This is not the same validation model as keyboard shortcuts.

Hotkey settings must be grouped by feature, not rendered as one flat wall of rows. Conflict messages should name the feature and action, for example `Window Control: Left half`.

Validation should fetch macOS symbolic hotkeys once per settings/apply pass and pass that set through validation helpers. Hotkey-triggered window movement should begin within roughly 50 ms on normal hardware, so the hotkey fire path must avoid fresh settings loads, symbolic-hotkey fetches, or other expensive synchronous work.

## 7. UX And Visual Direction

### 7.1 Tone

Window Control should feel quiet, precise, and operational. It is a daily productivity surface, not a marketing page and not a decorative utility clone.

### 7.2 Layout

Use MAYN's existing product-page rhythm:

- Left app sidebar for first-level tool navigation.
- Tool page header with title, subtitle, status chip, and compact action.
- Shared segmented child tabs below the header.
- Dense sections and rows for settings.
- No nested cards.
- No oversized hero section.
- No raw `Picker(...).pickerStyle(.segmented)` for product-owned tabs or segmented choices.

### 7.3 Components

Required shared components:

- `FunctionPageShell`
- `FunctionSegmentedTabStrip`
- `MAYNSettingsPage`
- `MAYNSection`
- `MAYNSettingsRow`
- `MAYNDropdown`
- `MAYNButton`
- `ShortcutChip`
- `MAYNHotkeyDisplay`
- `StatusPill`
- `MAYNTheme`
- `MAYNControlMetrics`
- `MAYNMotion`
- `MAYNMotionBridge`

### 7.4 Snap Preview

Snap overlay should look like MAYN, not Rectangle or AnyDrag:

- Subtle accent fill using `MAYNTheme.progress` opacity.
- 1 px border from the same accent family.
- Radius aligned with `MAYNControlMetrics.panelRadius`.
- No glow-heavy treatment.
- No glassmorphism.
- No decorative blobs or gradients.
- Reduced Motion disables spatial animation.

Implementation should reuse the local floating HUD/panel patterns from `MiniVoiceHUD`, `CopyHUD`, and `FloatingHUDWindowLayering` rather than inventing a separate panel stack.

### 7.5 Copy

Use direct, compact labels:

- Window Control
- Drag windows from anywhere
- Snap by screen edge
- Restore previous frame
- Ignored apps
- Gesture modifier
- Needs Accessibility
- Disabled for this app
- Event tap active

Avoid long instructional copy on the main page. Use short settings subtitles and diagnostics details only where needed.

## 8. Architecture

### 8.1 Core

Create pure, testable code in `Shared/Sources/Core/WindowControl`:

- `WindowAction`
- `WindowControlSettings`
- `WindowGeometryCalculator`
- `WindowRestoreHistory`
- `WindowGestureModifier`
- `WindowSnapZone`

Core must not import AppKit-only event tap code beyond data types that are already acceptable in the `Core` target. If AppKit types create target pressure, use simple rect/screen value structs and bridge in Platform.

`WindowRestoreHistory` is in-memory and cleared on app quit. Key entries by a `WindowIdentity` built from PID plus CG window ID when available, with a fallback to PID plus a title hash and frame. Store the previous frame before keyboard actions and snap actions so Restore can return to the last user-visible frame.

### 8.2 Platform

Create macOS behavior in `Shared/Sources/Platform/WindowControl`:

- `WindowAccessibilityElement`
- `WindowScreenDetector`
- `WindowMover`
- `WindowTargetResolver`
- `WindowEventTap`
- `NativeTitleBarDragStrategy`

Platform owns AX calls, CGWindow list inspection, CGEvent tap lifecycle, and pointer-event handling.

`WindowScreenDetector` owns display selection. Keyboard actions use the current window's screen. Pointer gestures use the cursor screen. Next/previous display must be implemented as a display-aware geometry operation, not as a `nil` case in `WindowGeometryCalculator`.

### 8.3 App

Create app-level coordination in `MacAllYouNeed/WindowControl`:

- `WindowControlCoordinator`
- `WindowControlMainPage`
- `WindowControlSettingsView`
- `WindowSnapOverlayPanel`
- `WindowGestureModifierPicker`
- `WindowControlDiagnosticsView`

`WindowControlCoordinator` should mirror `VoiceCoordinator`'s lifecycle and integration style: `@MainActor`, `@Observable`, owned by `AppController`, started from `AppController.init`, and exposed through the AppController graph so SwiftUI overview/status UI updates without polling timers. It owns its settings application logic and supports `start`, `stop`, idempotent suspend/resume, and action dispatch.

`AppController` owns one `WindowControlCoordinator`, starts it after stored settings load, suspends it during hotkey recording, and stops/restarts it when settings or Accessibility state changes. Hook into the existing hotkey-recorder observers and `activeHotkeyRecorderCount` gate in `AppController`; do not introduce a second recorder counter inside Window Control. When suspended for hotkey recording, the coordinator must tear down the active event tap, not merely flip a boolean. Resume reinstalls the tap only when settings and Accessibility still allow it.

There is no central Accessibility trust observer today. Window Control should add a small feature-local trust monitor that checks `AXIsProcessTrusted()` on app activation/settings return and with a bounded timer while the feature is enabled and in `Needs Accessibility` or `Active`. The monitor starts the coordinator after a grant and tears it down after revoke.

## 9. Event-Tap Safety

The event tap is the highest-risk part. Requirements:

- Disabled by default.
- Start only when feature is enabled and Accessibility is trusted.
- This is an active tap using `kCGEventTapOptionDefault` / `.defaultTap`, not a listen-only tap.
- `SnippetExpander` is only a passive `.listenOnly` precedent; it is not the model for drag-anywhere input modification.
- `HotkeyRecorder` is the closer local precedent for active tap lifecycle, `tapDisabledByTimeout`, `tapDisabledByUserInput`, `CFRunLoopAddSource`, and `CGEvent.tapEnable`.
- Pass through all events when trust is uncertain.
- Tear down cleanly on Accessibility revoke.
- Retry only from the main actor lifecycle path.
- Avoid posting replay events from inside the tap callback.
- Log failures enough to diagnose "nothing happened" reports.
- Do not compete with hotkey recording; suspend while any hotkey recorder is active.
- The callback must not block on AX writes, wait on locks, perform disk I/O, fetch settings from storage, or allocate large objects.

The event tap may suppress an event only when this predicate is true at mouse-down time:

```text
feature enabled
AND Accessibility trusted
AND coordinator state is active
AND no hotkey recorder is active
AND configured drag/snap modifier mask is held
AND WindowTargetResolver returns a normal, non-MAYN window
AND frontmost app bundle ID is not ignored
```

Otherwise the original event must pass through unchanged. Returning `nil` from the callback swallows the event and is allowed only for this predicate; implement it as a single guardable expression in code, not spread across narrative branches.

`tapDisabledByTimeout` and `tapDisabledByUserInput` recovery is explicit: mark state `Error` or `Recovering`, surface the reason in diagnostics, re-enable from the main actor with bounded exponential backoff, and stop retrying after a fixed failure count until settings are toggled or the app restarts.

## 10. Data And Settings

Use App Group `UserDefaults` for settings, matching the rest of app behavior. Follow the Voice settings pattern: a Codable `WindowControlSettings` struct plus `WindowControlSettingsStore.load()` / `save()` static methods, persisted as one encoded payload. Do not scatter ad-hoc `AppGroupSettings.defaults.bool(forKey:)` reads across the codebase.

Persisted keys:

- `windowControl.settings.v1`
- `hotkeyMapV3`

`WindowControlSettingsStore.save()` should post the existing `com.macallyouneed.settings-changed` Darwin notification through the same helper pattern used elsewhere when settings affect long-running observers. The coordinator should also reload immediately through `AppController` when settings are applied in-process.

## 11. Key States

Overview states:

- Off: feature disabled, settings available.
- Needs Accessibility: enabled but cannot start.
- Active: event tap running.
- Suspended: hotkey recorder active or ignored app frontmost.
- Error: event tap failed to start or was disabled by timeout.
- Recovering: event tap was disabled and a bounded retry is scheduled.

Gesture states:

- Idle.
- Drag active.
- Snap candidate.
- Snap cancelled.
- Ignored app.
- No target window.

## 12. Acceptance Criteria

- Windows appears as a MAYN first-level tool.
- Window Control UI uses the shared MAYN design system.
- All keyboard shortcuts are configurable and can be disabled.
- Existing V2 hotkey users keep their clipboard and folder defaults after migration.
- Window shortcuts are editable from the Windows tool settings.
- All gesture modifiers are configurable.
- Feature starts disabled by default.
- Enabling with no Accessibility shows a clear Needs Accessibility state.
- Granting Accessibility after enabling starts Window Control without requiring app restart.
- Hotkey recording suspends Window Control by tearing down the active event tap.
- Modifier-drag moves a normal window smoothly.
- Modifier double-click toggles maximize/restore when enabled.
- Edge/corner snap preview matches final frame.
- Ignored apps suppress keyboard window actions and gestures for that app.
- Hotkey recording suspends Window Control gestures.
- Accessibility revoke never freezes input.
- Geometry tests cover visible frames, corners, restore, and multiple displays.
- Build and targeted tests pass.

## 13. Non-Goals

- No GPL source import.
- No separate preferences window.
- No duplicated design system.
- No hidden hardcoded shortcuts.
- No raw segmented picker for product tabs or segmented settings choices.
- No all-in-one huge `WindowControl.swift` file.
- Do not sandbox the main app without re-evaluating the active event tap.
