import Carbon.HIToolbox
@testable import MacAllYouNeed
import Platform
import XCTest

final class VoiceActivationSettingsStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        suiteName = "VoiceActivationSettingsStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
    }

    func testDefaultSettingsUseToggleControlOptionSpace() {
        let settings = VoiceActivationSettingsStore.load(from: defaults)

        XCTAssertEqual(settings.mode, .toggle)
        XCTAssertEqual(settings.shortcut.keyCode, UInt32(kVK_Space))
        XCTAssertEqual(settings.shortcut.modifiers, [.control, .option])
        XCTAssertEqual(settings.shortcut.display, "⌃⌥Space")
    }

    func testSavesAndLoadsSettings() {
        let saved = VoiceActivationSettings(
            shortcut: HotkeyDescriptor(keyCode: UInt32(kVK_ANSI_R), modifiers: [.command, .shift]),
            mode: .hold
        )

        VoiceActivationSettingsStore.save(saved, to: defaults)
        let loaded = VoiceActivationSettingsStore.load(from: defaults)

        XCTAssertEqual(loaded, saved)
    }
}
