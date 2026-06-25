@testable import Core
import XCTest

final class VoiceHistorySettingsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "VoiceHistorySettingsTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func test_defaults_when_keys_absent_are_forever_and_saveAudioOn() {
        let loaded = VoiceHistorySettings.load(from: defaults)
        XCTAssertEqual(loaded.retention, .forever)
        XCTAssertTrue(loaded.saveAudio)
    }

    func test_save_then_load_roundtrips() {
        let settings = VoiceHistorySettings(retention: .days7, saveAudio: true)
        settings.save(to: defaults)

        let loaded = VoiceHistorySettings.load(from: defaults)
        XCTAssertEqual(loaded.retention, .days7)
        XCTAssertTrue(loaded.saveAudio)
    }

    func test_load_reads_individual_keys() {
        defaults.set("30d", forKey: VoiceHistorySettings.retentionKey)
        defaults.set(true, forKey: VoiceHistorySettings.saveAudioKey)

        let loaded = VoiceHistorySettings.load(from: defaults)
        XCTAssertEqual(loaded.retention, .days30)
        XCTAssertTrue(loaded.saveAudio)
    }
}
