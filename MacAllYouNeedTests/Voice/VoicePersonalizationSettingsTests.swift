@testable import MacAllYouNeed
import XCTest

final class VoicePersonalizationSettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        suiteName = "VoicePersonalizationSettingsTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
    }

    func testDefaultSettingsHaveLearningAndTrainingExamplesOnWithStandardCacheLimits() {
        let settings = VoicePersonalizationSettingsStore.load(from: defaults)

        XCTAssertTrue(settings.learnFromEditsEnabled)
        XCTAssertTrue(settings.saveTrainingExamplesEnabled)
        XCTAssertEqual(settings.rollingCacheDays, 30)
        XCTAssertEqual(settings.rollingCacheMaxSamples, 50)
    }

    func testSavesAndLoadsAllFields() {
        let saved = VoicePersonalizationSettings(
            learnFromEditsEnabled: false,
            saveTrainingExamplesEnabled: false,
            rollingCacheDays: 14,
            rollingCacheMaxSamples: 100
        )

        VoicePersonalizationSettingsStore.save(saved, to: defaults)
        let loaded = VoicePersonalizationSettingsStore.load(from: defaults)

        XCTAssertEqual(loaded, saved)
    }

    func testPartialJSONPayloadUsesDefaultsForMissingKeys() {
        let payload = #"{"learnFromEditsEnabled":false}"#.data(using: .utf8)!
        defaults.set(payload, forKey: VoicePersonalizationSettingsStore.key)

        let loaded = VoicePersonalizationSettingsStore.load(from: defaults)

        XCTAssertFalse(loaded.learnFromEditsEnabled)
        XCTAssertTrue(loaded.saveTrainingExamplesEnabled)
        XCTAssertEqual(loaded.rollingCacheDays, 30)
        XCTAssertEqual(loaded.rollingCacheMaxSamples, 50)
    }

    func testCorruptPayloadFallsBackToDefault() {
        defaults.set(Data("not json".utf8), forKey: VoicePersonalizationSettingsStore.key)

        let loaded = VoicePersonalizationSettingsStore.load(from: defaults)

        XCTAssertEqual(loaded, .default)
    }
}
