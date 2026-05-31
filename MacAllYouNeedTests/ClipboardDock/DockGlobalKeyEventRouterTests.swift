@testable import MacAllYouNeed
import Platform
import XCTest

final class DockGlobalKeyEventRouterTests: XCTestCase {
    private var bindings: DockGlobalKeyFallbackBindings {
        DockGlobalKeyFallbackBindings(
            quickLook: [HotkeyDescriptor(keyCode: 49, modifiers: [])],
            dismiss: [HotkeyDescriptor(keyCode: 53, modifiers: [])]
        )
    }

    func testQuickLookBindingMatchesSpace() {
        XCTAssertEqual(
            DockGlobalKeyEventRouter.route(
                keyCode: 49,
                modifierFlags: [],
                bindings: bindings
            ),
            .quickLook
        )
    }

    func testDismissBindingMatchesEscape() {
        XCTAssertEqual(
            DockGlobalKeyEventRouter.route(
                keyCode: 53,
                modifierFlags: [],
                bindings: bindings
            ),
            .dismiss
        )
    }

    func testArrowKeysWithoutModifiersRouteToFocusActions() {
        XCTAssertEqual(
            DockGlobalKeyEventRouter.route(
                keyCode: 123,
                modifierFlags: [],
                bindings: bindings
            ),
            .focusBackward
        )
        XCTAssertEqual(
            DockGlobalKeyEventRouter.route(
                keyCode: 124,
                modifierFlags: [],
                bindings: bindings
            ),
            .focusForward
        )
    }

    func testUnboundKeyReturnsNil() {
        XCTAssertNil(DockGlobalKeyEventRouter.route(
            keyCode: 1,
            modifierFlags: [],
            bindings: bindings
        ))
    }

    func testModifierMaskExcludesNonDeviceFlags() {
        let mask = DockGlobalKeyFallbackPolicy.modifierMask(
            from: [.maskCommand, .maskAlphaShift]
        )
        XCTAssertEqual(mask, NSEvent.ModifierFlags.command.rawValue)
    }
}
