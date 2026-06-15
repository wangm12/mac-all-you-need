import Core
import XCTest

final class RadialMenuKeyBindingsTests: XCTestCase {
    func testDefaultKeyboardMappingIncludesLegacyMaximizeKey() {
        let mapping = RadialMenuKeyBindings.default.keyboardMapping()
        XCTAssertEqual(mapping["f"], .maximize)
        XCTAssertEqual(mapping["m"], .maximize)
        XCTAssertEqual(mapping["w"], .topHalf)
    }

    func testDisplayShowsLegacyMaximizeAlias() {
        XCTAssertEqual(RadialMenuKeyBindings.default.display(for: .maximize), "F, M")
    }

    func testReplacingDuplicateKeysEliminatesConflicts() {
        var bindings = RadialMenuKeyBindings.default
        bindings.bindings[WindowAction.topHalf.rawValue] = "d"
        let resolved = bindings.replacingDuplicateKeys()
        let characters = resolved.bindings.values.compactMap(\.first)
        XCTAssertEqual(Set(characters).count, characters.count)
        XCTAssertEqual(resolved.bindings[WindowAction.rightHalf.rawValue], "d")
        XCTAssertEqual(resolved.bindings[WindowAction.topHalf.rawValue], "w")
    }

    func testNormalizedRejectsReservedKeys() {
        var bindings = RadialMenuKeyBindings.default
        bindings.bindings[WindowAction.topHalf.rawValue] = "x"
        let normalized = bindings.normalized()
        XCTAssertEqual(normalized.bindings[WindowAction.topHalf.rawValue], "w")
    }

    func testCustomBindingResolvesThroughLayout() {
        var bindings = RadialMenuKeyBindings.default
        bindings.bindings[WindowAction.leftHalf.rawValue] = "j"
        XCTAssertEqual(RadialMenuLayout.action(forKey: "j", bindings: bindings), .leftHalf)
        XCTAssertEqual(RadialMenuLayout.inMenuShortcutDisplay(for: .leftHalf, bindings: bindings), "J")
    }
}
