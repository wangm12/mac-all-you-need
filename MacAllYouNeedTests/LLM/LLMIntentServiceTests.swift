import Core
@testable import MacAllYouNeed
import XCTest

final class FakeLLMProvider: VoiceLLMProvider, @unchecked Sendable {
    let providerIdentifier = "fake"
    private(set) var lastRequest: VoiceLLMRequest?
    var response = "CLEANED"
    func clean(_ request: VoiceLLMRequest) async throws -> String {
        lastRequest = request; return response
    }
}

final class LLMIntentServiceTests: XCTestCase {
    func testReturnsNilWhenNoProviderConfigured() async {
        let service = LLMIntentService(makeProvider: { nil })
        let result = await service.run(template: .voiceCleanup, input: "hello world this is a test", voiceContext: .init(language: .english, appBundleID: nil, dictionaryEntries: [], translationTarget: nil))
        XCTAssertNil(result)
    }
    func testRoutesInputThroughConfiguredProvider() async {
        let fake = FakeLLMProvider()
        let service = LLMIntentService(makeProvider: { fake })
        let result = await service.run(template: .voiceCleanup, input: "hello world this is a test", voiceContext: .init(language: .english, appBundleID: nil, dictionaryEntries: [], translationTarget: nil))
        XCTAssertEqual(result, "CLEANED")
        XCTAssertEqual(fake.lastRequest?.text, "hello world this is a test")
    }
}
