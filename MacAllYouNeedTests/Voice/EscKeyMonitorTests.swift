import AppKit
@testable import MacAllYouNeed
import XCTest

/// Verifies dispatch of Esc / Return / numpad-Enter keystrokes. Uses
/// `monitor.handle(event:)` directly to avoid posting NSEvents through the
/// AppKit run loop, which is flaky inside xctest. The same `handle(event:)`
/// body services both the global and local NSEvent monitors in production, so
/// exercising it directly covers both dispatch paths.
@MainActor
final class EscKeyMonitorTests: XCTestCase {
    private func makeKeyDown(keyCode: UInt16) -> NSEvent {
        // NSEvent.keyEvent returns an Optional but in practice never nil for
        // a well-formed keyDown — force-unwrap is fine in a test.
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        )!
    }

    func testEscEventFiresOnEscOnlyOnce() {
        var escCount = 0
        var returnCount = 0
        let monitor = EscKeyMonitor(
            onEsc: { escCount += 1 },
            onReturn: { returnCount += 1 }
        )

        monitor.handle(event: makeKeyDown(keyCode: EscKeyMonitor.KeyCode.escape))

        XCTAssertEqual(escCount, 1, "Esc must fire onEsc exactly once")
        XCTAssertEqual(returnCount, 0, "Esc must not fire onReturn")
    }

    func testReturnEventFiresOnReturnOnlyOnce() {
        var escCount = 0
        var returnCount = 0
        let monitor = EscKeyMonitor(
            onEsc: { escCount += 1 },
            onReturn: { returnCount += 1 }
        )

        monitor.handle(event: makeKeyDown(keyCode: EscKeyMonitor.KeyCode.return))

        XCTAssertEqual(returnCount, 1, "Return must fire onReturn exactly once")
        XCTAssertEqual(escCount, 0, "Return must not fire onEsc")
    }

    func testNumpadEnterFiresOnReturnOnlyOnce() {
        var escCount = 0
        var returnCount = 0
        let monitor = EscKeyMonitor(
            onEsc: { escCount += 1 },
            onReturn: { returnCount += 1 }
        )

        monitor.handle(event: makeKeyDown(keyCode: EscKeyMonitor.KeyCode.numpadEnter))

        XCTAssertEqual(returnCount, 1, "Numpad Enter must fire onReturn exactly once")
        XCTAssertEqual(escCount, 0, "Numpad Enter must not fire onEsc")
    }

    func testIgnoredKeyCodesDoNotFireAnyCallback() {
        var escCount = 0
        var returnCount = 0
        let monitor = EscKeyMonitor(
            onEsc: { escCount += 1 },
            onReturn: { returnCount += 1 }
        )

        // 0x00 = 'a', 0x31 = space — both must be ignored.
        monitor.handle(event: makeKeyDown(keyCode: 0x00))
        monitor.handle(event: makeKeyDown(keyCode: 0x31))

        XCTAssertEqual(escCount, 0, "non-target key must not fire onEsc")
        XCTAssertEqual(returnCount, 0, "non-target key must not fire onReturn")
    }

    func testMultipleEscEventsFireOncePerEvent() {
        var escCount = 0
        let monitor = EscKeyMonitor(onEsc: { escCount += 1 })

        for _ in 0 ..< 3 {
            monitor.handle(event: makeKeyDown(keyCode: EscKeyMonitor.KeyCode.escape))
        }

        XCTAssertEqual(escCount, 3, "each Esc must fire exactly once (no global + local double-firing)")
    }

    func testInstallThenUninstallDoesNotCrash() {
        let monitor = EscKeyMonitor()
        monitor.install()
        monitor.uninstall()
        // Re-install should also be safe and idempotent.
        monitor.install()
        monitor.install()
        monitor.uninstall()
    }

    func testNilCallbacksAreSafe() {
        let monitor = EscKeyMonitor()
        // No callbacks set — must not crash.
        monitor.handle(event: makeKeyDown(keyCode: EscKeyMonitor.KeyCode.escape))
        monitor.handle(event: makeKeyDown(keyCode: EscKeyMonitor.KeyCode.return))
    }
}
