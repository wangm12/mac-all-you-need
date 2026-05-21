@testable import Platform
import XCTest

final class HotkeyDescriptorTests: XCTestCase {
    func testDefaultClipboardHotkey() {
        let d = HotkeyDescriptor.defaultClipboard
        XCTAssertEqual(d.keyCode, 9)
        XCTAssertTrue(d.modifiers.contains(.command))
        XCTAssertTrue(d.modifiers.contains(.shift))
        XCTAssertNil(d.modifierTap)
    }

    func testDisplayString() {
        let d = HotkeyDescriptor(keyCode: 9, modifiers: [.command, .shift])
        XCTAssertEqual(d.display, "⇧⌘V")
    }

    func testModifierTapSingleTapDisplay() {
        let d = HotkeyDescriptor(modifierTap: .singleTap(.command))
        XCTAssertEqual(d.display, "Tap ⌘")
        XCTAssertTrue(d.isModifierTap)
    }

    func testModifierTapDoubleTapDisplay() {
        let d = HotkeyDescriptor(modifierTap: .doubleTap(.leftOption))
        XCTAssertEqual(d.display, "Left ⌥ ×2")
        XCTAssertTrue(d.isModifierTap)
    }

    func testModifierTapHashableEquality() {
        let a = HotkeyDescriptor(modifierTap: .singleTap(.command))
        let b = HotkeyDescriptor(modifierTap: .singleTap(.command))
        let c = HotkeyDescriptor(modifierTap: .doubleTap(.command))
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testTapAndComboNeverEqual() {
        let tap = HotkeyDescriptor(modifierTap: .singleTap(.command))
        let combo = HotkeyDescriptor(keyCode: 0, modifiers: [])
        XCTAssertNotEqual(tap, combo)
    }

    func testBackwardsCompatibleCodableDecodeNoModifierTapField() throws {
        // Old-format JSON without the modifierTap field should decode with nil.
        let oldJSON = """
        {"keyCode": 9, "modifiers": 768}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(HotkeyDescriptor.self, from: oldJSON)
        XCTAssertEqual(decoded.keyCode, 9)
        XCTAssertNil(decoded.modifierTap)
    }

    func testModifierTapCodableRoundtrip() throws {
        let original = HotkeyDescriptor(modifierTap: .doubleTap(.leftCommand))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HotkeyDescriptor.self, from: data)
        XCTAssertEqual(original, decoded)
        XCTAssertEqual(decoded.modifierTap?.key, .leftCommand)
        XCTAssertEqual(decoded.modifierTap?.count, 2)
    }
}
