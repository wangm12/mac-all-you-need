import Core
import CoreGraphics
import XCTest

final class RadialSelectionMathTests: XCTestCase {
    func testDeadZoneReturnsNone() {
        var state = RadialSelectionMath.SelectionState()
        XCTAssertEqual(RadialSelectionMath.selection(from: .zero, state: &state), .none)
        XCTAssertEqual(RadialSelectionMath.selection(from: CGPoint(x: 10, y: 10), state: &state), .none)
        XCTAssertEqual(RadialSelectionMath.selection(from: CGPoint(x: 0, y: 29), state: &state), .none)
    }

    func testArmedHysteresisExit() {
        var state = RadialSelectionMath.SelectionState()
        _ = RadialSelectionMath.selection(from: CGPoint(x: 0, y: -40), state: &state)
        XCTAssertTrue(state.isArmed)
        XCTAssertEqual(RadialSelectionMath.selection(from: CGPoint(x: 0, y: -20), state: &state), .none)
        XCTAssertFalse(state.isArmed)
    }

    func testTopDirectionIsRing0() {
        var state = RadialSelectionMath.SelectionState()
        let sel = RadialSelectionMath.selection(from: CGPoint(x: 0, y: -50), state: &state)
        XCTAssertEqual(sel, .ring(0))
    }

    func testRightDirectionIsRing2() {
        var state = RadialSelectionMath.SelectionState()
        let sel = RadialSelectionMath.selection(from: CGPoint(x: 50, y: 0), state: &state)
        XCTAssertEqual(sel, .ring(2))
    }

    func testLongPullUpSelectsFullScreen() {
        var state = RadialSelectionMath.SelectionState()
        let sel = RadialSelectionMath.selection(from: CGPoint(x: 0, y: -140), state: &state)
        XCTAssertEqual(sel, .fullScreen)
        XCTAssertTrue(state.isFullScreen)
    }

    func testLongPullRightSelectsFullScreen() {
        var state = RadialSelectionMath.SelectionState()
        let sel = RadialSelectionMath.selection(from: CGPoint(x: 140, y: 0), state: &state)
        XCTAssertEqual(sel, .fullScreen)
        XCTAssertTrue(state.isFullScreen)
    }

    func testLongPullDownSelectsFullScreen() {
        var state = RadialSelectionMath.SelectionState()
        let sel = RadialSelectionMath.selection(from: CGPoint(x: 0, y: 140), state: &state)
        XCTAssertEqual(sel, .fullScreen)
        XCTAssertTrue(state.isFullScreen)
    }

    func testFullScreenRequiresDwellWhenClockProvided() {
        var state = RadialSelectionMath.SelectionState()
        let delta = CGPoint(x: 0, y: -140)
        XCTAssertEqual(RadialSelectionMath.selection(from: delta, state: &state, now: 1.0), .ring(0))
        XCTAssertFalse(state.isFullScreen)
        XCTAssertEqual(RadialSelectionMath.selection(from: delta, state: &state, now: 1.1), .ring(0))
        XCTAssertEqual(RadialSelectionMath.selection(from: delta, state: &state, now: 1.19), .fullScreen)
        XCTAssertTrue(state.isFullScreen)
    }

    func testFullScreenDwellResetsWhenCursorReturnsInsideBand() {
        var state = RadialSelectionMath.SelectionState()
        let far = CGPoint(x: 0, y: -140)
        _ = RadialSelectionMath.selection(from: far, state: &state, now: 1.0)
        _ = RadialSelectionMath.selection(from: CGPoint(x: 0, y: -50), state: &state, now: 1.05)
        XCTAssertNil(state.fullScreenArmingStartedAt)
        XCTAssertEqual(RadialSelectionMath.selection(from: far, state: &state, now: 2.0), .ring(0))
    }

    func testFullScreenHysteresisExitReturnsCurrentRing() {
        var state = RadialSelectionMath.SelectionState()
        _ = RadialSelectionMath.selection(from: CGPoint(x: 140, y: 0), state: &state)
        XCTAssertEqual(RadialSelectionMath.selection(from: CGPoint(x: 120, y: 0), state: &state), .fullScreen)
        let backToRight = RadialSelectionMath.selection(from: CGPoint(x: 110, y: 0), state: &state)
        XCTAssertEqual(backToRight, .ring(2))
        XCTAssertFalse(state.isFullScreen)
    }

    func testShortPullUpSelectsTopHalf() {
        var state = RadialSelectionMath.SelectionState()
        let sel = RadialSelectionMath.selection(from: CGPoint(x: 0, y: -50), state: &state)
        XCTAssertEqual(sel, .ring(0))
        XCTAssertFalse(state.isFullScreen)
    }

    func testFullScreenHysteresisExit() {
        var state = RadialSelectionMath.SelectionState()
        _ = RadialSelectionMath.selection(from: CGPoint(x: 0, y: -140), state: &state)
        XCTAssertEqual(RadialSelectionMath.selection(from: CGPoint(x: 0, y: -120), state: &state), .fullScreen)
        let backToTop = RadialSelectionMath.selection(from: CGPoint(x: 0, y: -110), state: &state)
        XCTAssertEqual(backToTop, .ring(0))
        XCTAssertFalse(state.isFullScreen)
    }

    func testFullScreenActionMapping() {
        XCTAssertEqual(RadialSelectionMath.action(for: .fullScreen), .maximize)
        XCTAssertEqual(RadialSelectionMath.action(for: .ring(2)), .rightHalf)
        XCTAssertNil(RadialSelectionMath.action(for: .none))
    }

    func testAngleHysteresisPreventsFlickerNearBoundary() {
        var state = RadialSelectionMath.SelectionState()
        _ = RadialSelectionMath.selection(from: CGPoint(x: 0, y: -50), state: &state)
        XCTAssertEqual(state.lastRingIndex, 0)
        let nearRight = RadialSelectionMath.selection(from: CGPoint(x: 12, y: -48), state: &state)
        XCTAssertEqual(nearRight, .ring(0))
    }

    func testAllSegmentsReachable() {
        var selections = Set<RadialSelectionMath.Selection>()
        for index in 0 ..< 8 {
            var state = RadialSelectionMath.SelectionState()
            let angle = RadialMenuLayout.canonicalAngleRadians(forRingIndex: index)
            let delta = CGPoint(x: sin(angle) * 50, y: -cos(angle) * 50)
            selections.insert(RadialSelectionMath.selection(from: delta, state: &state))
        }
        XCTAssertEqual(selections.count, 8)
    }

    func testSyntheticDeltaForKeyboardSelection() {
        let delta = RadialSelectionMath.syntheticDelta(for: .ring(2))
        var state = RadialSelectionMath.SelectionState()
        XCTAssertEqual(RadialSelectionMath.selection(from: delta, state: &state), .ring(2))
    }

    func testEdgeClampIgnoresInterMonitorEdge() {
        let left = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let right = CGRect(x: 1000, y: 0, width: 1000, height: 800)
        let desktop = left.union(right)
        let nearInternalEdge = CGPoint(x: 995, y: 400)
        var clamp = RadialSelectionMath.EdgeClamp(initial: nearInternalEdge, desktopBounds: desktop)
        let resolved = clamp.resolve(current: nearInternalEdge, deltaX: 10, deltaY: 0)
        XCTAssertEqual(resolved, nearInternalEdge)
    }

    func testEdgeClampCompensatesAtDesktopPerimeter() {
        let desktop = CGRect(x: 0, y: 0, width: 2000, height: 800)
        let atRightEdge = CGPoint(x: 1999, y: 400)
        var clamp = RadialSelectionMath.EdgeClamp(initial: atRightEdge, desktopBounds: desktop)
        let pinned = CGPoint(x: 2000, y: 400)
        let resolved = clamp.resolve(current: pinned, deltaX: 30, deltaY: 0)
        XCTAssertGreaterThan(resolved.x, pinned.x)
    }

    func testOuterBandDisplayDistanceUsesFullScreenRayWhileRingSelected() {
        let delta = CGPoint(x: 0, y: -140)
        let distance = RadialSelectionMath.displayDistance(for: delta, selection: .ring(0))
        XCTAssertEqual(distance, RadialPuckMetrics.fullScreenRayMaxRadius, accuracy: 0.001)
    }

    func testUsesCursorAimInOuterBandEvenWhenRingSelected() {
        let delta = CGPoint(x: 80, y: -120)
        XCTAssertTrue(RadialSelectionMath.usesCursorAim(for: delta, selection: .ring(1)))
        XCTAssertTrue(RadialSelectionMath.usesCursorAim(for: delta, selection: .fullScreen))
        XCTAssertFalse(RadialSelectionMath.usesCursorAim(for: CGPoint(x: 0, y: -50), selection: .ring(0)))
    }
}
