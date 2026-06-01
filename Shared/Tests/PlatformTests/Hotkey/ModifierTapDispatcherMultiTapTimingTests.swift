import CoreGraphics
import XCTest
@testable import Platform
import Core

// MARK: - Helpers

/// CGEventFlags that represent left-option pressed (physical device bit + generic flag).
private let kOptionDown = CGEventFlags(
    rawValue: CGModifierDeviceBit.leftOption | CGEventFlags.maskAlternate.rawValue
)
/// CGEventFlags with all modifier bits cleared (option released).
private let kNoFlags = CGEventFlags(rawValue: 0)

/// CGEventFlags that represent left-shift pressed (used as a second, distinct modifier).
private let kShiftDown = CGEventFlags(
    rawValue: CGModifierDeviceBit.leftShift | CGEventFlags.maskShift.rawValue
)

private let kCommandDown = CGEventFlags(
    rawValue: CGModifierDeviceBit.leftCommand | CGEventFlags.maskCommand.rawValue
)

extension ModifierTapDispatcher {
    /// Simulate a complete tap: press then immediate release of left-option.
    func simulateOptionTap() {
        handleFlagsChanged(newFlags: kOptionDown)
        handleFlagsChanged(newFlags: kNoFlags)
    }
}

// MARK: - Tests

final class ModifierTapDispatcherMultiTapTimingTests: XCTestCase {

    // Use a short multi-tap window to keep tests fast.
    private let window: TimeInterval = 0.15

    /// Returns a fresh dispatcher instance configured with a short multi-tap window.
    private func makeDispatcher() -> ModifierTapDispatcher {
        let d = ModifierTapDispatcher()
        d.multiTapWindow = window
        return d
    }

    // MARK: - 1. Single tap fires exactly once after window expires

    func testSingleTapFiresExactlyOnceAfterWindow() {
        let dispatcher = makeDispatcher()

        // Register single-tap for option.
        var callCount = 0
        let token = dispatcher.register(.singleTap(.leftOption)) {
            callCount += 1
        }

        // Simulate one tap. Because no double-tap sibling is registered,
        // hasHigherCountRegistration returns false → fires immediately (no timer).
        dispatcher.simulateOptionTap()

        // Callback fires synchronously via DispatchQueue.main.async. Drain main queue.
        let exp = expectation(description: "callback fires")
        DispatchQueue.main.async { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)

        XCTAssertEqual(callCount, 1, "Single tap should fire callback exactly once")

        dispatcher.unregister(token)
    }

    // MARK: - 2. Double tap within window fires once with count=2

    func testDoubleTapWithinWindowFiresOnceWithCountTwo() {
        let dispatcher = makeDispatcher()

        // Register only double-tap; also register single-tap so that
        // hasHigherCountRegistration returns true and the timer arms after tap 1.
        var singleCount = 0
        var doubleCount = 0
        let t1 = dispatcher.register(.singleTap(.leftOption)) { singleCount += 1 }
        let t2 = dispatcher.register(.doubleTap(.leftOption)) { doubleCount += 1 }

        // First tap — timer arms because a double-tap sibling exists.
        dispatcher.simulateOptionTap()

        // Second tap arrives before the window expires — timer cancels, count=2 fires.
        // Since there is no triple-tap registration, the double-tap fires immediately.
        dispatcher.simulateOptionTap()

        // Drain the main queue so async callbacks execute.
        let exp = expectation(description: "callbacks settle")
        DispatchQueue.main.async { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)

        XCTAssertEqual(singleCount, 0, "No single-tap callback after a double tap")
        XCTAssertEqual(doubleCount, 1, "Double-tap callback should fire exactly once")

        dispatcher.unregister(t1)
        dispatcher.unregister(t2)
    }

    // MARK: - 3. Non-modifier key during modifier hold cancels the tap

    func testNonModifierKeyDuringHoldCancelsTap() {
        let dispatcher = makeDispatcher()

        var callCount = 0
        let token = dispatcher.register(.singleTap(.leftOption)) { callCount += 1 }

        // Press option.
        dispatcher.handleFlagsChanged(newFlags: kOptionDown)

        // Simulate a non-modifier keyDown while option is held.
        // We need a CGEvent to call handleEvent; synthesize a keyDown event.
        if let event = CGEvent(keyboardEventSource: nil, virtualKey: 0x00, keyDown: true) {
            dispatcher.handleEvent(type: .keyDown, event: event)
        }

        // Release option — tap should be rejected because nonModifierDownSincePress
        // contains .leftOption.
        dispatcher.handleFlagsChanged(newFlags: kNoFlags)

        // Drain main queue.
        let exp = expectation(description: "settle")
        DispatchQueue.main.async { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)

        XCTAssertEqual(callCount, 0, "Tap interrupted by non-modifier key must not fire")

        dispatcher.unregister(token)
    }

    // MARK: - 4. ⌘A then ⌘C must not register as a double-tap

    func testCommandComboSequenceDoesNotFireDoubleTap() {
        let dispatcher = makeDispatcher()

        var doubleCount = 0
        let token = dispatcher.register(.doubleTap(.leftCommand)) { doubleCount += 1 }

        // ⌘A
        dispatcher.handleFlagsChanged(newFlags: kCommandDown)
        if let event = CGEvent(keyboardEventSource: nil, virtualKey: 0x00, keyDown: true) {
            var flags = event.flags
            flags.insert(kCommandDown)
            event.flags = flags
            dispatcher.handleEvent(type: .keyDown, event: event)
        }
        dispatcher.handleFlagsChanged(newFlags: kNoFlags)

        // ⌘C shortly after (separate combo, not a double-tap)
        dispatcher.handleFlagsChanged(newFlags: kCommandDown)
        if let event = CGEvent(keyboardEventSource: nil, virtualKey: 0x08, keyDown: true) {
            var flags = event.flags
            flags.insert(kCommandDown)
            event.flags = flags
            dispatcher.handleEvent(type: .keyDown, event: event)
        }
        dispatcher.handleFlagsChanged(newFlags: kNoFlags)

        let exp = expectation(description: "settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + window + 0.1) { exp.fulfill() }
        wait(for: [exp], timeout: 2.0)

        XCTAssertEqual(doubleCount, 0, "⌘A then ⌘C must not count as a modifier double-tap")

        dispatcher.unregister(token)
    }

    // MARK: - 5. Unregister before timer fires cancels the pending callback

    func testUnregisterBeforeTimerFiresPreventsCallback() {
        let dispatcher = makeDispatcher()

        // Register single-tap AND double-tap so that the timer arms after tap 1.
        var singleCount = 0
        var doubleCount = 0
        let t1 = dispatcher.register(.singleTap(.leftOption)) { singleCount += 1 }
        let t2 = dispatcher.register(.doubleTap(.leftOption)) { doubleCount += 1 }

        // First tap — timer arms (waiting for possible second tap).
        dispatcher.simulateOptionTap()

        // Unregister all callbacks before the timer window expires.
        // removeTap() is called by unregister (last registration), which calls
        // cancelPendingTimer() — the Task is cancelled and firePendingTap() never runs.
        dispatcher.unregister(t1)
        dispatcher.unregister(t2)

        // Wait well past the multi-tap window to confirm no callback fires.
        let exp = expectation(description: "no callback after cancel")
        DispatchQueue.main.asyncAfter(deadline: .now() + window + 0.15) { exp.fulfill() }
        wait(for: [exp], timeout: 2.0)

        XCTAssertEqual(singleCount, 0, "Single-tap callback must not fire after unregister")
        XCTAssertEqual(doubleCount, 0, "Double-tap callback must not fire after unregister")
    }
}
