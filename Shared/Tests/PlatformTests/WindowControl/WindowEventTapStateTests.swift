@testable import Platform
import XCTest

final class WindowEventTapStateTests: XCTestCase {
    func testStartWithoutAccessibilityNeedsPermission() {
        let machine = WindowEventTapStateMachine()

        machine.start(enabled: true, axTrusted: false)

        XCTAssertEqual(machine.state, .needsAccessibility)
        XCTAssertFalse(machine.isTapActive)
    }

    func testDisabledStartStaysStopped() {
        let machine = WindowEventTapStateMachine()

        machine.start(enabled: false, axTrusted: true)

        XCTAssertEqual(machine.state, .stopped)
        XCTAssertFalse(machine.isTapActive)
    }

    func testActiveTapDisabledByTimeoutRequestsBoundedRetry() {
        let machine = WindowEventTapStateMachine(baseRetryDelay: 0.25)
        machine.start(enabled: true, axTrusted: true)

        machine.handleTapDisabled(.timeout)

        XCTAssertEqual(machine.state, .recovering(reason: .timeout, retryCount: 1, nextRetryDelay: 0.25))
        XCTAssertFalse(machine.isTapActive)
        XCTAssertEqual(machine.lastFailureReason, .timeout)
    }

    func testTapDisabledEventuallyEntersErrorAfterBoundedRetries() {
        let machine = WindowEventTapStateMachine(maxRetryCount: 1, baseRetryDelay: 0.25)
        machine.start(enabled: true, axTrusted: true)

        machine.handleTapDisabled(.timeout)
        machine.retryNow(enabled: true, axTrusted: true)
        machine.handleTapDisabled(.timeout)

        XCTAssertEqual(machine.state, .error(reason: .timeout))
        XCTAssertFalse(machine.isTapActive)
    }

    func testRetryAfterTerminalErrorDoesNotReactivateTap() {
        let machine = WindowEventTapStateMachine(maxRetryCount: 0, baseRetryDelay: 0.25)
        machine.start(enabled: true, axTrusted: true)
        machine.handleTapDisabled(.timeout)

        machine.retryNow(enabled: true, axTrusted: true)

        XCTAssertEqual(machine.state, .error(reason: .timeout))
        XCTAssertFalse(machine.isTapActive)
    }

    func testAccessibilityRevokeStopsTapAndPassesThrough() {
        let machine = WindowEventTapStateMachine()
        machine.start(enabled: true, axTrusted: true)

        machine.updateAccessibilityTrust(false, enabled: true)

        XCTAssertEqual(machine.state, .needsAccessibility)
        XCTAssertFalse(machine.isTapActive)
        XCTAssertEqual(machine.handleMouseDown(.suppressAllowed), .passThrough)
    }

    func testTapDisabledAfterStopIsIgnored() {
        let machine = WindowEventTapStateMachine()
        machine.start(enabled: true, axTrusted: true)
        machine.stop()

        machine.handleTapDisabled(.timeout)

        XCTAssertEqual(machine.state, .stopped)
        XCTAssertFalse(machine.isTapActive)
        XCTAssertNil(machine.lastFailureReason)
    }

    func testTapDisabledAfterAccessibilityRevokeIsIgnored() {
        let machine = WindowEventTapStateMachine()
        machine.start(enabled: true, axTrusted: true)
        machine.updateAccessibilityTrust(false, enabled: true)

        machine.handleTapDisabled(.timeout)

        XCTAssertEqual(machine.state, .needsAccessibility)
        XCTAssertFalse(machine.isTapActive)
        XCTAssertNil(machine.lastFailureReason)
    }

    func testStaleRetryAfterStopDoesNotReactivateTap() {
        let machine = WindowEventTapStateMachine()
        machine.start(enabled: true, axTrusted: true)
        machine.handleTapDisabled(.timeout)
        machine.stop()

        machine.retryNow(enabled: true, axTrusted: true)

        XCTAssertEqual(machine.state, .stopped)
        XCTAssertFalse(machine.isTapActive)
    }

    func testStopMovesActiveTapToStopped() {
        let machine = WindowEventTapStateMachine()
        machine.start(enabled: true, axTrusted: true)

        machine.stop()

        XCTAssertEqual(machine.state, .stopped)
        XCTAssertFalse(machine.isTapActive)
    }

    func testMouseDownWithoutConfiguredModifierPassesThrough() {
        let machine = WindowEventTapStateMachine()
        machine.start(enabled: true, axTrusted: true)

        XCTAssertEqual(machine.handleMouseDown(.suppressAllowed.with(modifierHeld: false)), .passThrough)
    }

    func testMouseDownWithoutResolvedTargetPassesThrough() {
        let machine = WindowEventTapStateMachine()
        machine.start(enabled: true, axTrusted: true)

        XCTAssertEqual(machine.handleMouseDown(.suppressAllowed.with(targetIsNormalNonMAYNWindow: false)), .passThrough)
    }

    func testMouseDownInIgnoredFrontAppPassesThrough() {
        let machine = WindowEventTapStateMachine()
        machine.start(enabled: true, axTrusted: true)

        XCTAssertEqual(machine.handleMouseDown(.suppressAllowed.with(frontAppIgnored: true)), .passThrough)
    }

    func testMouseDownSuppressesOnlyWhenFullPredicateIsSatisfied() {
        let machine = WindowEventTapStateMachine()
        machine.start(enabled: true, axTrusted: true)

        XCTAssertTrue(WindowEventTapStateMachine.shouldSuppressMouseDown(.suppressAllowed))
        XCTAssertEqual(machine.handleMouseDown(.suppressAllowed), .suppress)
    }
}

private extension WindowEventTapMouseDownContext {
    static let suppressAllowed = WindowEventTapMouseDownContext(
        enabled: true,
        axTrusted: true,
        coordinatorActive: true,
        recordingHotkey: false,
        modifierHeld: true,
        targetIsNormalNonMAYNWindow: true,
        frontAppIgnored: false
    )

    func with(
        enabled: Bool? = nil,
        axTrusted: Bool? = nil,
        coordinatorActive: Bool? = nil,
        recordingHotkey: Bool? = nil,
        modifierHeld: Bool? = nil,
        targetIsNormalNonMAYNWindow: Bool? = nil,
        frontAppIgnored: Bool? = nil
    ) -> WindowEventTapMouseDownContext {
        WindowEventTapMouseDownContext(
            enabled: enabled ?? self.enabled,
            axTrusted: axTrusted ?? self.axTrusted,
            coordinatorActive: coordinatorActive ?? self.coordinatorActive,
            recordingHotkey: recordingHotkey ?? self.recordingHotkey,
            modifierHeld: modifierHeld ?? self.modifierHeld,
            targetIsNormalNonMAYNWindow: targetIsNormalNonMAYNWindow ?? self.targetIsNormalNonMAYNWindow,
            frontAppIgnored: frontAppIgnored ?? self.frontAppIgnored
        )
    }
}
