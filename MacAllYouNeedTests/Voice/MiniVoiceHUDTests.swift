@testable import MacAllYouNeed
import XCTest

final class MiniVoiceHUDTests: XCTestCase {
    func testV7UniversalPillSize() {
        XCTAssertEqual(MiniVoiceHUDLayout.pillWidth, 144)
        XCTAssertEqual(MiniVoiceHUDLayout.pillHeight, 32)
        XCTAssertEqual(MiniVoiceHUDLayout.iconSize, 14)
        XCTAssertEqual(MiniVoiceHUDLayout.leftSlotCenter, 20)
        XCTAssertEqual(MiniVoiceHUDLayout.rightSlotCenter, 124)
    }

    func testAllStatesShareUniversalPillSize() {
        let expected = CGSize(width: 144, height: 32)
        for state in [
            MiniVoiceHUD.State.recording(level: 0.4),
            .transcribing,
            .thinking,
            .pasted,
            .copied,
            .cancelled,
            .noSpeech("x"),
            .error("y"),
            .idlePreview
        ] {
            XCTAssertEqual(MiniVoiceHUDLayout.size(for: state), expected,
                           "state \(state) must use universal v7 pill size")
        }
    }

    func testRecordingMapsToListeningWithWaveformAndStopAction() {
        let pill = MiniVoiceHUDPill(state: .recording(level: 0.4))

        XCTAssertEqual(pill.label, "Listening")
        XCTAssertEqual(pill.leading, .waveformBars)
        XCTAssertTrue(pill.isStoppable)
        XCTAssertFalse(pill.isTerminal)
    }

    func testTranscribingPillUsesAISparkleAndIsStoppable() {
        let pill = MiniVoiceHUDPill(state: .transcribing)

        XCTAssertEqual(pill.label, "Transcribing")
        XCTAssertEqual(pill.leading, .aiSparkle)
        XCTAssertTrue(pill.isStoppable)
        XCTAssertFalse(pill.isTerminal)
    }

    func testThinkingPillUsesDotSpinnerAndIsStoppable() {
        let pill = MiniVoiceHUDPill(state: .thinking)

        XCTAssertEqual(pill.label, "Thinking")
        XCTAssertEqual(pill.leading, .dotSpinner)
        XCTAssertTrue(pill.isStoppable)
        XCTAssertFalse(pill.isTerminal)
    }

    func testPastedMapsToAppliedCheckPill() {
        let pill = MiniVoiceHUDPill(state: .pasted)

        XCTAssertEqual(pill.label, "Applied")
        XCTAssertEqual(pill.leading, .checkInCircle)
        XCTAssertFalse(pill.isStoppable)
        XCTAssertTrue(pill.isTerminal)
    }

    func testCopiedMapsToCopiedCheckPill() {
        let pill = MiniVoiceHUDPill(state: .copied)

        XCTAssertEqual(pill.label, "Copied")
        XCTAssertEqual(pill.leading, .checkInCircle)
        XCTAssertFalse(pill.isStoppable)
        XCTAssertTrue(pill.isTerminal)
    }

    func testNoSpeechPillUsesWarningTriangle() {
        let pill = MiniVoiceHUDPill(state: .noSpeech("anything"))

        XCTAssertEqual(pill.label, "No speech")
        XCTAssertEqual(pill.leading, .warningTriangle)
        XCTAssertFalse(pill.isStoppable)
        XCTAssertTrue(pill.isTerminal)
    }

    func testErrorPillMapsToFailedWithWarningTriangle() {
        let pill = MiniVoiceHUDPill(state: .error("some api blew up"))

        XCTAssertEqual(pill.label, "Failed")
        XCTAssertEqual(pill.leading, .warningTriangle)
        XCTAssertFalse(pill.isStoppable)
        XCTAssertTrue(pill.isTerminal)
    }

    func testNoUsableAudioErrorMessageDemotesToNoSpeechPill() {
        let pill = MiniVoiceHUDPill(state: .error("No usable audio captured"))

        XCTAssertEqual(pill.label, "No speech")
        XCTAssertEqual(pill.leading, .warningTriangle)
    }

    func testTranscriptWasEmptyErrorMessageDemotesToNoSpeechPill() {
        let pill = MiniVoiceHUDPill(state: .error("Transcript was empty"))

        XCTAssertEqual(pill.label, "No speech")
        XCTAssertEqual(pill.leading, .warningTriangle)
    }

    func testCancelledPillUsesXInCircleAndOffersUndo() {
        let pill = MiniVoiceHUDPill(state: .cancelled)

        XCTAssertEqual(pill.label, "Cancelled")
        XCTAssertEqual(pill.leading, .xInCircle)
        XCTAssertFalse(pill.isStoppable)
        XCTAssertFalse(pill.isTerminal)
        XCTAssertTrue(pill.isUndoable)
    }

    func testCancelledStateSharesUniversalPillSize() {
        XCTAssertEqual(MiniVoiceHUDLayout.size(for: .cancelled),
                       CGSize(width: 144, height: 32))
    }

    @MainActor
    func testVisibleLevelUpdatesReuseContentView() {
        let hud = MiniVoiceHUD()
        hud.show(.recording(level: 0.1), onCancel: {}, onPrimary: {})
        let firstContentView = hud.testingContentView

        hud.show(.recording(level: 0.5), onCancel: {}, onPrimary: {})

        XCTAssertTrue(hud.testingContentView === firstContentView)
        hud.dismiss()
    }
}
