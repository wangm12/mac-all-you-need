import Core
import CoreGraphics
import Platform
@testable import MacAllYouNeed
import XCTest

final class LayoutHotkeyBindingsTests: XCTestCase {
    func testMatchesControlOptionLeftArrowIgnoringSpuriousFnFlag() {
        let bindings = [
            LayoutHotkeyBinding(
                keyCode: UInt32(kVK_LeftArrow),
                modifiers: [.control, .option],
                action: .leftHalf
            )
        ]

        var flags: CGEventFlags = [.maskControl, .maskAlternate, .maskSecondaryFn]
        let source = CGEventSource(stateID: .hidSystemState)
        guard let event = CGEvent(
            keyboardEventSource: source,
            virtualKey: CGKeyCode(kVK_LeftArrow),
            keyDown: true
        ) else {
            XCTFail("expected CGEvent")
            return
        }
        event.flags = flags

        XCTAssertEqual(LayoutHotkeyBindings.action(for: event, bindings: bindings), .leftHalf)
    }

    func testBuildsBindingsFromHotkeyMap() {
        let map: [HotkeyAction: [HotkeyDescriptor]] = [
            .windowLeftHalf: [HotkeyDescriptor(keyCode: UInt32(kVK_LeftArrow), modifiers: [.control, .option])],
            .clipboard: [.defaultClipboard]
        ]

        let bindings = LayoutHotkeyBindings.from(map)

        XCTAssertEqual(bindings.count, 1)
        XCTAssertEqual(bindings.first?.action, .leftHalf)
    }
}
