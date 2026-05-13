@testable import MacAllYouNeed
import XCTest

final class VoiceOnboardingStepTests: XCTestCase {
    func testTryItCanBeSkippedWhenMachineTranscriptFails() {
        XCTAssertTrue(VoiceOnboardingStep.tryIt.canSkip)
    }

    func testWelcomeAndDoneCannotBeSkipped() {
        XCTAssertFalse(VoiceOnboardingStep.welcome.canSkip)
        XCTAssertFalse(VoiceOnboardingStep.done.canSkip)
    }
}
