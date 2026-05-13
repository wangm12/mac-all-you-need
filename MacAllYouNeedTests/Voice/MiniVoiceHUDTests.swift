@testable import MacAllYouNeed
import XCTest

final class MiniVoiceHUDTests: XCTestCase {
    func testHUDUsesCompactTypelessStyleLayout() {
        XCTAssertLessThanOrEqual(MiniVoiceHUDLayout.panelSize.width, 172)
        XCTAssertLessThanOrEqual(MiniVoiceHUDLayout.panelSize.height, 78)
        XCTAssertLessThanOrEqual(MiniVoiceHUDLayout.controlWidth, 132)
    }

    func testTipOnlyAppearsForVoiceEntryStates() {
        XCTAssertEqual(MiniVoiceHUDPresentationState(state: .idlePreview).tipTitle, "Ask anything")
        XCTAssertEqual(MiniVoiceHUDPresentationState(state: .recording(level: 0.4)).tipTitle, "Ask anything")
        XCTAssertNil(MiniVoiceHUDPresentationState(state: .transcribing).tipTitle)
        XCTAssertNil(MiniVoiceHUDPresentationState(state: .pasted).tipTitle)
        XCTAssertNil(MiniVoiceHUDPresentationState(state: .noSpeech("empty")).tipTitle)
        XCTAssertNil(MiniVoiceHUDPresentationState(state: .error("failed")).tipTitle)
    }

    func testPanelCollapsesToPillWhenTipIsHidden() {
        let recordingSize = MiniVoiceHUDLayout.size(for: .recording(level: 0.4))
        let transcribingSize = MiniVoiceHUDLayout.size(for: .transcribing)

        XCTAssertGreaterThan(recordingSize.height, transcribingSize.height)
        XCTAssertLessThanOrEqual(transcribingSize.height, 48)
    }

    func testRecordingActionsEnableCancelAndStop() {
        let actions = MiniVoiceHUDActionState(state: .recording(level: 0.4))

        XCTAssertTrue(actions.cancelEnabled)
        XCTAssertTrue(actions.primaryEnabled)
        XCTAssertEqual(actions.primarySymbol, "stop.fill")
        XCTAssertEqual(actions.primaryAccessibilityLabel, "Stop and transcribe")
    }

    func testTranscribingActionsEnableCancelOnly() {
        let actions = MiniVoiceHUDActionState(state: .transcribing)

        XCTAssertTrue(actions.cancelEnabled)
        XCTAssertFalse(actions.primaryEnabled)
        XCTAssertEqual(actions.primarySymbol, "hourglass")
        XCTAssertEqual(actions.primaryAccessibilityLabel, "Transcribing")
    }

    func testPastedActionsEnableCheckDismissOnly() {
        let actions = MiniVoiceHUDActionState(state: .pasted)

        XCTAssertFalse(actions.cancelEnabled)
        XCTAssertTrue(actions.primaryEnabled)
        XCTAssertEqual(actions.primarySymbol, "checkmark")
        XCTAssertEqual(actions.primaryAccessibilityLabel, "Dismiss")
    }
}
