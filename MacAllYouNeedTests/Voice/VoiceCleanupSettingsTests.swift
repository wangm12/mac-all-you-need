import Core
@testable import MacAllYouNeed
import XCTest

final class VoiceCleanupSettingsTests: XCTestCase {
    func testDefaultSettingsKeepLLMDisabled() {
        XCTAssertEqual(VoiceCleanupSettings.default.isEnabled, false)
        XCTAssertEqual(VoiceCleanupSettings.default.provider, .anthropic)
        XCTAssertGreaterThan(VoiceCleanupSettings.default.timeoutSeconds, 0)
    }

    func testSavesAndLoadsSettingsWithoutAPIKey() throws {
        let suiteName = "VoiceCleanupSettings-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = VoiceCleanupSettings(
            isEnabled: true,
            provider: .openAICompatible,
            model: "gpt-test",
            baseURLString: "https://llm.example/v1",
            timeoutSeconds: 3
        )

        VoiceCleanupSettingsStore.save(settings, to: defaults)

        XCTAssertEqual(VoiceCleanupSettingsStore.load(from: defaults), settings)
        XCTAssertNil(defaults.string(forKey: "apiKey"))
        XCTAssertFalse(try XCTUnwrap(try String(data: XCTUnwrap(defaults.data(forKey: "voice.cleanup.settings.v1")), encoding: .utf8))
            .contains("secret"))
    }

    func testKeyStoreSavesLoadsAndDeletesProviderKey() throws {
        let keychain = InMemoryKeychain()
        let store = VoiceCleanupKeyStore(keychain: keychain)

        try store.saveAPIKey("secret", for: .anthropic)
        XCTAssertEqual(try store.apiKey(for: .anthropic), "secret")

        try store.saveAPIKey("", for: .anthropic)
        XCTAssertNil(try store.apiKey(for: .anthropic))
    }

    func testProviderFactoryRequiresKeyForCloudProvider() throws {
        let settings = VoiceCleanupSettings(
            isEnabled: true,
            provider: .anthropic,
            model: "claude-test",
            baseURLString: "https://api.anthropic.com",
            timeoutSeconds: 7
        )

        XCTAssertNil(try VoiceCleanupProviderFactory.makeProvider(
            settings: settings,
            keyStore: VoiceCleanupKeyStore(keychain: InMemoryKeychain())
        ))
    }

    func testProviderFactoryBuildsCloudProviderWhenKeyExists() throws {
        let keychain = InMemoryKeychain()
        let keyStore = VoiceCleanupKeyStore(keychain: keychain)
        try keyStore.saveAPIKey("secret", for: .openAICompatible)
        let settings = VoiceCleanupSettings(
            isEnabled: true,
            provider: .openAICompatible,
            model: "gpt-test",
            baseURLString: "https://llm.example/v1",
            timeoutSeconds: 7
        )

        let provider = try VoiceCleanupProviderFactory.makeProvider(settings: settings, keyStore: keyStore)

        XCTAssertEqual(provider?.providerIdentifier, "openai-compatible")
    }

    func testProviderFactoryBuildsDraftProviderFromUnsavedAPIKey() throws {
        let settings = VoiceCleanupSettings(
            isEnabled: true,
            provider: .anthropic,
            model: "claude-test",
            baseURLString: "https://api.anthropic.com",
            timeoutSeconds: 7
        )

        let provider = try VoiceCleanupProviderFactory.makeProvider(settings: settings, apiKey: "draft-key")

        XCTAssertEqual(provider?.providerIdentifier, "anthropic")
    }
}
