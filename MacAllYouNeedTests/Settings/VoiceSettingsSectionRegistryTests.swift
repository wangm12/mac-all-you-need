import XCTest
@testable import MacAllYouNeed

/// Pins the ordered list of section types and their user-visible header strings
/// for the Voice Settings page decomposition.
final class VoiceSettingsSectionRegistryTests: XCTestCase {

    // MARK: - Section type name ordering

    func testSectionTypeNamesAreInExpectedOrder() {
        let expected = [
            "VoiceAPIKeySection",
            "VoiceDictionarySection",
            "VoicePersonalizationSection",
            "VoiceTrainingExamplesSection",
        ]
        XCTAssertEqual(VoiceSettingsSectionRegistry.orderedTypeNames, expected)
    }

    // MARK: - Section header strings

    func testAPIKeySectionHeader() {
        XCTAssertEqual(VoiceSettingsSectionRegistry.headers[.apiKey], "API Key Setup")
    }

    func testDictionarySectionHeader() {
        XCTAssertEqual(VoiceSettingsSectionRegistry.headers[.dictionary], "Dictionary")
    }

    func testPersonalizationSectionHeader() {
        XCTAssertEqual(VoiceSettingsSectionRegistry.headers[.personalization], "Personalization")
    }

    func testTrainingExamplesSectionHeader() {
        XCTAssertEqual(VoiceSettingsSectionRegistry.headers[.trainingExamples], "Training Examples")
    }
}
