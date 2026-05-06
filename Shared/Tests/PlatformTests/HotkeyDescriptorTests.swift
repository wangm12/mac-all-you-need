@testable import Platform
import XCTest

final class HotkeyDescriptorTests: XCTestCase {
    func testDefaultClipboardHotkey() {
        let d = HotkeyDescriptor.defaultClipboard
        XCTAssertEqual(d.keyCode, 9)
        XCTAssertTrue(d.modifiers.contains(.command))
        XCTAssertTrue(d.modifiers.contains(.shift))
    }

    func testDisplayString() {
        let d = HotkeyDescriptor(keyCode: 9, modifiers: [.command, .shift])
        XCTAssertEqual(d.display, "⇧⌘V")
    }
}
