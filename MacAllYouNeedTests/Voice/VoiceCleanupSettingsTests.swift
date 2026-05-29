import Core
@testable import MacAllYouNeed
import XCTest

final class VoiceCleanupSettingsTests: XCTestCase {
    func testDefaultSettingsKeepLLMDisabled() {
        XCTAssertEqual(VoiceCleanupSettings.default.isEnabled, false)
        XCTAssertEqual(VoiceCleanupSettings.default.provider, .anthropic)
        XCTAssertGreaterThan(VoiceCleanupSettings.default.timeoutSeconds, 0)
        XCTAssertEqual(VoiceCleanupSettings.default.latencyPolicy, .balanced2s)
    }

    func testDecodesLegacySettingsWithBalancedLatencyPolicy() throws {
        let data = Data("""
        {
          "isEnabled": true,
          "provider": "openAICompatible",
          "model": "gpt-test",
          "baseURLString": "https://llm.example/v1",
          "timeoutSeconds": 7
        }
        """.utf8)

        let settings = try JSONDecoder().decode(VoiceCleanupSettings.self, from: data)

        XCTAssertEqual(settings.latencyPolicy, .balanced2s)
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
            timeoutSeconds: 3,
            latencyPolicy: .qualityFirst
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

    func testDecodesNewCleanupProviders() throws {
        for raw in ["groq", "gemini", "omlx"] {
            let data = Data("""
            {
              "isEnabled": false,
              "provider": "\(raw)",
              "model": "",
              "baseURLString": "",
              "timeoutSeconds": 7
            }
            """.utf8)
            let settings = try JSONDecoder().decode(VoiceCleanupSettings.self, from: data)
            XCTAssertEqual(settings.provider.rawValue, raw)
        }
    }

    func testKeyStoreUsesDistinctAccountsPerProvider() throws {
        let keychain = InMemoryKeychain()
        let store = VoiceCleanupKeyStore(keychain: keychain)
        try store.saveAPIKey("groq-cleanup", for: .groq)
        try store.saveAPIKey("gemini-cleanup", for: .gemini)
        XCTAssertEqual(try store.apiKey(for: .groq), "groq-cleanup")
        XCTAssertEqual(try store.apiKey(for: .gemini), "gemini-cleanup")
    }

    func testProviderFactoryBuildsGroqWhenKeyExists() throws {
        let keychain = InMemoryKeychain()
        let keyStore = VoiceCleanupKeyStore(keychain: keychain)
        try keyStore.saveAPIKey("secret", for: .groq)
        let settings = VoiceCleanupSettings(
            isEnabled: true,
            provider: .groq,
            model: "llama-test",
            baseURLString: "https://api.groq.com/openai/v1",
            timeoutSeconds: 7
        )

        let provider = try VoiceCleanupProviderFactory.makeProvider(settings: settings, keyStore: keyStore)

        XCTAssertEqual(provider?.providerIdentifier, "openai-compatible")
    }

    func testProviderFactoryBuildsOmlxWithoutKey() throws {
        let settings = VoiceCleanupSettings(
            isEnabled: true,
            provider: .omlx,
            model: "m",
            baseURLString: "http://127.0.0.1:8000/v1",
            timeoutSeconds: 7
        )

        let provider = try VoiceCleanupProviderFactory.makeProvider(
            settings: settings,
            keyStore: VoiceCleanupKeyStore(keychain: InMemoryKeychain())
        )

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
