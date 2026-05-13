import Core
@testable import MacAllYouNeed
import XCTest

final class VoicePromptBuilderTests: XCTestCase {
    func testBuildsMixedLanguageCleanupPromptWithAppAndDictionaryContext() {
        let prompt = VoicePromptBuilder.systemPrompt(context: VoicePromptContext(
            language: .mixed,
            appBundleID: "com.todesktop.230313mzl4w4u92",
            dictionaryEntries: [.fixture(phrase: "海涛", replacement: "江涛")],
            translationTarget: nil
        ))

        XCTAssertTrue(prompt.contains("zh+en mixed"))
        XCTAssertTrue(prompt.contains("com.todesktop.230313mzl4w4u92"))
        XCTAssertTrue(prompt.contains("海涛 -> 江涛"))
        XCTAssertTrue(prompt.contains("Return only the final cleaned text"))
    }

    func testBuildsTranslationInstructionWhenTargetLanguageIsSet() {
        let prompt = VoicePromptBuilder.systemPrompt(context: VoicePromptContext(
            language: .chinese,
            appBundleID: nil,
            dictionaryEntries: [],
            translationTarget: .english,
            appInstructions: nil
        ))

        XCTAssertTrue(prompt.contains("translate"))
        XCTAssertTrue(prompt.contains("English"))
    }

    func testIncludesAppSpecificInstructionsWhenPresent() {
        let prompt = VoicePromptBuilder.systemPrompt(context: VoicePromptContext(
            language: .mixed,
            appBundleID: "com.todesktop.230313mzl4w4u92",
            dictionaryEntries: [],
            translationTarget: nil,
            appInstructions: "Format as a concise Git commit message."
        ))

        XCTAssertTrue(prompt.contains("App-specific instructions:"))
        XCTAssertTrue(prompt.contains("Format as a concise Git commit message."))
    }

    func testWrapsTranscriptInUserPromptTags() {
        XCTAssertEqual(
            VoicePromptBuilder.userPrompt(transcript: "我今天要 deploy。"),
            "<TRANSCRIPT>我今天要 deploy。</TRANSCRIPT>"
        )
    }
}

private extension VoiceDictionaryEntry {
    static func fixture(phrase: String, replacement: String) -> VoiceDictionaryEntry {
        VoiceDictionaryEntry(
            id: UUID().uuidString,
            phrase: phrase,
            replacement: replacement,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
    }
}
