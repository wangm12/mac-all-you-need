@testable import MacAllYouNeed
import XCTest

final class MiniVoiceHUDTests: XCTestCase {
    func testHUDUsesCompactTypelessStyleLayout() {
        XCTAssertLessThanOrEqual(MiniVoiceHUDLayout.panelSize.width, 172)
        XCTAssertLessThanOrEqual(MiniVoiceHUDLayout.panelSize.height, 78)
        XCTAssertLessThanOrEqual(MiniVoiceHUDLayout.controlWidth, 132)
    }

    func testTipNeverAppearsInCompactVoiceHUD() {
        XCTAssertNil(MiniVoiceHUDPresentationState(state: .idlePreview).tipTitle)
        XCTAssertNil(MiniVoiceHUDPresentationState(state: .recording(level: 0.4)).tipTitle)
        XCTAssertNil(MiniVoiceHUDPresentationState(state: .transcribing).tipTitle)
        XCTAssertNil(MiniVoiceHUDPresentationState(state: .pasted).tipTitle)
        XCTAssertNil(MiniVoiceHUDPresentationState(state: .noSpeech("empty")).tipTitle)
        XCTAssertNil(MiniVoiceHUDPresentationState(state: .error("failed")).tipTitle)
    }

    func testPanelUsesPillSizeForRecordingAndTranscribing() {
        let recordingSize = MiniVoiceHUDLayout.size(for: .recording(level: 0.4))
        let transcribingSize = MiniVoiceHUDLayout.size(for: .transcribing)

        XCTAssertEqual(recordingSize, CGSize(width: MiniVoiceHUDLayout.controlWidth, height: MiniVoiceHUDLayout.controlHeight))
        XCTAssertEqual(transcribingSize, CGSize(width: MiniVoiceHUDLayout.controlWidth, height: MiniVoiceHUDLayout.controlHeight))
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
