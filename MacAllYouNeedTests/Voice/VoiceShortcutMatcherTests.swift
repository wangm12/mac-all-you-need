import Carbon.HIToolbox
@testable import MacAllYouNeed
import Platform
import XCTest

final class VoiceShortcutMatcherTests: XCTestCase {
    func testMatchesConfiguredKeyAndModifiers() {
        let descriptor = HotkeyDescriptor(keyCode: UInt32(kVK_Space), modifiers: [.control, .option])

        XCTAssertTrue(VoiceShortcutMatcher.matches(
            keyCode: UInt16(kVK_Space),
            modifiers: [.control, .option],
            descriptor: descriptor
        ))
        XCTAssertFalse(VoiceShortcutMatcher.matches(
            keyCode: UInt16(kVK_Space),
            modifiers: [.control],
            descriptor: descriptor
        ))
        XCTAssertFalse(VoiceShortcutMatcher.matches(
            keyCode: UInt16(kVK_ANSI_R),
            modifiers: [.control, .option],
            descriptor: descriptor
        ))
    }
}
