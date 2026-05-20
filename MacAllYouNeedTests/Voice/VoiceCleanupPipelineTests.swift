import Core
@testable import MacAllYouNeed
import XCTest

final class VoiceCleanupPipelineTests: XCTestCase {
    func testUsesLocalCleanupWhenProviderIsMissing() async {
        let pipeline = VoiceCleanupPipeline(provider: nil)

        let result = await pipeline.clean(VoiceCleanupRequest(
            rawText: "test一二三四，test，帮我修改一下这个。test嗯，ok。",
            appBundleID: "com.todesktop.230313mzl4w4u92",
            language: .mixed
        ))

        XCTAssertEqual(result.cleanedText, "test1234，test，帮我修改一下这个。test，ok。")
        XCTAssertFalse(result.usedLLM)
        XCTAssertNil(result.providerIdentifier)
    }

    func testProviderReceivesLocalCleanedText() async {
        let provider = SpyVoiceLLMProvider(output: "polished output")
        let pipeline = VoiceCleanupPipeline(provider: provider)

        let result = await pipeline.clean(VoiceCleanupRequest(
            rawText: "我今天要 deploy 这个 service。嗯",
            appBundleID: "com.apple.TextEdit",
            language: .mixed
        ))

        XCTAssertEqual(result.cleanedText, "polished output")
        XCTAssertTrue(result.usedLLM)
        XCTAssertEqual(result.providerIdentifier, "spy")
        let requests = await provider.requests
        XCTAssertEqual(requests.map(\.text), ["我今天要 deploy 这个 service。"])
        XCTAssertEqual(requests.map(\.rawText), ["我今天要 deploy 这个 service。嗯"])
    }

    func testFallsBackToLocalCleanupWhenProviderReturnsEmpty() async {
        let pipeline = VoiceCleanupPipeline(provider: SpyVoiceLLMProvider(output: "  \n "))

        let result = await pipeline.clean(VoiceCleanupRequest(
            rawText: "我今天要 deploy 这个 service。嗯",
            appBundleID: "com.apple.TextEdit",
            language: .mixed
        ))

        XCTAssertEqual(result.cleanedText, "我今天要 deploy 这个 service。")
        XCTAssertFalse(result.usedLLM)
        XCTAssertEqual(result.providerIdentifier, "spy")
    }

    func testSkipsProviderForShortTranscript() async {
        let provider = SpyVoiceLLMProvider(output: "should not be used")
        let pipeline = VoiceCleanupPipeline(provider: provider)

        let result = await pipeline.clean(VoiceCleanupRequest(
            rawText: "ok 嗯",
            appBundleID: nil,
            language: .english
        ))

        XCTAssertEqual(result.cleanedText, "ok")
        XCTAssertFalse(result.usedLLM)
        let requests = await provider.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testAppliesDictionaryAfterLocalCleanup() async {
        let pipeline = VoiceCleanupPipeline(provider: nil)

        let result = await pipeline.clean(VoiceCleanupRequest(
            rawText: "帮我改成海涛。",
            appBundleID: nil,
            language: .mixed,
            dictionaryEntries: [.fixture(phrase: "海涛", replacement: "江涛")]
        ))

        XCTAssertEqual(result.cleanedText, "帮我改成江涛。")
    }

    func testAppliesDictionaryAfterProviderCleanup() async {
        let pipeline = VoiceCleanupPipeline(provider: SpyVoiceLLMProvider(output: "请找海涛 review 这个 service。"))

        let result = await pipeline.clean(VoiceCleanupRequest(
            rawText: "请找海涛 review 这个 service。嗯",
            appBundleID: nil,
            language: .mixed,
            dictionaryEntries: [.fixture(phrase: "海涛", replacement: "江涛")]
        ))

        XCTAssertEqual(result.cleanedText, "请找江涛 review 这个 service。")
        XCTAssertTrue(result.usedLLM)
    }

    func testFallsBackWithDeadlineMetadataWhenProviderTimesOut() async {
        let pipeline = VoiceCleanupPipeline(
            provider: SlowVoiceLLMProvider(),
            timeout: .milliseconds(10)
        )

        let result = await pipeline.clean(VoiceCleanupRequest(
            rawText: "我今天要 deploy 这个 service，然后通知 product owner。",
            appBundleID: "com.apple.TextEdit",
            language: .mixed
        ))

        XCTAssertEqual(result.cleanedText, "我今天要 deploy 这个 service，然后通知 product owner。")
        XCTAssertFalse(result.usedLLM)
        XCTAssertEqual(result.providerIdentifier, "slow")
        XCTAssertEqual(result.fallbackReason, .deadlineExceeded)
        XCTAssertTrue(result.deadlineExceeded)
        XCTAssertGreaterThanOrEqual(result.cleanupMs, 0)
    }
}

private actor SpyVoiceLLMProvider: VoiceLLMProvider {
    nonisolated let providerIdentifier = "spy"
    private let output: String
    private(set) var requests: [VoiceLLMRequest] = []

    init(output: String) {
        self.output = output
    }

    func clean(_ request: VoiceLLMRequest) async throws -> String {
        requests.append(request)
        return output
    }
}

private struct SlowVoiceLLMProvider: VoiceLLMProvider {
    let providerIdentifier = "slow"

    func clean(_: VoiceLLMRequest) async throws -> String {
        try await Task.sleep(for: .milliseconds(200))
        return "late output"
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
