import Core
@testable import MacAllYouNeed
import XCTest

final class LLMIntentTemplateTests: XCTestCase {
    func testVoiceCleanupTemplateMatchesVoicePromptBuilder() {
        let ctx = VoicePromptContext(language: .english, appBundleID: nil, dictionaryEntries: [], translationTarget: nil)
        let expected = VoicePromptBuilder.systemPrompt(context: ctx)
        let rendered = LLMIntentTemplate.voiceCleanup.systemPrompt(voiceContext: ctx)
        XCTAssertEqual(rendered, expected)
    }
    func testUserPromptWrapsInput() {
        let user = LLMIntentTemplate.voiceCleanup.userPrompt(input: "hello")
        XCTAssertEqual(user, VoicePromptBuilder.userPrompt(transcript: "hello"))
    }
}
