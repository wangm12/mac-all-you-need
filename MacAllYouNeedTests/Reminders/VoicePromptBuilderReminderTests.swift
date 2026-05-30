@testable import MacAllYouNeed
import XCTest

final class VoicePromptBuilderReminderTests: XCTestCase {
    func testReminderSystemPromptIsNonEmpty() {
        XCTAssertFalse(VoicePromptBuilder.reminderSystemPrompt().isEmpty)
    }

    func testReminderUserPromptIncludesTranscript() {
        let p = VoicePromptBuilder.reminderUserPrompt(transcript: "call dentist")
        XCTAssertTrue(p.contains("call dentist"))
    }
}
