# Loop Radial Window UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an optional, settings-gated radial (pie) window-management overlay that, on a held trigger, shows a re-skinned radial menu + live preview, lets the user pick a layout by cursor angle or keyboard, and on release routes exactly one `MAYN.WindowAction` into the existing `WindowControlCoordinator.perform(action:)`.

**Architecture:** A thin `RadialMenuCoordinator` owns the held-trigger lifecycle (open/update/commit/cancel) and the only mutable output is `(WindowAction, CGRect)`; it emits the action through an injected `RadialActionPerforming` seam (the real `WindowControlCoordinator`) and gets the preview frame from a read-only `ProposedFrameResolving` seam that shares `WindowMover`'s code path so preview and commit can never diverge. Selection math (cursor angle/distance → segment, ring/center mapping, keyboard mapping) and the coordinator state machine are pure and unit-tested; overlay NSPanels and the CGEvent-tap key/flags wiring get a thin injectable seam plus noted manual verification. All ported Loop views are re-implemented against `MAYNTheme`/`MAYNMotion`/`MAYNMotionBridge`, never copy-pasted.

**Tech Stack:** Swift 5.9+, SwiftUI, AppKit (NSPanel), CoreGraphics event tap, XCTest

---

## File Structure

New files (all under `MacAllYouNeed/WindowControl/Radial/` unless noted):

- `Shared/Sources/Core/WindowControl/RadialMenuLayout.swift` — pure layout + mapping (ring segment order, `WindowAction` per ring index, keyboard-key → action, center-band actions). No AppKit.
- `Shared/Sources/Core/WindowControl/RadialSelectionMath.swift` — pure cursor angle/distance → ring index / center-band / nil, plus the edge-clamp compensation ported from Loop's `MouseInteractionObserver`.
- `MacAllYouNeed/WindowControl/Radial/RadialMenuCoordinator.swift` — `@MainActor @Observable` lifecycle state machine; injected `RadialActionPerforming` + `ProposedFrameResolving` + overlay seam.
- `MacAllYouNeed/WindowControl/Radial/RadialMenuController.swift` — radial NSPanel via `NonActivatingFloatingPanelController<RadialMenuView>`.
- `MacAllYouNeed/WindowControl/Radial/RadialMenuView.swift` — ported `RadialLayout` + `RadialMenuView` + direction selector, re-skinned to MAYN tokens.
- `MacAllYouNeed/WindowControl/Radial/RadialMenuViewModel.swift` — `ObservableObject`: `currentAction`, animated `angle`, `isShown`, `isSettingsPreview`.
- `MacAllYouNeed/WindowControl/Radial/RadialPreviewController.swift` — screen-sized preview NSPanel, one level below the menu.
- `MacAllYouNeed/WindowControl/Radial/RadialPreviewView.swift` + `RadialPreviewViewModel.swift` — draws the resolved `CGRect` (reuses `WindowSnapOverlayPresentation` visual language).
- `MacAllYouNeed/WindowControl/Radial/RadialSettingsPreview.swift` — non-interactive Settings live preview wrapper.

Modified files:

- `Shared/Sources/Core/WindowControl/WindowControlSettings.swift` — add `radialMenuEnabled`, `radialLockToCenter`, `radialCursorSelectionEnabled` (all default `false`/`false`/`false`).
- `Shared/Sources/Platform/WindowControl/WindowMover.swift` — expose a read-only `proposedFrame(for:element:previousResult:)` that returns the target rect without writing.
- `MacAllYouNeed/WindowControl/WindowControlCoordinator.swift` — `RadialActionPerforming` conformance + `proposedFrame(for:)` + construct/wire `RadialMenuCoordinator`.
- `MacAllYouNeed/WindowControl/WindowControlEventTap.swift` — `radialMenuEnabled` runtime flag, key/flags mask when armed, radial-trigger detection forwarding open/update/commit/cancel.
- `MacAllYouNeed/WindowControl/WindowControlSettingsView.swift` + settings presentation — toggle + sub-options + live preview section.

New test files:

- `Shared/Tests/CoreTests/WindowControl/RadialMenuLayoutTests.swift`
- `Shared/Tests/CoreTests/WindowControl/RadialSelectionMathTests.swift`
- `Shared/Tests/CoreTests/WindowControl/WindowControlSettingsRadialTests.swift`
- `MacAllYouNeedTests/WindowControl/RadialMenuCoordinatorTests.swift`
- `MacAllYouNeedTests/WindowControl/RadialProposedFrameParityTests.swift`
- `MacAllYouNeedTests/WindowControl/RadialEventTapGatingTests.swift`
- additions to `MacAllYouNeedTests/WindowControl/WindowControlPresentationTests.swift`

Test command (Shared / Core pieces): `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test`
Test command (app): `xcodebuild test -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -destination 'platform=macOS,arch=arm64'`

---

### Task 1 — Settings: persist `radialMenuEnabled` + sub-options with safe defaults

**Files:** `Shared/Sources/Core/WindowControl/WindowControlSettings.swift`; test `Shared/Tests/CoreTests/WindowControl/WindowControlSettingsRadialTests.swift`

- [ ] Write failing XCTest:
```swift
import Core
import XCTest

final class WindowControlSettingsRadialTests: XCTestCase {
    func testRadialDefaultsAreOff() {
        let s = WindowControlSettings.default
        XCTAssertFalse(s.radialMenuEnabled)
        XCTAssertFalse(s.radialLockToCenter)
        XCTAssertFalse(s.radialCursorSelectionEnabled)
    }

    func testRadialRoundTripsThroughCoding() throws {
        var s = WindowControlSettings.default
        s.radialMenuEnabled = true
        s.radialLockToCenter = true
        s.radialCursorSelectionEnabled = true
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(WindowControlSettings.self, from: data)
        XCTAssertEqual(decoded, s)
    }

    func testLegacyPayloadWithoutRadialDecodesToDefaults() throws {
        let legacy = #"{"enabled":true,"dragAnywhereEnabled":true,"dragModifier":{"rawValue":0},"edgeSnapEnabled":true,"edgeSnapRequiresModifier":false,"edgeSnapModifier":{"rawValue":0},"doubleClickEnabled":true,"doubleClickModifier":{"rawValue":0},"ignoredBundleIDs":[],"titleBarYOffset":0,"debugLoggingEnabled":false,"showSyntheticClickMarker":false,"defaultsSeededVersion":3}"#
        // If the real encoded shape of WindowGestureModifier differs, encode a
        // default settings value, strip the three radial keys from the JSON, and
        // assert it still decodes — adapt this literal to the actual shape.
        let decoded = try JSONDecoder().decode(WindowControlSettings.self, from: Data(legacy.utf8))
        XCTAssertFalse(decoded.radialMenuEnabled)
    }
}
```
- [ ] Run-fail: `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter WindowControlSettingsRadialTests` → expect compile error (no `radialMenuEnabled`). If `testLegacyPayloadWithoutRadialDecodesToDefaults` is brittle against `WindowGestureModifier`'s real Codable shape, first encode `WindowControlSettings.default`, decode-print it, and update the literal before proceeding.
- [ ] Minimal impl: add three `public var radialMenuEnabled/radialLockToCenter/radialCursorSelectionEnabled: Bool` stored properties, default `false`, with `init` params defaulting `false`, and decode-with-default so legacy payloads remain valid. Because Swift's synthesized `Decodable` already treats missing keys with a default-value initializer only if the property has a default *and* a custom `init(from:)`, add a `init(from decoder:)` that does `decodeIfPresent(..., forKey:) ?? false` for the three new keys (mirror the existing members exactly).
- [ ] Run-pass: same filter command → green.
- [ ] Commit:
```
git add Shared/Sources/Core/WindowControl/WindowControlSettings.swift Shared/Tests/CoreTests/WindowControl/WindowControlSettingsRadialTests.swift
git commit -m "Add radial menu settings fields with safe defaults

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2 — Pure ring layout: ring index → `WindowAction`

**Files:** `Shared/Sources/Core/WindowControl/RadialMenuLayout.swift`; test `Shared/Tests/CoreTests/WindowControl/RadialMenuLayoutTests.swift`

- [ ] Write failing XCTest (the §5 mapping table for the 8-segment ring; index 0 = N, clockwise):
```swift
import Core
import XCTest

final class RadialMenuLayoutTests: XCTestCase {
    func testRingHasEightDirectionalSegments() {
        XCTAssertEqual(RadialMenuLayout.ringActions.count, 8)
    }

    func testRingOrderClockwiseFromNorth() {
        XCTAssertEqual(RadialMenuLayout.ringActions, [
            .topHalf,      // N  (index 0)
            .topRight,     // NE
            .rightHalf,    // E
            .bottomRight,  // SE
            .bottomHalf,   // S
            .bottomLeft,   // SW
            .leftHalf,     // W
            .topLeft       // NW
        ])
    }

    func testActionForRingIndexWraps() {
        XCTAssertEqual(RadialMenuLayout.action(ringIndex: 0), .topHalf)
        XCTAssertEqual(RadialMenuLayout.action(ringIndex: 8), .topHalf)
        XCTAssertEqual(RadialMenuLayout.action(ringIndex: -1), .topLeft)
    }
}
```
- [ ] Run-fail: `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter RadialMenuLayoutTests` → no such type.
- [ ] Minimal impl: `public enum RadialMenuLayout` with `public static let ringActions: [WindowAction] = [.topHalf, .topRight, .rightHalf, .bottomRight, .bottomHalf, .bottomLeft, .leftHalf, .topLeft]` and `public static func action(ringIndex: Int) -> WindowAction { ringActions[((ringIndex % ringActions.count) + ringActions.count) % ringActions.count] }`.
- [ ] Run-pass: same filter → green.
- [ ] Commit:
```
git add Shared/Sources/Core/WindowControl/RadialMenuLayout.swift Shared/Tests/CoreTests/WindowControl/RadialMenuLayoutTests.swift
git commit -m "Add pure radial ring layout mapping

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3 — Pure mapping: keyboard key + center band → `WindowAction?`

**Files:** `Shared/Sources/Core/WindowControl/RadialMenuLayout.swift` (extend); test `RadialMenuLayoutTests.swift` (extend)

- [ ] Write failing XCTest (arrow + paired directional keys, center band, dedicated keys; covers the full §5 table incl. nil no-selection). Use `RadialMenuKey` as a pure abstraction (not raw NSEvent keycodes) so it stays AppKit-free:
```swift
extension RadialMenuLayoutTests {
    func testKeyboardMapping() {
        XCTAssertEqual(RadialMenuLayout.action(for: .left), .leftHalf)
        XCTAssertEqual(RadialMenuLayout.action(for: .right), .rightHalf)
        XCTAssertEqual(RadialMenuLayout.action(for: .up), .topHalf)
        XCTAssertEqual(RadialMenuLayout.action(for: .down), .bottomHalf)
        XCTAssertEqual(RadialMenuLayout.action(for: .upLeft), .topLeft)
        XCTAssertEqual(RadialMenuLayout.action(for: .upRight), .topRight)
        XCTAssertEqual(RadialMenuLayout.action(for: .downLeft), .bottomLeft)
        XCTAssertEqual(RadialMenuLayout.action(for: .downRight), .bottomRight)
        XCTAssertEqual(RadialMenuLayout.action(for: .maximize), .maximize)
        XCTAssertEqual(RadialMenuLayout.action(for: .almostMaximize), .almostMaximize)
        XCTAssertEqual(RadialMenuLayout.action(for: .center), .center)
        XCTAssertEqual(RadialMenuLayout.action(for: .nextDisplay), .nextDisplay)
        XCTAssertEqual(RadialMenuLayout.action(for: .previousDisplay), .previousDisplay)
        XCTAssertEqual(RadialMenuLayout.action(for: .restore), .restore)
    }

    func testCenterBandActionByDistance() {
        // Inside no-action band → nil; center band (>= noAction, < directional)
        // resolves the configured center action; here .maximize is the default.
        XCTAssertNil(RadialMenuLayout.centerBandAction)
        XCTAssertEqual(RadialMenuLayout.action(for: .maximize), .maximize)
    }
}
```
- [ ] Run-fail: same filter → missing `RadialMenuKey` / `action(for:)`.
- [ ] Minimal impl: add `public enum RadialMenuKey { case left, right, up, down, upLeft, upRight, downLeft, downRight, maximize, almostMaximize, center, nextDisplay, previousDisplay, restore }` and `public static func action(for key: RadialMenuKey) -> WindowAction` with a `switch` returning the §5 mapping. Add `public static let centerBandAction: WindowAction? = nil` placeholder used by Task 4's distance bands (the cursor center band resolves `.maximize`; keyboard center keys resolve the three center actions explicitly). Keep ports of `.smaller/.larger/.cycle/.stash/thirds` out entirely.
- [ ] Run-pass: same filter → green.
- [ ] Commit:
```
git add Shared/Sources/Core/WindowControl/RadialMenuLayout.swift Shared/Tests/CoreTests/WindowControl/RadialMenuLayoutTests.swift
git commit -m "Add radial keyboard and center-band action mapping

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4 — Pure cursor selection math: angle/distance → action

**Files:** `Shared/Sources/Core/WindowControl/RadialSelectionMath.swift`; test `Shared/Tests/CoreTests/WindowControl/RadialSelectionMathTests.swift`

Ports the bucketing + band logic from Loop `MouseInteractionObserver.swift:116-152` (`noActionDistance = 10`, `directionalActionDistance = 50`, `angle + .pi/2`, index = `Int((degrees + halfSpan)/span) % count`). No event plumbing here.

- [ ] Write failing XCTest:
```swift
import Core
import CoreGraphics
import XCTest

final class RadialSelectionMathTests: XCTestCase {
    private let origin = CGPoint(x: 500, y: 500)

    func testBelowNoActionDistanceIsNil() {
        let p = CGPoint(x: 505, y: 503) // distance < 10
        XCTAssertNil(RadialSelectionMath.action(initial: origin, current: p))
    }

    func testBetweenBandsIsCenterAction() {
        let p = CGPoint(x: 530, y: 500) // 30pt: >= noAction, < directional
        XCTAssertEqual(RadialSelectionMath.action(initial: origin, current: p), .maximize)
    }

    func testStraightUpSelectsTopHalf() {
        // CG coords: up = smaller y. 100pt up.
        let p = CGPoint(x: 500, y: 400)
        XCTAssertEqual(RadialSelectionMath.action(initial: origin, current: p), .topHalf)
    }

    func testRightSelectsRightHalf() {
        let p = CGPoint(x: 600, y: 500)
        XCTAssertEqual(RadialSelectionMath.action(initial: origin, current: p), .rightHalf)
    }

    func testDiagonalSelectsCorner() {
        let p = CGPoint(x: 600, y: 400) // up-right
        XCTAssertEqual(RadialSelectionMath.action(initial: origin, current: p), .topRight)
    }

    func testEdgeClampExtendsTravelBeyondPinnedCursor() {
        // When the cursor is pinned at the screen's max X, the unclamped
        // resolved X keeps growing by delta, still bucketing to the E segment.
        let bounds = CGRect(x: 0, y: 0, width: 500, height: 500)
        var clamp = RadialSelectionMath.EdgeClamp(initial: CGPoint(x: 495, y: 250), screenBounds: bounds)
        let resolved = clamp.resolve(current: CGPoint(x: 500, y: 250), deltaX: 20, deltaY: 0)
        XCTAssertGreaterThan(resolved.x, 500)
    }
}
```
- [ ] Run-fail: `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter RadialSelectionMathTests` → no such type.
- [ ] Minimal impl: `public enum RadialSelectionMath` with `directionalActionDistance: CGFloat = 50`, `noActionDistance: CGFloat = 10`; `public static func action(initial:current:) -> WindowAction?` computing `distance` and `angle = atan2(dy, dx) + .pi/2` (CG up-is-smaller-y handled by sign), normalizing to `[0,360)`, returning `nil` below `noActionDistance`, `.maximize` (center band) between bands, else `RadialMenuLayout.action(ringIndex: Int((deg + halfSpan)/span) % 8)` with `span = 360/8`. Add a `public struct EdgeClamp` porting `computeLatestMousePosition` (`MouseInteractionObserver.swift:177-214`): store `initial`, `screenBounds`, `latest`, `shouldAccountForAbsolute` (set from the edge-proximity check at `:63-70`); `mutating func resolve(current:deltaX:deltaY:) -> CGPoint`. Align the ring-index-to-N convention with Task 2 (index 0 = N) by choosing the angle offset accordingly — adjust the offset constant until the four cardinal tests pass; document the chosen offset in a comment.
- [ ] Run-pass: same filter → green.
- [ ] Commit:
```
git add Shared/Sources/Core/WindowControl/RadialSelectionMath.swift Shared/Tests/CoreTests/WindowControl/RadialSelectionMathTests.swift
git commit -m "Add pure radial cursor selection math with edge clamp

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5 — Read-only proposed-frame on `WindowMover`

**Files:** `Shared/Sources/Platform/WindowControl/WindowMover.swift`; test `MacAllYouNeedTests/WindowControl/RadialProposedFrameParityTests.swift`

`targetFrame(for:currentFrame:preserveSize:previousResult:)` (`WindowMover.swift:188-234`) is already pure; expose a thin public read-only entry that calls it without `moveValidated`.

- [ ] Write failing XCTest asserting the proposed frame equals what `move(...)` proposes, for on-screen actions, using a fake element (mirror existing mover/`WindowControlPresentationTests` fakes):
```swift
@testable import MacAllYouNeed
import Core
import CoreGraphics
import Platform
import XCTest

@MainActor
final class RadialProposedFrameParityTests: XCTestCase {
    func testProposedFrameMatchesMoveForOnScreenActions() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let element = FakeWindowMovableElement(frame: CGRect(x: 100, y: 100, width: 600, height: 500))
        let mover = WindowMover(screenDetector: FixedScreenDetector(visibleFrame: visible))
        for action in [WindowAction.leftHalf, .rightHalf, .topHalf, .bottomHalf,
                       .topLeft, .topRight, .bottomLeft, .bottomRight, .maximize, .almostMaximize] {
            let proposed = mover.proposedFrame(for: action, element: element, previousResult: nil)
            let committed = mover.move(element, action: action).proposedFrame
            XCTAssertEqual(proposed, committed, "drift for \(action)")
        }
    }
}
```
- [ ] Run-fail: `xcodebuild test -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -destination 'platform=macOS,arch=arm64' -only-testing:MacAllYouNeedTests/RadialProposedFrameParityTests` → no `proposedFrame`. (If `FakeWindowMovableElement`/`FixedScreenDetector` don't already exist in the test target, reuse the existing mover-test fakes; create minimal conformances in this file only if absent.)
- [ ] Minimal impl: add `public func proposedFrame(for action: WindowAction, element: WindowMovableElement, previousResult: WindowMovementResult?) -> CGRect?` that resolves `currentFrame = element.frame` and returns `targetFrame(for: action, currentFrame:, preserveSize: <same value move() uses>, previousResult:)`. Read `move(...)` to match its `preserveSize` derivation exactly so parity holds. Do **not** call any AX write.
- [ ] Run-pass: same `-only-testing` → green.
- [ ] Commit:
```
git add Shared/Sources/Platform/WindowControl/WindowMover.swift MacAllYouNeedTests/WindowControl/RadialProposedFrameParityTests.swift
git commit -m "Expose read-only proposed frame on WindowMover for radial preview

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6 — `RadialActionPerforming` + `ProposedFrameResolving` seams on the coordinator

**Files:** `MacAllYouNeed/WindowControl/WindowControlCoordinator.swift`; test `MacAllYouNeedTests/WindowControl/RadialMenuCoordinatorTests.swift` (seam-only assertions here; full lifecycle in Task 7)

- [ ] Write failing XCTest asserting `WindowControlCoordinator` conforms and forwards:
```swift
@testable import MacAllYouNeed
import Core
import CoreGraphics
import XCTest

@MainActor
final class RadialMenuCoordinatorTests: XCTestCase {
    func testCoordinatorIsRadialActionPerformer() {
        let coordinator = WindowControlCoordinator(
            settings: WindowControlSettings.default,
            tap: InertTap(),
            actionPerformer: SpyActionPerformer()
        )
        let performer: RadialActionPerforming = coordinator
        performer.performRadial(.leftHalf)
        // perform is gated; with default settings (enabled=false) it is a no-op,
        // which is the contract: radial inherits all perform() guards.
        XCTAssertNil(coordinator.lastMovementResult)
    }
}
```
(Define `InertTap`/`SpyActionPerformer` minimally in the test file conforming to `WindowControlTapLifecycle`/`WindowControlActionPerforming`.)
- [ ] Run-fail: `xcodebuild test ... -only-testing:MacAllYouNeedTests/RadialMenuCoordinatorTests/testCoordinatorIsRadialActionPerformer` → no `RadialActionPerforming`.
- [ ] Minimal impl: declare `@MainActor protocol RadialActionPerforming: AnyObject { func performRadial(_ action: WindowAction) }` and `@MainActor protocol ProposedFrameResolving: AnyObject { func proposedFrame(for action: WindowAction) -> CGRect? }`. Conform `WindowControlCoordinator`: `performRadial(_:)` simply calls existing `perform(action:)` (reuses every guard at `:202-235`); `proposedFrame(for:)` resolves the focused element via the action performer's `currentIdentity` path and calls `WindowMover.proposedFrame(...)` — for `.restore/.nextDisplay/.previousDisplay` return `nil` in v1 (per spec §6.2 option 2; preview simply not shown).
- [ ] Run-pass: same `-only-testing` → green.
- [ ] Commit:
```
git add MacAllYouNeed/WindowControl/WindowControlCoordinator.swift MacAllYouNeedTests/WindowControl/RadialMenuCoordinatorTests.swift
git commit -m "Add radial action and proposed-frame seams to WindowControlCoordinator

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 7 — `RadialMenuCoordinator` lifecycle state machine

**Files:** `MacAllYouNeed/WindowControl/Radial/RadialMenuCoordinator.swift`; test `MacAllYouNeedTests/WindowControl/RadialMenuCoordinatorTests.swift` (extend)

The coordinator is constructed with injected `RadialActionPerforming`, `ProposedFrameResolving`, and an `OverlayPresenting` seam (so tests use a spy instead of real NSPanels).

- [ ] Write failing XCTest covering open/update/commit/cancel + double-open guard:
```swift
extension RadialMenuCoordinatorTests {
    func testLifecycle() {
        let action = SpyRadialPerformer()
        let frames = StubFrameResolver(rect: CGRect(x: 0, y: 0, width: 720, height: 900))
        let overlay = SpyOverlayPresenter()
        let c = RadialMenuCoordinator(performer: action, frameResolver: frames, overlay: overlay)

        c.open(initialCursor: CGPoint(x: 10, y: 10), lockToCenter: false)
        XCTAssertTrue(overlay.isShown)
        XCTAssertNil(c.currentAction)
        XCTAssertEqual(action.performCount, 0)

        c.open(initialCursor: CGPoint(x: 99, y: 99), lockToCenter: false) // re-open ignored
        XCTAssertEqual(overlay.showCount, 1)

        c.update(action: .leftHalf)
        XCTAssertEqual(c.currentAction, .leftHalf)
        XCTAssertEqual(overlay.lastPreviewRect, frames.rect)

        c.commit()
        XCTAssertEqual(action.performCount, 1)
        XCTAssertEqual(action.lastAction, .leftHalf)
        XCTAssertFalse(overlay.isShown)
    }

    func testCancelDoesNotPerform() {
        let action = SpyRadialPerformer()
        let c = RadialMenuCoordinator(performer: action,
                                      frameResolver: StubFrameResolver(rect: .zero),
                                      overlay: SpyOverlayPresenter())
        c.open(initialCursor: .zero, lockToCenter: false)
        c.update(action: .rightHalf)
        c.cancel()
        XCTAssertEqual(action.performCount, 0)
    }

    func testCommitWithNilActionIsNoOp() {
        let action = SpyRadialPerformer()
        let c = RadialMenuCoordinator(performer: action,
                                      frameResolver: StubFrameResolver(rect: .zero),
                                      overlay: SpyOverlayPresenter())
        c.open(initialCursor: .zero, lockToCenter: false)
        c.commit()
        XCTAssertEqual(action.performCount, 0)
    }
}
```
(Add `SpyRadialPerformer`, `StubFrameResolver`, `SpyOverlayPresenter` to the test file; `OverlayPresenting` protocol declared with the impl.)
- [ ] Run-fail: `xcodebuild test ... -only-testing:MacAllYouNeedTests/RadialMenuCoordinatorTests` → no `RadialMenuCoordinator`.
- [ ] Minimal impl: `@MainActor @Observable final class RadialMenuCoordinator` with `private(set) var isOpen`, `private(set) var currentAction: WindowAction?`; `OverlayPresenting` protocol (`func show(lockToCenter:cursor:)`, `func updateAction(_:previewRect:)`, `func hide()`); `open(initialCursor:lockToCenter:)` no-ops if `isOpen`, else sets `isOpen=true`, `currentAction=nil`, calls `overlay.show`; `update(action:)` sets `currentAction`, asks `frameResolver.proposedFrame(for:)`, calls `overlay.updateAction(_:previewRect:)`; `commit()` performs once iff `currentAction != nil` then `hide()` + reset; `cancel()` just `hide()` + reset.
- [ ] Run-pass: same `-only-testing` → green.
- [ ] Commit:
```
git add MacAllYouNeed/WindowControl/Radial/RadialMenuCoordinator.swift MacAllYouNeedTests/WindowControl/RadialMenuCoordinatorTests.swift
git commit -m "Add RadialMenuCoordinator open/update/commit/cancel state machine

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 8 — Radial menu view model (angle + currentAction, MAYN motion)

**Files:** `MacAllYouNeed/WindowControl/Radial/RadialMenuViewModel.swift`; test add to `RadialMenuCoordinatorTests.swift` or a small `RadialMenuViewModelTests.swift` in app target

Port Loop `RadialMenuViewModel.swift:128-137` angle formula (`index × span − 90`) over `RadialMenuLayout.ringActions`; strip `parentAction`, `ResizeContext`, `Window`, `Defaults`, `.smooth`. Animation goes through `MAYNMotion.animation(_:reduceMotion:)`.

- [ ] Write failing XCTest (pure angle math is the testable seam; expose `targetAngle(for:)`):
```swift
@testable import MacAllYouNeed
import Core
import XCTest

@MainActor
final class RadialMenuViewModelTests: XCTestCase {
    func testTargetAngleForRingActions() {
        let vm = RadialMenuViewModel(isSettingsPreview: false)
        XCTAssertEqual(vm.targetAngle(for: .topHalf), -90, accuracy: 0.001)   // index 0
        XCTAssertEqual(vm.targetAngle(for: .rightHalf), 0, accuracy: 0.001)   // index 2 (×45 −90)
        XCTAssertNil(vm.targetAngle(for: .restore))                           // non-ring → no angle
    }

    func testNoSelectionClearsAction() {
        let vm = RadialMenuViewModel(isSettingsPreview: false)
        vm.apply(action: .leftHalf)
        XCTAssertEqual(vm.currentAction, .leftHalf)
        vm.apply(action: nil)
        XCTAssertNil(vm.currentAction)
    }
}
```
- [ ] Run-fail: `xcodebuild test ... -only-testing:MacAllYouNeedTests/RadialMenuViewModelTests` → no type.
- [ ] Minimal impl: `final class RadialMenuViewModel: ObservableObject` with `@Published private(set) var currentAction: WindowAction?`, `@Published private(set) var angle: Double = 0`, `@Published private(set) var isShown = false`, `let isSettingsPreview: Bool`. `func targetAngle(for action: WindowAction?) -> Double?` returns `ringActions.firstIndex(of:).map { Double($0) * 45 - 90 }`. `func apply(action:)` sets `currentAction` and, if a target angle exists, tweens `angle` to it via `withAnimation(MAYNMotion.animation(.control, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion))`. No raw springs/`.smooth`.
- [ ] Run-pass: same `-only-testing` → green.
- [ ] Commit:
```
git add MacAllYouNeed/WindowControl/Radial/RadialMenuViewModel.swift MacAllYouNeedTests/WindowControl/RadialMenuViewModelTests.swift
git commit -m "Add RadialMenuViewModel with MAYN-tokenized angle animation

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 9 — Radial menu SwiftUI view (re-skinned to MAYNTheme)

**Files:** `MacAllYouNeed/WindowControl/Radial/RadialMenuView.swift`

Pure SwiftUI; no new pure-logic test (rendering is manual-verify). Port `RadialLayout` (`RadialLayout.swift:10-29`), the ring of direction segments, and the center glyph; **re-skin**: all colors from `MAYNTheme`, all motion from `MAYNMotion`. Center glyph uses `WindowAction.symbolName` (`WindowAction.swift:52`); empty state (no focused window, non-preview) shows `exclamationmark.triangle` re-skinned.

- [ ] Implement `struct RadialMenuView: View` taking `@ObservedObject var viewModel: RadialMenuViewModel`, a hardcoded MAYN-tokenized diameter constant (define `private enum RadialMenuMetrics { static let diameter: CGFloat = 180 }` — single source, no magic numbers scattered), `RadialLayout` over 8 `DirectionSegment` subviews, selected-segment highlight via `MAYNTheme` accent, angle indicator rotated by `viewModel.angle`. Use `MAYNMotion.animation(.tab, reduceMotion:)` for segment highlight transitions. No `Color(red:green:blue:)`, no `.spring`, no `.easeInOut(duration:)`.
- [ ] Verify build only (no unit test): `xcodebuild build -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -destination 'platform=macOS,arch=arm64'` → succeeds.
- [ ] Run `swiftlint --strict --path MacAllYouNeed/WindowControl/Radial/RadialMenuView.swift` → no raw color/animation violations.
- [ ] **Manual verification (note in commit):** rendered later in Settings live preview (Task 14); structural review now.
- [ ] Commit:
```
git add MacAllYouNeed/WindowControl/Radial/RadialMenuView.swift
git commit -m "Add re-skinned RadialMenuView (MAYNTheme/MAYNMotion)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 10 — Radial menu NSPanel controller

**Files:** `MacAllYouNeed/WindowControl/Radial/RadialMenuController.swift`

Mirror `WindowSnapOverlayPanel.swift:44-67` exactly: `NonActivatingFloatingPanelController<RadialMenuView>`, `FloatingHUDWindowLayering.windowLevel`, clear background, `ignoresMouseEvents = true`, `MAYNMotionBridge` fades. `open(at:lockToCenter:)` positions at cursor or locked screen center (port `RadialMenuController.swift:51-68` positioning, MAYN-tokenized).

- [ ] Implement `@MainActor final class RadialMenuController` owning the panel + a `RadialMenuViewModel`; `open(at cursor: CGPoint, lockToCenter: Bool, screen: NSScreen?)`, `update(action: WindowAction?, ...)`, `close()`. Fade in/out via `MAYNMotionBridge.effectiveDuration(.toastIn/.toastOut)` and `timingFunction` (copy the `animate(_:to:kind:)` pattern from `WindowSnapOverlayPanel.swift:114-126`).
- [ ] Verify build: `xcodebuild build -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -destination 'platform=macOS,arch=arm64'` → succeeds.
- [ ] **Manual verification:** held-trigger smoke after Task 13.
- [ ] Commit:
```
git add MacAllYouNeed/WindowControl/Radial/RadialMenuController.swift
git commit -m "Add radial menu floating panel controller

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 11 — Preview overlay controller + view (shares snap overlay visual)

**Files:** `MacAllYouNeed/WindowControl/Radial/RadialPreviewController.swift`, `RadialPreviewView.swift`, `RadialPreviewViewModel.swift`

Screen-sized panel one level **below** the radial menu (`FloatingHUDWindowLayering.windowLevel` − 1, per spec §3.3); draws the resolved `CGRect` reusing `WindowSnapOverlayPresentation` (black fill / light-gray border / corner radius). The frame comes only from `RadialMenuCoordinator` (never recomputed in the view).

- [ ] Implement `RadialPreviewViewModel: ObservableObject` with `@Published var previewRect: CGRect?` and `isShown`; `RadialPreviewView` rendering a `RoundedRectangle` at `previewRect` using `WindowSnapOverlayPresentation` constants; `RadialPreviewController` building a screen-sized `NonActivatingFloatingPanelController`, `setFrame(screen.frame)`, `ignoresMouseEvents = true`, MAYN fades. Animate rect moves with `MAYNMotionBridge` durations.
- [ ] Verify build: `xcodebuild build ... -destination 'platform=macOS,arch=arm64'` → succeeds.
- [ ] **Manual verification:** preview lands correctly single + dual display after Task 13.
- [ ] Commit:
```
git add MacAllYouNeed/WindowControl/Radial/RadialPreviewController.swift MacAllYouNeed/WindowControl/Radial/RadialPreviewView.swift MacAllYouNeed/WindowControl/Radial/RadialPreviewViewModel.swift
git commit -m "Add radial preview overlay sharing snap overlay visual language

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 12 — `OverlayPresenting` real impl wiring controllers to the coordinator

**Files:** `MacAllYouNeed/WindowControl/Radial/RadialMenuCoordinator.swift` (add concrete `RadialOverlayPresenter`); reuse `RadialMenuCoordinatorTests` to assert AppKit-coordinate conversion is delegated, not recomputed

- [ ] Write failing XCTest asserting the presenter converts the CG preview rect to AppKit coords via the existing helper (inject a conversion closure so the test stays headless):
```swift
extension RadialMenuCoordinatorTests {
    func testOverlayPresenterConvertsPreviewToAppKitCoordinates() {
        var converted: CGRect?
        let presenter = RadialOverlayPresenter(
            menu: NoopMenuPresenting(),
            preview: NoopPreviewPresenting(),
            convertToAppKit: { cg, _ in converted = cg; return CGRect(x: cg.minX, y: 999, width: cg.width, height: cg.height) }
        )
        presenter.updateAction(.leftHalf, previewRect: CGRect(x: 0, y: 0, width: 720, height: 900))
        XCTAssertEqual(converted, CGRect(x: 0, y: 0, width: 720, height: 900))
    }
}
```
(Define `NoopMenuPresenting`/`NoopPreviewPresenting` thin protocols the real controllers also satisfy.)
- [ ] Run-fail: `xcodebuild test ... -only-testing:MacAllYouNeedTests/RadialMenuCoordinatorTests/testOverlayPresenterConvertsPreviewToAppKitCoordinates` → no `RadialOverlayPresenter`.
- [ ] Minimal impl: `RadialOverlayPresenter: OverlayPresenting` holding the two controllers (behind small protocols) plus an injected `convertToAppKit: (CGRect, UInt32) -> CGRect` defaulting to `WindowScreenDetector.convertCGDisplayRectToAppKitCoordinates` (the same path `WindowControlEventTap.appKitOverlayFrame` uses, `WindowControlEventTap.swift:373-384`). `updateAction` converts then forwards to preview controller; `show`/`hide` drive both controllers.
- [ ] Run-pass: same `-only-testing` → green.
- [ ] Commit:
```
git add MacAllYouNeed/WindowControl/Radial/RadialMenuCoordinator.swift MacAllYouNeedTests/WindowControl/RadialMenuCoordinatorTests.swift
git commit -m "Wire radial overlay presenter with shared AppKit coordinate conversion

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 13 — Event tap: `radialMenuEnabled` flag, key mask, trigger forwarding

**Files:** `MacAllYouNeed/WindowControl/WindowControlEventTap.swift`, `MacAllYouNeed/WindowControl/WindowControlCoordinator.swift` (construct + wire `RadialMenuCoordinator` like the snap overlay at `:110-119`); test `MacAllYouNeedTests/WindowControl/RadialEventTapGatingTests.swift`

- [ ] Write failing XCTest for the gating predicate (extract the mask/arming decision into a pure helper so it's testable without installing a real tap):
```swift
@testable import MacAllYouNeed
import Core
import XCTest

final class RadialEventTapGatingTests: XCTestCase {
    func testKeyMaskOnlyWhenRadialEnabledAndTrusted() {
        XCTAssertFalse(WindowControlEventTap.shouldArmRadial(radialEnabled: false, axTrusted: true, anyRuntimeEnabled: true))
        XCTAssertFalse(WindowControlEventTap.shouldArmRadial(radialEnabled: true, axTrusted: false, anyRuntimeEnabled: true))
        XCTAssertTrue(WindowControlEventTap.shouldArmRadial(radialEnabled: true, axTrusted: true, anyRuntimeEnabled: true))
    }

    func testRadialIncludesKeyEventsInMask() {
        let withRadial = WindowControlEventTap.eventMask(includeRadialKeys: true)
        let without = WindowControlEventTap.eventMask(includeRadialKeys: false)
        let keyDown = CGEventMask(1 << CGEventType.keyDown.rawValue)
        XCTAssertEqual(withRadial & keyDown, keyDown)
        XCTAssertEqual(without & keyDown, 0)
        // Mouse + recovery mask unchanged when radial off.
        let mouseDown = CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
        XCTAssertEqual(without & mouseDown, mouseDown)
    }
}
```
- [ ] Run-fail: `xcodebuild test ... -only-testing:MacAllYouNeedTests/RadialEventTapGatingTests` → no such statics.
- [ ] Minimal impl:
  - Add `radialMenuEnabled` to the tap's `Runtime` (sourced from `settings.radialMenuEnabled` in `updateRuntime`; `WindowControlCoordinator.updateTapRuntime` already passes `settings`).
  - Add `static func shouldArmRadial(radialEnabled:axTrusted:anyRuntimeEnabled:) -> Bool` and `static func eventMask(includeRadialKeys:) -> CGEventMask` (existing mouse+recovery mask, OR-ing `keyDown|keyUp|flagsChanged` when `includeRadialKeys`). Build `mask` in `start()` from `eventMask(includeRadialKeys: runtime.settings.radialMenuEnabled)`.
  - In `handle(type:event:)`, **before** the mouse switch, add a `case .keyDown, .keyUp, .flagsChanged:` branch that returns early (passes the event through) unless radial is armed; when armed and the trigger transitions, forward open/update/commit/cancel to the injected `radialCoordinator` closures and respect the synthetic-event marker + `tapDisabledBy*` early-outs (`:137-151`). When a mouse gesture is already active (`gestureMode != .none`), suppress radial open. Guard the trigger key against bare `dragModifier`/`edgeSnapModifier`/`doubleClickModifier` reuse (cancel collision).
  - Inject radial intents from the coordinator the same way as `setSnapOverlay` (`:86-92`), constructing the `RadialMenuCoordinator` in `WindowControlCoordinator.init` (`:110-119`).
  - **Never** add the key mask when `radialMenuEnabled` is false (risk mitigation §11): pass-through discipline preserved.
- [ ] Run-pass: same `-only-testing` → green. Then run the full WindowControl suite to confirm no mouse-path regression: `xcodebuild test ... -only-testing:MacAllYouNeedTests/WindowControlPresentationTests -only-testing:MacAllYouNeedTests/RadialEventTapGatingTests`.
- [ ] **Manual verification:** with toggle on, hold trigger → menu + preview appear; release on a direction → window moves once; Esc cancels; confirm grab/edge-snap/double-click still work; toggle off → no key interception.
- [ ] Commit:
```
git add MacAllYouNeed/WindowControl/WindowControlEventTap.swift MacAllYouNeed/WindowControl/WindowControlCoordinator.swift MacAllYouNeedTests/WindowControl/RadialEventTapGatingTests.swift
git commit -m "Arm radial trigger on event tap behind radialMenuEnabled gate

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 14 — Settings toggle, sub-options, and live preview

**Files:** `MacAllYouNeed/WindowControl/WindowControlSettingsView.swift`, settings presentation source (the type backing `WindowControlSettingsPresentation`), `MacAllYouNeed/WindowControl/Radial/RadialSettingsPreview.swift`; test additions in `MacAllYouNeedTests/WindowControl/WindowControlPresentationTests.swift`

- [ ] Write failing XCTest extending the presentation test to include the new section + that sub-options are gated on the toggle:
```swift
extension WindowControlPresentationTests {
    func testRadialSettingsSectionPresent() {
        XCTAssertTrue(WindowControlSettingsPresentation.sectionTitles.contains("Radial Window Menu"))
        XCTAssertFalse(WindowControlSettingsPresentation.showsRadialSubOptions(radialEnabled: false))
        XCTAssertTrue(WindowControlSettingsPresentation.showsRadialSubOptions(radialEnabled: true))
    }
}
```
- [ ] Run-fail: `xcodebuild test ... -only-testing:MacAllYouNeedTests/WindowControlPresentationTests/testRadialSettingsSectionPresent` → missing.
- [ ] Minimal impl:
  - Add `"Radial Window Menu"` to `WindowControlSettingsPresentation.sectionTitles` and `static func showsRadialSubOptions(radialEnabled: Bool) -> Bool { radialEnabled }`.
  - In `WindowControlSettingsView`, add a `MAYNSection` titled "Radial Window Menu" with a `MAYNSettingsRow` + toggle bound to `settings.radialMenuEnabled` (persist via `WindowControlSettingsStore.save` → `applySettings`). When on, show sub-option rows (lock to center, cursor selection) and the live preview. Any in-section 2–5-way choice uses `FunctionSegmentedTabStrip`, never `.pickerStyle(.segmented)`.
  - `RadialSettingsPreview`: a `RadialMenuView(viewModel:)` with `isSettingsPreview = true`, no panel/monitors, cycling through a few representative actions on a `MAYNMotion`-tokenized timer; honor Reduce Motion (snap, no animate).
- [ ] Run-pass: same `-only-testing` → green.
- [ ] Run `swiftlint --strict` over the touched files → clean.
- [ ] **Manual verification:** toggle reveals sub-options + animated preview; Reduce Motion makes the preview snap.
- [ ] Commit:
```
git add MacAllYouNeed/WindowControl/WindowControlSettingsView.swift MacAllYouNeed/WindowControl/Radial/RadialSettingsPreview.swift MacAllYouNeedTests/WindowControl/WindowControlPresentationTests.swift
git commit -m "Add radial menu settings section, sub-options, and live preview

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 15 — FeatureDescriptor gate + full-suite green

**Files:** the relevant `MacAllYouNeed/App/Descriptors/` Window Layouts descriptor (gate the radial capability as a sub-capability of Window Layouts per spec §12 Q4 default — no separate card unless decided otherwise); no new test file (covered by settings round-trip + gating tests)

- [ ] Confirm radial behavior is reachable only when both the Window Layouts feature is enabled *and* `radialMenuEnabled` is on (the tap's `shouldArmRadial` + coordinator guards already enforce AX trust + layouts runtime). Add the settings surface under the existing Window Layouts descriptor; do not introduce a new permission.
- [ ] Run the full Shared suite: `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test` → green.
- [ ] Run the full app suite: `xcodebuild test -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -destination 'platform=macOS,arch=arm64'` → green.
- [ ] Run `swiftlint --strict` (as in `scripts/ci-build.sh`) → clean.
- [ ] **Manual verification matrix:** single + dual display held-trigger flow; keyboard selection of every action; cursor selection (sub-toggle on) incl. screen-edge clamp; Reduce Motion snap; grab/edge-snap/double-click unaffected with radial on and off.
- [ ] Commit:
```
git add -A
git commit -m "Gate radial window UI under Window Layouts feature and finalize suite

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review

Spec coverage check against `04-loop-radial-window-ui.md`:

- **Held-trigger lifecycle (§3.1):** Task 13 (event-tap trigger detection, key/flags mask gated on `radialMenuEnabled` + AX, gesture-collision suppression) forwarding to Task 7 `RadialMenuCoordinator` (open/update/commit/cancel, double-open guard).
- **Radial menu overlay (§3.2, §4.1):** Task 9 view (re-skinned `RadialLayout` + segments + center glyph), Task 8 view model (angle formula stripped of `parentAction`/`ResizeContext`/`Defaults`/`.smooth`), Task 10 NSPanel controller via `NonActivatingFloatingPanelController` + `FloatingHUDWindowLayering` + `MAYNMotionBridge`, `isSettingsPreview` flag.
- **Preview overlay (§3.3, §4.2):** Task 11 (screen-sized panel one level below, reuses `WindowSnapOverlayPresentation`, frame supplied by resolver only).
- **Both selection modes (§3.4):** Task 3 keyboard mapping, Task 4 cursor angle/distance + `EdgeClamp` port. Keyboard ships first; cursor behind `radialCursorSelectionEnabled`.
- **Thin coordinator emitting WindowAction into perform (§4.3, §6.1):** Tasks 6–7; `performRadial` routes through existing `WindowControlCoordinator.perform(action:)` (all guards reused).
- **Read-only frame resolver, anti-drift (§6.2):** Task 5 `WindowMover.proposedFrame(...)` + Task 5 parity test asserting equality with `move(...).proposedFrame`; Task 6 `proposedFrame(for:)`; display/restore return `nil` in v1.
- **Loop-zone → WindowAction mapping table (§5):** Task 2 (ring) + Task 3 (keyboard/center), dropped Loop zones excluded.
- **Settings toggle + live preview (§3.5, §8.3, §6.5):** Task 1 (persistence + legacy decode), Task 14 (section, gated sub-options, `RadialMenuView(isSettingsPreview:)`).
- **Design system (§8.2):** every ported view uses `MAYNTheme`/`MAYNMotion`/`MAYNMotionBridge`; `swiftlint --strict` enforced in Tasks 9, 14, 15; `FunctionSegmentedTabStrip` for any segmented choice; Reduce Motion honored (Tasks 8, 11, 14).
- **No new permissions (§7):** confirmed; radial inherits AX trust via existing tap/coordinator gates (Task 15).
- **Stripped Loop infra:** no `Defaults`, `Scribe`/`@Loggable`, `AnimationConfiguration`, `WindowActionEngine`, `ResizeContext`, cycle/stash/thirds — enforced by the hardcoded `RadialMenuLayout` and the `(WindowAction, CGRect)`-only output.
- **Edge cases (§9):** double-open guard (Task 7), gesture collision + trigger-modifier validation (Task 13), preview/commit parity (Task 5), multi-display coordinate conversion (Task 12), nil-action no-op commit (Task 7).

Each task is bite-sized TDD (failing real XCTest → run-fail command → minimal real Swift → run-pass → exact commit). Overlay rendering and the live event tap carry explicit manual-verification notes where pure tests cannot reach.
