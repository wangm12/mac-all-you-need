import Core
import CoreGraphics
@testable import MacAllYouNeed
import XCTest

@MainActor
final class RadialPuckAnimationStateTests: XCTestCase {
    func testSnapPreviewSetsFrameAndOpacity() {
        let state = RadialPuckAnimationState()
        let frame = CGRect(x: 10, y: 20, width: 400, height: 300)
        state.snapPreview(to: frame)
        XCTAssertEqual(state.renderState.dampedPreviewFrame, frame)
        XCTAssertEqual(state.renderState.previewOpacity, 1)
    }

    func testIdleAimAngleStartsAtUp() {
        let state = RadialPuckAnimationState()
        XCTAssertEqual(state.renderState.aimAngle, 0, accuracy: 0.001)
    }

    func testTickUsesCanonicalAngleForRingSelection() {
        let state = RadialPuckAnimationState()
        let now = Date.timeIntervalSinceReferenceDate
        state.tick(
            now: now,
            selection: .ring(2),
            cursorDelta: CGPoint(x: 40, y: 0),
            labelText: "Right",
            previewFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
            reduceMotion: true,
            allowsIdleBreath: false
        )
        let expected = RadialMenuLayout.canonicalAngleRadians(forRingIndex: 2)
        XCTAssertEqual(state.renderState.aimAngle, expected, accuracy: 0.001)
    }

    func testTickUsesCursorAngleForFullScreenSelection() {
        let state = RadialPuckAnimationState()
        let now = Date.timeIntervalSinceReferenceDate
        let delta = CGPoint(x: 100, y: 0)
        state.tick(
            now: now,
            selection: .fullScreen,
            cursorDelta: delta,
            labelText: "Fill Screen",
            previewFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
            reduceMotion: true,
            allowsIdleBreath: false
        )
        let expected = RadialSelectionMath.aimAngleRadians(for: delta)
        XCTAssertEqual(state.renderState.aimAngle, expected, accuracy: 0.001)
    }

    func testFullScreenTracksCursorWhileDragging() {
        let state = RadialPuckAnimationState()
        var now = Date.timeIntervalSinceReferenceDate
        for _ in 0 ..< 30 {
            state.tick(
                now: now,
                selection: .fullScreen,
                cursorDelta: CGPoint(x: 50, y: 0),
                labelText: "Fill Screen",
                previewFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
                reduceMotion: false,
                allowsIdleBreath: false
            )
            now += 1.0 / 60.0
        }
        let right = RadialSelectionMath.aimAngleRadians(for: CGPoint(x: 50, y: 0))
        XCTAssertEqual(state.renderState.aimAngle, right, accuracy: 0.02)

        for _ in 0 ..< 45 {
            state.tick(
                now: now,
                selection: .fullScreen,
                cursorDelta: CGPoint(x: 0, y: -140),
                labelText: "Fill Screen",
                previewFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
                reduceMotion: false,
                allowsIdleBreath: false
            )
            now += 1.0 / 60.0
        }
        let up = RadialSelectionMath.aimAngleRadians(for: CGPoint(x: 0, y: -140))
        XCTAssertEqual(state.renderState.aimAngle, up, accuracy: 0.05)
    }

    func testAnimatedFullScreenTransitionDoesNotTakeLongArc() {
        let state = RadialPuckAnimationState()
        var now = Date.timeIntervalSinceReferenceDate
        state.tick(
            now: now,
            selection: .ring(0),
            cursorDelta: CGPoint(x: 0, y: -50),
            labelText: "Top Half",
            previewFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
            reduceMotion: false,
            allowsIdleBreath: false
        )
        let startAngle = state.renderState.aimAngle

        now += 1.0 / 60.0
        state.tick(
            now: now,
            selection: .fullScreen,
            cursorDelta: CGPoint(x: 80, y: -120),
            labelText: "Fill Screen",
            previewFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
            reduceMotion: false,
            allowsIdleBreath: false
        )
        let delta = abs(state.renderState.aimAngle - startAngle)
        let wrappedDelta = min(delta, 2 * .pi - delta)
        XCTAssertLessThan(wrappedDelta, .pi / 4)
    }

    func testOuterBandRingSelectionUsesCursorAngle() {
        let state = RadialPuckAnimationState()
        let now = Date.timeIntervalSinceReferenceDate
        let delta = CGPoint(x: 80, y: -120)
        state.tick(
            now: now,
            selection: .ring(0),
            cursorDelta: delta,
            labelText: "Top Half",
            previewFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
            reduceMotion: true,
            allowsIdleBreath: false
        )
        let expected = RadialSelectionMath.aimAngleRadians(for: delta)
        XCTAssertEqual(state.renderState.aimAngle, expected, accuracy: 0.001)
    }
}
