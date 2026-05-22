@testable import MacAllYouNeed
import XCTest

final class VoiceEnginePickerPresentationTests: XCTestCase {
    func testCurrentEngineIDUsesLocalSelectionWhenProviderIsLocal() {
        let engineID = VoiceEngineCatalogPresentation.currentEngineID(
            providerKind: .local,
            selectedLocalModelID: .qwen3ASR06BF32,
            selectedCloudModelID: .groqWhisperLargeV3Turbo
        )

        XCTAssertEqual(engineID, .local(.qwen3ASR06BF32))
    }

    func testCurrentEngineIDUsesCloudSelectionWhenProviderIsCloud() {
        let engineID = VoiceEngineCatalogPresentation.currentEngineID(
            providerKind: .openAITranscribe,
            selectedLocalModelID: .qwen3ASR06BF32,
            selectedCloudModelID: .openAIGPT4oTranscribe
        )

        XCTAssertEqual(engineID, .cloud(.openAIGPT4oTranscribe))
    }

    func testPickerEntriesContainLocalCloudAndExperimentalGroups() {
        let entries = VoiceEngineCatalogPresentation.pickerEntries()
        let groups = Set(entries.map(\.group))

        XCTAssertTrue(groups.contains(.local))
        XCTAssertTrue(groups.contains(.cloud))
        XCTAssertTrue(groups.contains(.experimental))
    }

    func testLocalFilterIncludesExperimentalEntries() {
        let entries = VoiceEngineCatalogPresentation.pickerEntries()
        let filtered = entries.filter { VoiceEngineCatalogPresentation.matchesFilter($0, filter: .local) }

        XCTAssertTrue(filtered.contains { $0.group == .local })
        XCTAssertTrue(filtered.contains { $0.group == .experimental })
        XCTAssertFalse(filtered.contains { $0.group == .cloud })
    }
}
