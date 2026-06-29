import XCTest
@testable import MacAllYouNeed

final class VoiceHUDCopyTests: XCTestCase {
    func testBlockingAlertForPermission() {
        let alert = VoiceHUDCopy.blockingAlert(for: "Microphone permission denied")
        XCTAssertEqual(alert?.title, VoiceHUDCopy.Blocking.micPermissionTitle)
    }

    func testTranscribeFailureUsesCaptionInsteadOfBlockingAlert() {
        XCTAssertNil(VoiceHUDCopy.blockingAlert(for: "Couldn't transcribe"))
        XCTAssertNil(VoiceHUDCopy.captionMessage(forFailure: "Couldn't transcribe"))
        XCTAssertNil(VoiceHUDCopy.captionMessage(forFailure: "ASR failed"))
        XCTAssertEqual(
            VoiceHUDCopy.pillLabel(for: "ASR failed"),
            VoiceHUDCopy.Pill.couldntTranscribe
        )
    }

    func testAvailabilityFailureUsesDetailedCaptionOnly() {
        let message = "No ASR model installed. Download a model from Voice → Models before dictating."
        XCTAssertEqual(
            VoiceHUDCopy.captionMessage(forFailure: message),
            message
        )
        XCTAssertEqual(VoiceHUDCopy.pillLabel(for: message), VoiceHUDCopy.Pill.voiceUnavailable)
    }

    func testPillLabelMapsPasteFailureToCouldntPaste() {
        XCTAssertEqual(VoiceHUDCopy.pillLabel(for: "Paste timed out"), VoiceHUDCopy.Pill.couldntPaste)
    }

    func testCaptionPriorityOrdering() {
        XCTAssertTrue(VoiceHUDCopy.Priority.blocking < VoiceHUDCopy.Priority.education)
        XCTAssertTrue(VoiceHUDCopy.Priority.terminal < VoiceHUDCopy.Priority.sessionInfo)
    }
}
