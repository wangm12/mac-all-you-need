@testable import MacAllYouNeed
import XCTest

final class VoiceRecordingMicReadinessTests: XCTestCase {
    func testHoldModeStopsWhenHotkeyReleasedDuringMicPrep() {
        XCTAssertTrue(
            VoiceRecordingMicReadiness.shouldStopImmediatelyAfterPrep(
                mode: .hold,
                isHotkeyHeld: false
            )
        )
    }

    func testHoldModeContinuesWhenHotkeyStillHeld() {
        XCTAssertFalse(
            VoiceRecordingMicReadiness.shouldStopImmediatelyAfterPrep(
                mode: .hold,
                isHotkeyHeld: true
            )
        )
    }

    func testToggleModeIgnoresHotkeyHeldState() {
        XCTAssertFalse(
            VoiceRecordingMicReadiness.shouldStopImmediatelyAfterPrep(
                mode: .toggle,
                isHotkeyHeld: false
            )
        )
    }
}
