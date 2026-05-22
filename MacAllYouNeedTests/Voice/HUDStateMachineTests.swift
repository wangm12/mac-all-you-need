@testable import MacAllYouNeed
import XCTest

/// Verifies every (starting phase × event) → expected ending phase combination
/// for the pure HUDStateMachine. No AppKit dependencies.
final class HUDStateMachineTests: XCTestCase {
    // MARK: - Happy-path forward transitions

    func testIdleToRecording_onBeginRecording() {
        var sm = HUDStateMachine(phase: .idle)
        XCTAssertTrue(sm.apply(.beginRecording))
        XCTAssertEqual(sm.phase, .recording)
    }

    func testRecordingToTranscribing_onBeginTranscribing() {
        var sm = HUDStateMachine(phase: .recording)
        XCTAssertTrue(sm.apply(.beginTranscribing))
        XCTAssertEqual(sm.phase, .transcribing)
    }

    func testTranscribingToThinking_onBeginThinking() {
        var sm = HUDStateMachine(phase: .transcribing)
        XCTAssertTrue(sm.apply(.beginThinking))
        XCTAssertEqual(sm.phase, .thinking)
    }

    func testRecordingDirectlyToThinking_whenAsrSkippedViaUndoReplay() {
        // Undo replay path: presetASRResult was provided so the HUD jumps
        // straight to .thinking without surfacing .transcribing.
        var sm = HUDStateMachine(phase: .recording)
        XCTAssertTrue(sm.apply(.beginThinking))
        XCTAssertEqual(sm.phase, .thinking)
    }

    func testThinkingToPasting_onBeginPasting() {
        var sm = HUDStateMachine(phase: .thinking)
        XCTAssertTrue(sm.apply(.beginPasting))
        XCTAssertEqual(sm.phase, .pasting)
    }

    func testPastingToApplied_onCompletedPaste() {
        var sm = HUDStateMachine(phase: .pasting)
        XCTAssertTrue(sm.apply(.completedPaste))
        XCTAssertEqual(sm.phase, .applied)
    }

    // MARK: - Stop is always cancel (never advances)

    func testStopFromRecording_lands_onCancelled() {
        var sm = HUDStateMachine(phase: .recording)
        XCTAssertTrue(sm.apply(.stop))
        XCTAssertEqual(sm.phase, .cancelled,
                       "Stop button must cancel — never advance to transcribe")
    }

    func testStopFromTranscribing_lands_onCancelled() {
        var sm = HUDStateMachine(phase: .transcribing)
        XCTAssertTrue(sm.apply(.stop))
        XCTAssertEqual(sm.phase, .cancelled)
    }

    func testStopFromThinking_lands_onCancelled() {
        var sm = HUDStateMachine(phase: .thinking)
        XCTAssertTrue(sm.apply(.stop))
        XCTAssertEqual(sm.phase, .cancelled)
    }

    func testStopFromIdle_isRejected() {
        var sm = HUDStateMachine(phase: .idle)
        XCTAssertFalse(sm.apply(.stop))
        XCTAssertEqual(sm.phase, .idle)
    }

    func testStopFromApplied_isRejected() {
        var sm = HUDStateMachine(phase: .applied)
        XCTAssertFalse(sm.apply(.stop))
        XCTAssertEqual(sm.phase, .applied)
    }

    func testStopFromCancelled_isRejected() {
        var sm = HUDStateMachine(phase: .cancelled)
        XCTAssertFalse(sm.apply(.stop))
        XCTAssertEqual(sm.phase, .cancelled)
    }

    func testStopFromError_isRejected() {
        var sm = HUDStateMachine(phase: .error("boom"))
        XCTAssertFalse(sm.apply(.stop))
        XCTAssertEqual(sm.phase, .error("boom"))
    }

    // MARK: - Dismiss always lands on .idle

    func testDismissFromIdle_staysIdle() {
        var sm = HUDStateMachine(phase: .idle)
        XCTAssertTrue(sm.apply(.dismiss))
        XCTAssertEqual(sm.phase, .idle)
    }

    func testDismissFromApplied_landsIdle() {
        var sm = HUDStateMachine(phase: .applied)
        XCTAssertTrue(sm.apply(.dismiss))
        XCTAssertEqual(sm.phase, .idle)
    }

    func testDismissFromCancelled_landsIdle() {
        var sm = HUDStateMachine(phase: .cancelled)
        XCTAssertTrue(sm.apply(.dismiss))
        XCTAssertEqual(sm.phase, .idle)
    }

    func testDismissFromError_landsIdle() {
        var sm = HUDStateMachine(phase: .error("boom"))
        XCTAssertTrue(sm.apply(.dismiss))
        XCTAssertEqual(sm.phase, .idle)
    }

    // MARK: - Fail always lands on .error

    func testFailFromRecording_landsError() {
        var sm = HUDStateMachine(phase: .recording)
        XCTAssertTrue(sm.apply(.fail("mic failed")))
        XCTAssertEqual(sm.phase, .error("mic failed"))
    }

    func testFailFromTranscribing_landsError() {
        var sm = HUDStateMachine(phase: .transcribing)
        XCTAssertTrue(sm.apply(.fail("asr blew up")))
        XCTAssertEqual(sm.phase, .error("asr blew up"))
    }

    // MARK: - Illegal direct transitions rejected

    func testIdleToTranscribing_isRejected() {
        var sm = HUDStateMachine(phase: .idle)
        XCTAssertFalse(sm.apply(.beginTranscribing))
        XCTAssertEqual(sm.phase, .idle)
    }

    func testAppliedToRecording_isRejected() {
        var sm = HUDStateMachine(phase: .applied)
        XCTAssertFalse(sm.apply(.beginRecording))
        XCTAssertEqual(sm.phase, .applied)
    }

    func testRecordingToPasting_isRejected() {
        var sm = HUDStateMachine(phase: .recording)
        XCTAssertFalse(sm.apply(.beginPasting))
        XCTAssertEqual(sm.phase, .recording)
    }

    // MARK: - isStoppable helper

    func testIsStoppable_trueForRecordingTranscribingThinking() {
        for phase in [HUDStateMachine.Phase.recording, .transcribing, .thinking] {
            XCTAssertTrue(HUDStateMachine(phase: phase).isStoppable,
                          "\(phase) must be stoppable")
        }
    }

    func testIsStoppable_falseForIdleAndTerminalPhases() {
        for phase in [
            HUDStateMachine.Phase.idle,
            .pasting,
            .applied,
            .cancelled,
            .error("x")
        ] {
            XCTAssertFalse(HUDStateMachine(phase: phase).isStoppable,
                           "\(phase) must NOT be stoppable")
        }
    }
}
