@testable import MacAllYouNeed
import AppKit
import XCTest

final class DockGlobalKeyEventRouterTests: XCTestCase {
    private var bindings: DockGlobalKeyFallbackBindings {
        DockGlobalKeyFallbackBindings(
            quickLook: [ShortcutBinding(keyCode: 49, modifierMask: 0)],
            dismiss: [ShortcutBinding(keyCode: 53, modifierMask: 0)]
        )
    }

    func testRouteQuickLookBinding() {
        XCTAssertEqual(
            DockGlobalKeyEventRouter.route(keyCode: 49, modifierFlags: [], bindings: bindings),
            .quickLook
        )
    }

    func testRouteDismissBinding() {
        XCTAssertEqual(
            DockGlobalKeyEventRouter.route(keyCode: 53, modifierFlags: [], bindings: bindings),
            .dismiss
        )
    }

    func testRoutePlainLeftArrowMapsToFocusBackward() {
        XCTAssertEqual(
            DockGlobalKeyEventRouter.route(keyCode: 123, modifierFlags: [], bindings: bindings),
            .focusBackward
        )
    }

    func testRoutePlainRightArrowMapsToFocusForward() {
        XCTAssertEqual(
            DockGlobalKeyEventRouter.route(keyCode: 124, modifierFlags: [], bindings: bindings),
            .focusForward
        )
    }

    func testRouteModifiedArrowKeysReturnNil() {
        XCTAssertNil(
            DockGlobalKeyEventRouter.route(keyCode: 124, modifierFlags: .shift, bindings: bindings)
        )
        XCTAssertNil(
            DockGlobalKeyEventRouter.route(keyCode: 123, modifierFlags: .command, bindings: bindings)
        )
    }

    func testRouteUnboundKeyReturnsNil() {
        XCTAssertNil(
            DockGlobalKeyEventRouter.route(keyCode: 0x21, modifierFlags: [], bindings: bindings)
        )
    }

    func testRouteOnlyDeviceIndependentModifiersAreConsidered() {
        // Sanity check: device-dependent bits (numeric pad / function) ARE
        // part of `deviceIndependentFlagsMask`, so a plain right-arrow with
        // numericPad set will land in the bound-shortcut branch (mask != 0)
        // and fall through to nil, NOT focusForward. This pins the existing
        // policy behavior so a refactor that quietly widened the mask would
        // get flagged.
        XCTAssertNil(
            DockGlobalKeyEventRouter.route(
                keyCode: 124,
                modifierFlags: .numericPad,
                bindings: bindings
            )
        )
    }

    func testFallbackPolicyMasksCGEventFlagsToDeviceIndependentBits() {
        // Ensure the CGEventFlags → NSEvent.ModifierFlags translation surface
        // we expose stays consistent with what `route(...)` consumes.
        let mask = DockGlobalKeyFallbackPolicy.modifierMask(
            from: [.maskShift, .maskCommand]
        )
        let expected = (NSEvent.ModifierFlags.shift.rawValue | NSEvent.ModifierFlags.command.rawValue)
            & NSEvent.ModifierFlags.deviceIndependentFlagsMask.rawValue
        XCTAssertEqual(mask, expected)
    }

    @MainActor
    func testRouterStartAndStopAreIdempotent() {
        // The router owns an NSEvent global monitor + a CGEventTap. Without
        // Accessibility permission the tap path quietly no-ops; what we
        // verify here is that repeated start()/stop() doesn't crash and
        // leaves the router in a consistent state.
        let router = DockGlobalKeyEventRouter(
            bindingsProvider: { [bindings] in bindings },
            handleAction: { _ in }
        )
        router.start()
        router.start()
        router.stop()
        router.stop()
    }
}
