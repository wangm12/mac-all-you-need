import XCTest
@testable import MacAllYouNeed

final class VoiceHUDCopyTests: XCTestCase {
    func testBlockingAlertForPermission() {
        let alert = VoiceHUDCopy.blockingAlert(for: "Microphone permission denied")
        XCTAssertEqual(alert?.title, VoiceHUDCopy.Blocking.micPermissionTitle)
    }

    func testPillLabelMapsPasteFailureToCouldntPaste() {
        XCTAssertEqual(VoiceHUDCopy.pillLabel(for: "Paste timed out"), VoiceHUDCopy.Pill.couldntPaste)
    }

    func testCaptionPriorityOrdering() {
        XCTAssertTrue(VoiceHUDCopy.Priority.blocking < VoiceHUDCopy.Priority.education)
        XCTAssertTrue(VoiceHUDCopy.Priority.terminal < VoiceHUDCopy.Priority.sessionInfo)
    }
}
