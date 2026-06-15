import Core
import XCTest
@testable import MacAllYouNeed

final class VoiceRecordingStartPlannerTests: XCTestCase {

    // MARK: - Local provider

    func test_localProvider_modelInstalled_streaming() {
        let caps = VoiceASRCapabilities(supportsStreaming: true, requiresNetwork: false, emitsPartials: false)
        let result = resolve(.local, keyPresent: false, online: true, installed: true, caps: caps)
        XCTAssertEqual(result, .start(provider: .local, mode: .streaming))
    }

    func test_localProvider_modelInstalled_batch() {
        let caps = VoiceASRCapabilities.batchOnly
        let result = resolve(.local, keyPresent: false, online: true, installed: true, caps: caps)
        XCTAssertEqual(result, .start(provider: .local, mode: .batch))
    }

    func test_localProvider_modelNotInstalled_blocked() {
        let result = resolve(.local, keyPresent: false, online: true, installed: false, caps: .batchOnly)
        XCTAssertEqual(result, .blocked(.localModelNotInstalled))
    }

    // MARK: - Cloud provider, key + online

    func test_cloudGroq_keyPresent_online() {
        let result = resolve(.groq, keyPresent: true, online: true, installed: true, caps: .batchOnly)
        XCTAssertEqual(result, .start(provider: .groq, mode: .batch))
    }

    func test_cloudOpenAI_keyPresent_online() {
        let result = resolve(.openAITranscribe, keyPresent: true, online: true, installed: true, caps: .batchOnly)
        XCTAssertEqual(result, .start(provider: .openAITranscribe, mode: .batch))
    }

    // MARK: - Cloud provider, offline fallback

    func test_cloudGroq_noNetwork_localInstalled_fallsBack() {
        let caps = VoiceASRCapabilities(supportsStreaming: true, requiresNetwork: false, emitsPartials: false)
        let result = resolve(.groq, keyPresent: true, online: false, installed: true, caps: caps)
        XCTAssertEqual(result, .start(provider: .local, mode: .streaming))
    }

    func test_cloudGroq_noNetwork_localNotInstalled_blocked() {
        let result = resolve(.groq, keyPresent: true, online: false, installed: false, caps: .batchOnly)
        XCTAssertEqual(result, .blocked(.localModelNotInstalled))
    }

    // MARK: - Cloud provider, no API key fallback

    func test_cloudGroq_noKey_localInstalled_fallsBack() {
        let result = resolve(.groq, keyPresent: false, online: true, installed: true, caps: .batchOnly)
        XCTAssertEqual(result, .start(provider: .local, mode: .batch))
    }

    func test_cloudGroq_noKey_offline_localNotInstalled_blocked() {
        let result = resolve(.groq, keyPresent: false, online: false, installed: false, caps: .batchOnly)
        XCTAssertEqual(result, .blocked(.localModelNotInstalled))
    }

    // MARK: - Helpers

    private func resolve(
        _ provider: VoiceASRProviderKind,
        keyPresent: Bool,
        online: Bool,
        installed: Bool,
        caps: VoiceASRCapabilities
    ) -> VoiceRecordingStartPlanner.Decision {
        VoiceRecordingStartPlanner.resolve(
            configured: provider,
            cloudKeyPresent: keyPresent,
            isOnline: online,
            localModelInstalled: installed,
            localEngineCapabilities: caps
        )
    }
}
