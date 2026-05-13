@testable import MacAllYouNeed
import XCTest

final class VoiceASRSettingsStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        suiteName = "VoiceASRSettingsStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
    }

    func testDefaultSettingsUseAutomaticLanguageHint() {
        let settings = VoiceASRSettingsStore.load(from: defaults)

        XCTAssertEqual(settings.languageHint, .automatic)
        XCTAssertNil(settings.languageHint.qwen3Language)
    }

    func testSavesAndLoadsLanguageHint() {
        let saved = VoiceASRSettings(languageHint: .english)

        VoiceASRSettingsStore.save(saved, to: defaults)
        let loaded = VoiceASRSettingsStore.load(from: defaults)

        XCTAssertEqual(loaded, saved)
        XCTAssertEqual(loaded.languageHint.qwen3Language, .english)
    }
}

final class VoiceAudioSettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        suiteName = "VoiceAudioSettingsTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
    }

    func testDefaultMicrophonePreferenceUsesSystemInput() {
        XCTAssertEqual(
            VoiceAudioSettings.preferredMicrophoneID(from: defaults),
            VoiceAudioSettings.systemMicrophoneID
        )
    }

    func testLoadsStoredPreferredMicrophoneID() {
        defaults.set("ExternalMicUID", forKey: VoiceAudioSettings.microphoneIDKey)

        XCTAssertEqual(VoiceAudioSettings.preferredMicrophoneID(from: defaults), "ExternalMicUID")
    }
}
