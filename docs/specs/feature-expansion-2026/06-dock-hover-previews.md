# Feature F — Dock-Hover Window Previews

Date: 2026-05-30
Status: Design draft (child of [`00-roadmap.md`](./00-roadmap.md))
Reference: `reference-projects/DockDoor-main`
Effort: M–L
New permission: Screen Recording (degrades to title-only when denied)

---

## 1. Summary

Dock-Hover Window Previews adds the DockDoor-style interaction to Mac All You
Need (MAYN): when the user hovers an app's Dock icon, a floating panel appears
beside that icon showing thumbnail previews of the app's open windows
(including minimized / hidden / off-Space windows). Clicking a thumbnail raises
and restores that specific window and activates its app. Optionally, previews
can be live (low-frame-rate streamed captures) instead of static thumbnails.

The feature is viable because the **main app is not sandboxed** (only the
`FolderPreview` Quick Look `.appex` is — confirmed in
[`00-roadmap.md`](./00-roadmap.md) §"Locked product decisions" #7), and MAYN
distributes via DMG + notarization + Sparkle, so there is **no Mac App Store
review constraint**. This unlocks the private SkyLight / CGS APIs DockDoor
relies on (`CGSHWCaptureWindowList`, `_SLPSSetFrontProcessWithOptions`,
`CGSCopySpacesForWindows`, `_AXUIElementGetWindow`).

It ships as its own gated `FeatureDescriptor` (dashboard card + onboarding +
enable/disable through `FeatureRuntime`), is **opt-in**, and **degrades
cleanly**: with Screen Recording denied it shows a title-only window list rather
than thumbnails; with Accessibility denied it does not run at all (Accessibility
is already held by MAYN's WindowControl / snippets subsystems).

It builds on the shared **S1 `AXObserverCoordinator`** utility
([`00-roadmap.md`](./00-roadmap.md) §S1) for robust observation of
`com.apple.dock`, and reuses MAYN's existing WindowControl AX-enumeration and
window-raise seams where practical.

---

## 2. Goals / Non-goals

### Goals

- Show a floating preview panel on Dock-icon hover, anchored to the hovered
  icon, MAYNTheme-styled, following the existing borderless-`NSPanel` + SwiftUI
  pattern (`WindowSnapOverlayPanel`).
- Enumerate **all** of an app's windows — on-screen via ScreenCaptureKit, plus
  minimized / hidden / off-Space via Accessibility — merged into a per-PID
  cache.
- Render static thumbnails by default (private `CGSHWCaptureWindowList`), with
  an **optional** live-preview mode (`SCStream` +
  `SCContentFilter(desktopIndependentWindow:)`).
- Click a thumbnail → raise + un-minimize + activate the exact window
  (SkyLight focus + AX `kAXMinimizedAttribute` restore + `app.activate()`).
- Filter by current Space / current monitor (private CGS), user-toggleable.
- Optional gesture extras: scroll-on-Dock-icon and click interception (off by
  default).
- First-class performance: launch-time seeding, concurrency-capped captures,
  thumbnail downscaling, cache lifespan.
- Graceful degradation when Screen Recording is denied (title-only list).
- Ship as an independent, opt-in, gated feature.

### Non-goals

- A Cmd-Tab / window-switcher replacement (DockDoor's `windowSwitcher` path).
  Only the **Dock-hover** surface is in scope for v1.
- Special-app Dock widgets (DockDoor's Calendar / Media-Remote widgets). Out of
  scope.
- The Dock click-to-hide / shift-click-new-window / cmd-right-click-quit
  behaviors are **off by default** and treated as an optional Phase 2 extra
  (see §3.7); v1 ships hover previews + click-to-raise only.
- Title-bar scroll gestures (maximize / center / move-across-Spaces). MAYN
  already owns window placement via WindowControl; we do not duplicate it here.
- Folder Dock-item previews.
- Any Mac App Store packaging. The feature deliberately depends on private APIs.

---

## 3. Full feature scope

### 3.1 Dock-hover observer

- Resolve `com.apple.dock` via
  `NSRunningApplication.runningApplications(withBundleIdentifier:"com.apple.dock")`,
  take its PID, build `AXUIElementCreateApplication(dockPID)`.
- Find the Dock's `AXList` child (role `kAXListRole`) and subscribe to
  `kAXSelectedChildrenChangedNotification` on it (this is how the Dock reports
  hover; see `DockObserver.setupSelectedDockItemObserver()`
  reference-projects/DockDoor-main/DockDoor/Utilities/DockObserver.swift:213).
- On notification, read the selected (hovered) dock item via
  `kAXSelectedChildrenAttribute`, confirm subrole `AXApplicationDockItem`, read
  `kAXURLAttribute` → `Bundle(url:)` → bundle id →
  `NSRunningApplication.runningApplications(withBundleIdentifier:)`
  (`DockObserver.getDockItemAppStatusUnderMouse()` reference line 595).
- A **health-check timer** re-subscribes when the Dock rebuilds its AX tree:
  the subscribed `AXList` element silently goes stale (Dock relaunch, display
  reconfig, Dock-pref change) and notifications stop. DockDoor polls every 5 s
  and validates the subscribed element with a `kAXRoleAttribute` read; on
  `.invalidUIElement` / `.cannotComplete` it tears down and re-subscribes
  (`DockObserver.performHealthCheck()` reference line 167). **In MAYN this
  observation + re-subscription is owned by the shared S1 `AXObserverCoordinator`**,
  not re-implemented locally.

### 3.2 Window enumeration

Two sources, merged per PID:

- **On-screen:** ScreenCaptureKit `SCShareableContent.current` →
  `SCWindow` list filtered by owning PID. Gives `windowID` (`CGWindowID`),
  geometry, title, on-screen flag.
- **Off-screen / minimized / hidden / off-Space:**
  `AXUIElementCreateApplication(pid).windows()` (AX) — AX is the only reliable
  source for minimized and other-Space windows that SCK omits.
- **Match AX ↔ SC** to dedupe: primary key is the `CGWindowID` obtained from an
  AX element via the private `_AXUIElementGetWindow(_:_:)`
  (PrivateApis.swift:17); fall back to title + geometry fingerprint when the
  window id is unavailable.
- Result merged into the per-PID window cache (§5). Each entry carries:
  `CGWindowID`, owning PID, AX element handle, title, frame, `isMinimized`,
  `isHidden`, space id(s), last-captured thumbnail + its timestamp.

### 3.3 Thumbnails (static)

- Default path: private `CGSHWCaptureWindowList(CGSMainConnectionID(), [wid], 1,
  options)` returning a `CGImage` per window
  (PrivateApis.swift:52). Options: `.bestResolution` + `.fullSize` (Stage
  Manager safe) + `.ignoreGlobalClipShape`, then **downscale** to the panel's
  thumbnail size before caching.
- Why private capture rather than `SCScreenshotManager`: it captures
  **minimized** and off-screen windows that SCK cannot, and is cheaper for
  one-shot stills. SCK is still used for live mode.
- Captured images are cached with a **lifespan** and refreshed on next hover
  after expiry (§5).

### 3.4 Live previews (optional)

- Behind a setting ("Live previews", default **off**). When on, each visible
  thumbnail in the panel starts an `SCStream` with
  `SCContentFilter(desktopIndependentWindow:)` for that `SCWindow`, at a low
  frame rate and reduced `width`/`height` in `SCStreamConfiguration`
  (mirrors `LiveWindowCapture.swift`).
- Hard cap: **≤ ~4 concurrent captures** (see `LimitedTaskGroup` in the
  reference). Streams start on appear and stop on disappear / panel dismiss.
- Live mode requires Screen Recording; with it denied, the toggle is disabled
  and the feature stays on static thumbnails / title-only.

### 3.5 Floating preview panel

- Borderless, non-activating `NSPanel` + SwiftUI content, reusing MAYN's
  `NonActivatingFloatingPanelController` + `FloatingHUDWindowLayering` from
  `WindowSnapOverlayPanel.swift` (styleMask `[.borderless, .nonactivatingPanel]`,
  HUD window level, fade in/out via `MAYNMotionBridge.effectiveDuration`).
- Unlike the snap overlay, **this panel accepts mouse events** (clickable
  thumbnails) — set `ignoresMouseEvents = false` and keep
  `hidesOnDeactivate = false`.
- Content: app name header + a horizontal (Dock-bottom) or vertical
  (Dock-left/right) strip of window cards. Each card = thumbnail (or title-only
  fallback) + window title + minimized/hidden badge. Styled entirely with
  `MAYNTheme` / `MAYNControlMetrics` / `MAYNMotion`.
- Positioning anchors to the hovered Dock item's screen rect and the Dock edge
  (`DockUtils.getDockPosition()` analog); panel is clamped to the Dock item's
  screen and offset toward screen interior. Cursor/Dock-item-screen lock is
  captured on first show and held for the hover lifecycle (mirrors MiniVoiceHUD
  `targetScreen`).
- Dismiss when the cursor leaves both the Dock item and the panel, on click, or
  on Dock-item change to a non-app item.

### 3.6 Raise / restore on click

On thumbnail click, raise that specific window:

1. If `isMinimized`: AX set `kAXMinimizedAttribute = false` on the window
   element to un-minimize.
2. If the app `isHidden`: `app.unhide()`.
3. SkyLight focus: `GetProcessForPID(pid, &psn)` then
   `_SLPSSetFrontProcessWithOptions(&psn, wid, SLPSMode.userGenerated)` plus a
   synthesized activation event via `SLPSPostEventRecordTo(&psn, &bytes)` — the
   byte-packed event record DockDoor uses to raise one specific window id
   (PrivateApis.swift:148/154). The SkyLight functions are `dlopen`-loaded from
   `/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight` lazily.
4. `app.activate()` as the final, public fallback.
5. AX `AXUIElementPerformAction(window, kAXRaiseAction)` is used as a
   public-API fallback path when SkyLight symbols fail to load.

Where the per-window AX raise + minimized-restore overlaps MAYN's existing
WindowControl logic, reuse the WindowControl element wrappers rather than
duplicating AX plumbing (§6).

### 3.7 Per-Space / multi-monitor filtering + gesture extras

- **Per-Space:** `CGSCopySpacesForWindows(cid, kCGSAllSpacesMask, [wids])` to map
  windows → spaces, and `CGSCopyManagedDisplaySpaces(cid)` to learn the current
  space per display; filter the panel to current-Space windows when
  "Current Space only" is on (PrivateApis.swift:61/69).
- **Per-monitor:** filter by the window frame's display vs. the hovered Dock
  item's display; `CGSGetWindowLevel` used to drop non-normal-level windows
  (panels, sheets) from previews.
- **Gesture extras (Phase 2, off by default):** a `CGEventTap`
  (`.cghidEventTap`, `tailAppendEventTap`) for scroll-on-Dock-icon (activate /
  hide app) and click interception. This mirrors `DockObserver.setupEventTap()`
  but is gated behind an explicit setting and is **not** part of v1's default
  behavior. If MAYN's WindowControl event tap is active, the two taps must
  coexist without double-handling (each filters by event type / cursor region).

---

## 4. Architecture & components

All new code lives under `MacAllYouNeed/DockPreviews/` (new directory) plus a
shared private-API module. Composition is wired through a feature activator from
`AppController`, exactly like WindowControl.

| Component | Responsibility | Modeled on |
|---|---|---|
| `DockHoverObserver` | Subscribe to Dock hover via **S1 `AXObserverCoordinator`**; resolve hovered `AXApplicationDockItem` → bundle id → `NSRunningApplication`; emit "hovered app changed" / "hover ended" events. | `DockObserver.swift` (hover-resolution parts only; observation lifecycle delegated to S1) |
| `DockPreviewWindowEnumerator` | Per-PID window discovery: SCK on-screen + AX off-screen, AX↔SC match via `_AXUIElementGetWindow`. | `WindowUtil.discoverWindowsViaAX` / `getActiveWindows` |
| `DockPreviewWindowCache` | Thread-safe per-PID `[pid_t: Set<WindowEntry>]` with diff-on-write. | `SpaceWindowCacheManager.swift` |
| `DockPreviewSeeder` | Launch-time seed of regular apps' windows into the cache (off main thread, concurrency-capped). | `WindowSeeder.swift` |
| `DockPreviewThumbnailService` | Static thumbnails via `CGSHWCaptureWindowList`; downscale; cache with lifespan; concurrency cap. | `WindowUtil` capture path |
| `DockPreviewLiveCaptureManager` | Optional `SCStream` live previews, ≤4 concurrent, start/stop on view appear/disappear. | `LiveWindowCapture.swift` / `LiveCaptureManager` |
| `DockPreviewPanel` | Borderless non-activating `NSPanel` + SwiftUI, anchored to Dock item, MAYNTheme-styled, click-to-raise, title-only fallback. | `WindowSnapOverlayPanel.swift`, `MiniVoiceHUD.swift` |
| `DockPreviewRaiseService` | Un-minimize (AX) + SkyLight focus + `app.activate()` + AX `kAXRaiseAction` fallback. | `WindowUtil` raise + PrivateApis SkyLight |
| `DockPreviewPrivateAPI` | One file wrapping all `@_silgen_name` CGS/SkyLight declarations + `dlopen` loader; the only place private symbols are declared. | `PrivateApis.swift` |
| `DockPreviewCoordinator` | `@MainActor @Observable` owner that wires observer → enumerator/cache → thumbnail/live → panel; holds settings; mirrors `WindowControlCoordinator`'s lifecycle (start/stop, AX-trust, suspend). | `WindowControlCoordinator.swift` |
| `DockPreviewsDescriptor` + `DockPreviewsFeatureActivator` | Gated feature registration, enable/disable, onboarding + settings factories. | `WindowGrabDescriptor.swift` + `WindowControlFeatureActivator` |
| `DockPreviewsSettingsStore` / `…SettingsView` | Persisted settings + tool-page settings UI. | `WindowControlSettingsStore` / `…SettingsView` |

`DockPreviewCoordinator` is a **static let** on `AppController` (per CLAUDE.md:
SwiftUI App structs may be recreated; the coordinator must be a single
instance). It owns no AX run-loop state directly — that belongs to S1.

---

## 5. Data model / caching

### Per-PID window cache

- Shape: `[pid_t: Set<WindowEntry>]` guarded by a lock, with add/remove/update
  diffing on write (`SpaceWindowCacheManager.writeCache` line 55 is the
  template). MAYN's variant does **not** need DockDoor's switcher-coordinator
  notifications — only the hover panel reads it — so the diff callbacks collapse
  to a single "cache changed for PID" signal the panel can re-read.
- `WindowEntry`: `windowID: CGWindowID`, `pid: pid_t`, `axElement`, `title`,
  `frame: CGRect`, `isMinimized`, `isHidden`, `spaceIDs: [CGSSpaceID]`,
  `lastAccessed: Date`.
- **Seeding:** at feature enable / app launch, `DockPreviewSeeder` enumerates
  `activationPolicy == .regular` apps (excluding MAYN itself) and populates the
  cache via AX so the first hover is instant (`WindowSeeder.run()` line 5).
- **Refresh:** on hover, the cache is shown immediately (stale-OK) and a
  concurrency-capped background refresh updates it, then the panel re-reads
  (DockDoor's "show cached, then `mergeWindowsIfNeeded`" pattern,
  DockObserver.swift:386–450).

### Thumbnail cache

- Keyed by `CGWindowID`. Stores the downscaled `CGImage` + capture timestamp.
- **Lifespan:** a configurable max age (default ~5 s); on hover, entries older
  than the lifespan are recaptured, newer ones are reused. Minimized windows
  keep their last good thumbnail until restored.
- Stored at thumbnail resolution only (post-downscale) to bound memory.

### Concurrency caps

- Static captures: bounded task group, default ≤ 4 in flight.
- Live streams: hard cap ≤ 4 concurrent `SCStream`s; streams stop on disappear.
- Seeder: bounded fan-out across apps so launch does not spike CPU.

---

## 6. Integration seams (real file:line refs)

MAYN seams to reuse / extend:

- **S1 `AXObserverCoordinator`** ([`00-roadmap.md`](./00-roadmap.md) §S1) —
  owns `AXObserverCreate` + run-loop source + notification registration + the
  health-check re-subscribe. `DockHoverObserver` consumes it; it does **not**
  re-implement the ad-hoc observer plumbing currently in WindowControl.
- **Coordinator lifecycle template** —
  `MacAllYouNeed/WindowControl/WindowControlCoordinator.swift:56` (`@MainActor
  @Observable`, `start()`/`stop()`/`reconcileLifecycle()`,
  `needsAccessibility` state, suspend semantics). `DockPreviewCoordinator`
  mirrors this state machine.
- **AX trust monitoring** —
  `MacAllYouNeed/WindowControl/WindowControlAccessibilityTrustMonitor.swift:1`
  (`didBecomeActive` + bounded polling, `shouldPoll` gating). Reused so the
  feature reacts when the user grants Accessibility without restart.
- **AX window resolution / raise** — the focused-window resolution and AX
  element wrapping in
  `MacAllYouNeed/WindowControl/WindowControlCoordinator.swift:358`
  (`resolveFocusedWindow()` / `WindowAccessibilityElement`) is the model for
  `DockPreviewRaiseService`'s minimized-restore + raise.
- **Borderless non-activating panel** —
  `MacAllYouNeed/WindowControl/WindowSnapOverlayPanel.swift:43`
  (`NonActivatingFloatingPanelController`, `FloatingHUDWindowLayering`,
  `MAYNMotionBridge` fades). `DockPreviewPanel` reuses this, with
  `ignoresMouseEvents = false`.
- **HUD screen-lock pattern** — `MiniVoiceHUD` `targetScreen` lock
  (`MacAllYouNeed/CLAUDE.md` §"Cursor-screen lock") for keeping the panel on one
  display for the hover lifecycle.
- **FeatureDescriptor** —
  `Shared/Sources/FeatureCore/FeatureDescriptor.swift:40`. Registration mirrors
  `MacAllYouNeed/App/Descriptors/WindowGrabDescriptor.swift:1`. **Requires
  enum extensions** (§7): `FeatureID` (`Shared/Sources/FeatureCore/FeatureID.swift:3`)
  has no dock-preview case, and `Permission`
  (`Shared/Sources/FeatureCore/FeatureDescriptor.swift:4`) has **no
  `screenRecording` case** today — both must be added.
- **Feature activator** —
  `MacAllYouNeed/WindowControl/WindowControlFeatureActivator.swift` is the
  template for `DockPreviewsFeatureActivator`.
- **Permission UI** — `MacAllYouNeed/Settings/PermissionsSettingsView.swift:8`
  (`PermissionDisplayState`, `PermissionStatusProvider`) and a new row modeled
  on `MacAllYouNeed/Settings/Permissions/AccessibilityPermissionRow.swift:1`
  (which wraps `PermissionCard`). A new `ScreenRecordingPermissionRow` is added
  here; Screen Recording state comes from `CGPreflightScreenCaptureAccess()`
  (the same call DockDoor uses,
  `…/PermissionsView/PermissionsChecker.swift:39`).
- **Onboarding** — `MacAllYouNeed/Onboarding/PermissionStepViews.swift` +
  `FeatureSetupPermissionsView.swift` provide the per-feature setup step the
  descriptor's `onboardingSetupFactory` returns.
- **Tool page** — new page via `FunctionPageShell`
  (`MacAllYouNeed/App/FunctionPageShell.swift`); per design rules the page is
  configuration/guidance + the toggle + permission status, not a browse surface.

Reference techniques (read-only, DockDoor):

- Dock observation + hover resolution + health check + (Phase 2) event tap:
  `reference-projects/DockDoor-main/DockDoor/Utilities/DockObserver.swift`.
- Private API declarations: `…/Utilities/PrivateApis.swift`.
- Window discovery + match + raise: `…/Utilities/Window Management/WindowUtil.swift`.
- Live capture: `…/Utilities/Window Management/LiveWindowCapture.swift`.
- Launch seeding: `…/Utilities/Window Management/WindowSeeder.swift`.
- Per-PID cache + diffing: `…/Utilities/Window Management/SpaceWindowCacheManager.swift`.
- Panel coordinator: `…/Views/Hover Window/Shared Components/SharedPreviewWindowCoordinator.swift`.
- Screen-recording preflight: `…/Components/PermissionsView/PermissionsChecker.swift`.
- Entitlements baseline: `…/DockDoor.entitlements`.

---

## 7. Permissions & entitlements

### Screen Recording (new)

- Required for thumbnails (`CGSHWCaptureWindowList`) and live previews
  (`SCStream`). Detected with `CGPreflightScreenCaptureAccess()`; requested with
  `CGRequestScreenCaptureAccess()` from the onboarding step.
- **No new entitlement key** is strictly required for Screen Recording (it is a
  TCC consent, not an entitlement) on a non-sandboxed app. What is needed is:
  the user-facing onboarding/permission flow, the `CGPreflight`/`CGRequest`
  calls, and graceful degradation when denied.
- Add `Permission.screenRecording` to
  `Shared/Sources/FeatureCore/FeatureDescriptor.swift:4`, and a matching
  `PermissionDisplayState` provider + `ScreenRecordingPermissionRow` in
  `PermissionsSettingsView.swift`.

### Accessibility (reuse)

- Already held by MAYN (WindowControl, snippets, CGEventTap). Used for the Dock
  AX observation, off-screen window enumeration, and minimized-window restore.
  No new prompt; reuse the existing Accessibility card and trust monitor.

### FeatureID

- Add a new case (e.g. `dockPreviews`) to
  `Shared/Sources/FeatureCore/FeatureID.swift:3` so the descriptor, persisted
  feature state, dashboard card, and sidebar destination can key off it.

### Private APIs / no App Store / sandbox note

- The feature uses private SkyLight/CGS symbols (`@_silgen_name` + lazy
  `dlopen`). This is acceptable **only because the main app is not sandboxed and
  is not App-Store-distributed** ([`00-roadmap.md`](./00-roadmap.md) #7).
- The main app's `MacAllYouNeed.entitlements` has **no sandbox key** (confirmed:
  it only declares App Groups, audio-input, keychain-access-groups). No sandbox
  entitlement is added; that is what permits `dlopen` of PrivateFrameworks and
  the CGS calls. The sandboxed `FolderPreview.appex` is unaffected — this
  feature lives entirely in the main app process.
- Hardened Runtime (required for notarization): confirm no entitlement blocks
  `dlopen` of system PrivateFrameworks (it does not by default). Document this
  in the implementation plan's notarization check.

---

## 8. UI / UX

### Floating panel

- Borderless non-activating `NSPanel` at HUD level, fade in/out via
  `MAYNMotionBridge.effectiveDuration(.toastIn/.toastOut)`; Reduce Motion
  honored (fades collapse to instant, matching `WindowSnapOverlayPanel`).
- Layout: app-name header (semantic font), then window cards laid out along the
  Dock's axis (row for bottom Dock, column for left/right Dock). Card = rounded
  thumbnail, window title (truncated), minimized/hidden badge. All tokens from
  `MAYNTheme` / `MAYNControlMetrics`; corner radius follows the
  OS-version-aware pattern already used in `WindowSnapOverlayPresentation`.
- Hover-highlight on a card uses `MAYNMotion`, not a raw animation.

### Positioning

- Anchored to the hovered Dock item's screen rect, offset toward the screen
  interior away from the Dock edge, clamped to the hovered item's display.
- Quartz↔Cocoa Y-flip handled centrally (see §10 / §9); the Dock item rect
  comes from AX (top-left origin) and must be converted to Cocoa
  (bottom-left origin) for `NSPanel.setFrame`.

### Click-to-raise

- Click a card → §3.6 raise sequence → panel dismisses. The click is handled
  inside the panel (mouse events enabled); no global click interception is
  required for the core flow.

### Title-only fallback

- When Screen Recording is denied, cards render **title + app icon + state
  badge** with no thumbnail (mirrors DockDoor's windowless / no-capture path).
  Click-to-raise still works fully (it uses AX + SkyLight, not capture).
- A subtle inline note + "Enable previews" affordance routes to the permission
  step.

### Onboarding & settings

- Descriptor `onboardingSetupFactory` returns a one-step setup: explain Dock
  previews, request Screen Recording (`CGRequestScreenCaptureAccess`), and show
  current status; the step is **skippable** (feature still works title-only).
- Tool page (`FunctionPageShell`) is configuration/guidance: the enable toggle,
  permission status, and settings: Live previews (off), Current-Space-only,
  Current-monitor-only, include minimized/hidden, thumbnail lifespan, and the
  Phase-2 gesture extras (off). No hotkey recorder on the page.
- Dashboard card via `FeatureToolCard` with the standard lifecycle actions.
  Disabled sidebar destination stays visible but inert (CLAUDE.md rule).

---

## 9. Edge cases & error handling

- **Screen Recording denied:** degrade to title-only list; live toggle
  disabled; never hard-fail or repeatedly prompt. Re-check via
  `CGPreflightScreenCaptureAccess()` on `didBecomeActive`.
- **Accessibility denied/revoked:** coordinator enters `needsAccessibility`,
  observer + enumeration suspend; trust monitor re-arms the feature on grant
  (no restart) — same path as WindowControl.
- **Dock AX tree rebuild:** S1 health-check detects the stale `AXList`
  (`kAXRoleAttribute` returns `.invalidUIElement`/`.cannotComplete`) and
  re-subscribes; hover silently resumes (DockObserver.swift:182–191).
- **Dock relaunch (PID change):** S1 detects the new `com.apple.dock` PID and
  rebuilds the observer (DockObserver.swift:175).
- **App has no windows:** show "No windows" (or, per setting, suppress the panel
  for windowless apps). Single-window apps optionally suppressed.
- **Minimized restore fails:** AX `kAXMinimizedAttribute=false` is best-effort;
  fall back to `app.activate()` then AX `kAXRaiseAction`.
- **SkyLight symbol load fails (future macOS):** raise degrades to
  `app.activate()` + AX `kAXRaiseAction`; never crash. Log once.
- **Stale window id at click time:** if the cached `CGWindowID` no longer
  resolves, re-enumerate the app's windows and match by title/geometry before
  giving up.
- **Multi-monitor / mixed scale:** convert per the hovered item's display; never
  assume the main display. Coordinate conversion uses the per-screen offset math
  (DockObserver `computeOffsets` / `nsPointFromCGPoint` line 649–679 as the
  reference for the flip).
- **Full-screen frontmost app / Dock hidden:** suppress previews when the Dock
  is not visible (`DockObserver.isDockVisible()` line 124).
- **Hover ends before async refresh returns:** the background refresh checks the
  still-hovered PID before mutating the visible panel (DockObserver.swift:430).
- **MAYN's own Dock icon:** skip to avoid self-activation loops.

---

## 10. Performance plan

Performance is first-class (per the feature mandate):

- **Launch/enable seeding** populates the per-PID cache so first hover is
  instant; seeding runs off the main thread with bounded fan-out
  (`WindowSeeder`).
- **Show-cached-then-refresh:** hover renders cached windows + cached thumbnails
  immediately; a concurrency-capped background pass refreshes and the panel
  re-reads (no blocking on capture).
- **Concurrency caps:** static captures ≤ 4 in flight (bounded task group);
  live `SCStream`s hard-capped at ≤ 4 and torn down on disappear.
- **Thumbnail downscaling:** capture, then immediately downscale to panel
  thumbnail size; cache only the downscaled image to bound memory.
- **Thumbnail cache lifespan:** reuse thumbnails within the lifespan window;
  recapture only expired entries on the next hover.
- **Live previews opt-in + low frame rate / reduced dimensions** in
  `SCStreamConfiguration`; default off.
- **Observer is event-driven** (AX notification), not a hot polling loop; only
  the lightweight health-check timer (≈5 s) and the bounded AX-trust poll run
  periodically.
- **No persistent CGEventTap by default** — the Phase-2 gesture tap is opt-in;
  the core hover feature adds no always-on event tap.
- **AX↔SC matching via `_AXUIElementGetWindow`** avoids expensive title/geometry
  scanning on the common path.

---

## 11. Testing strategy

Private-API and live-capture code is hard to unit-test; isolate testable logic
behind protocols and inject fakes (the WindowControl pattern: `tap`,
`actionPerformer`, `accessibilityTrust` are all injected — see
`WindowControlCoordinator.init` line 88).

- **Coordinator state machine (unit):** inject a fake observer, fake enumerator,
  fake trust source; assert transitions
  (off → needsAccessibility → active → suspended) mirroring
  `WindowControlPresentationTests`.
- **Cache diffing (unit):** add/remove/update produce correct change signals
  (template: `SpaceWindowCacheManager`); concurrency-safe under parallel writes.
- **AX↔SC merge (unit):** given fixture SC + AX window lists, dedupe by window
  id with title/geometry fallback yields the expected merged set.
- **Permission gating (unit):** Screen-Recording-denied → title-only model;
  granted → thumbnail model. `PermissionStatusProvider` mapping covered like the
  existing microphone mapping tests.
- **Positioning math (unit):** Quartz↔Cocoa flip + multi-monitor offset given
  fixture screen frames produces correct panel origins for each Dock edge.
- **Thumbnail lifespan (unit):** expired entries recapture, fresh entries reuse
  (inject a clock).
- **Manual / integration:** hover across bottom/left/right Dock; multi-monitor;
  minimized + hidden + off-Space windows; Dock relaunch (re-subscribe); Screen
  Recording toggle off→on; Reduce Motion; `swiftlint --strict`.
- The Shared `FeatureCore` enum additions (`FeatureID`, `Permission`) are
  covered by existing FeatureCore tests + recompilation.

---

## 12. Risks & mitigations

| Risk | Mitigation |
|---|---|
| **SkyLight focus byte-packing fragility** across macOS versions (the `SLPSPostEventRecordTo` event record is undocumented). | Lazy `dlopen`; if symbols/struct layout change, detect failed `CGError` and fall back to `app.activate()` + AX `kAXRaiseAction`. Pin behavior to tested macOS versions; gate via a runtime feature flag. |
| **Private CGS capture API drift** (`CGSHWCaptureWindowList`). | Wrap behind `DockPreviewPrivateAPI`; on failure fall back to `SCScreenshotManager` for on-screen windows and title-only for the rest. |
| **Screen Recording prompt UX** (system prompt is jarring; deny is sticky). | Request only from the explicit onboarding step; preflight first; degrade to fully-functional title-only mode; never re-prompt in a loop. |
| **Dock observer robustness** (AX tree rebuilds silently). | S1 health-check + element-validity probe + PID-change detection (DockDoor-proven). |
| **Performance regressions** (capture storms, memory). | Seeding, show-cached-then-refresh, ≤4 concurrency caps, downscaling, cache lifespan, opt-in live previews (§10). |
| **Multi-monitor coordinate math** (Quartz top-left vs Cocoa bottom-left, mixed scales). | Centralized conversion (reference `computeOffsets`/`nsPointFromCGPoint`); per-display anchoring; unit-tested positioning. |
| **macOS version constraints.** | Target macOS 14+; ScreenCaptureKit 12.3+; `SCContentFilter(desktopIndependentWindow:)` availability-gated; OS-version-aware corner radius already in the panel pattern. |
| **Event-tap coexistence** (Phase-2 gesture tap vs WindowControl tap). | Phase-2 only; each tap filters by event type / cursor region; off by default. |
| **Notarization / Hardened Runtime blocking `dlopen` of PrivateFrameworks.** | Confirmed non-sandboxed; verify in the plan's notarization step; no library-validation entitlement that would block it. |

---

## 13. Open questions

1. **Live previews in v1 or deferred to Phase 2?** Spec includes them as
   opt-in/off; confirm whether they ship enabled-capable in v1 or land later.
2. **Default for "Current Space only" / "Current monitor only"** — on or off by
   default? DockDoor defaults to showing all; MAYN may prefer current-Space-on
   for less clutter.
3. **Windowless apps:** show a "no windows" panel, or suppress the panel
   entirely? (DockDoor has a setting; pick a MAYN default.)
4. **Phase-2 gesture extras** (scroll-to-activate/hide, click-to-hide):
   in-scope as an opt-in setting, or dropped to avoid overlap with native Dock
   behavior and WindowControl?
5. **`FeatureID` / `Permission` enum naming** — `dockPreviews` and
   `screenRecording`? Confirm canonical names before they enter persisted
   feature state (they are `Codable` and stored).
6. **Hover-show delay** — match macOS Dock magnification feel, or expose a delay
   setting? DockDoor exposes one.
7. **S1 surface** — does `AXObserverCoordinator` expose
   `kAXSelectedChildrenChangedNotification` subscription on an arbitrary child
   element (the Dock `AXList`), or only app-level notifications? This feature
   needs child-element subscription; confirm S1's API covers it.
