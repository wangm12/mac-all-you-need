import XCTest
import AppKit
@testable import Platform

final class NSEventMonitorHandleTests: XCTestCase {

    // MARK: - Helpers

    /// Post a synthetic .applicationDefined event so local monitors can observe it.
    /// Returns true if an NSApplication instance was available and posting was attempted.
    @discardableResult
    private func postSyntheticEvent() -> Bool {
        guard let app = NSApp,
              let event = NSEvent.otherEvent(
                with: .applicationDefined,
                location: .zero,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: 0,
                context: nil,
                subtype: 0,
                data1: 0,
                data2: 0
              )
        else { return false }
        app.postEvent(event, atStart: false)
        // Drain the run loop briefly so the event is delivered.
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        return true
    }

    // MARK: - 1. Handle is released when strong reference is dropped

    func testHandleIsReleasedOnDeinit() {
        var handle: NSEventMonitorHandle? = NSEventMonitorHandle(
            local: .applicationDefined,
            handler: { $0 }
        )
        weak var weakHandle = handle
        XCTAssertNotNil(weakHandle)

        handle = nil

        XCTAssertNil(weakHandle, "Handle should have been deallocated after strong reference is dropped")
    }

    // MARK: - 2. Handler does not fire after handle is deallocated

    func testHandlerDoesNotFireAfterDeinit() {
        var callCount = 0

        // Install and immediately release the handle inside autoreleasepool.
        autoreleasepool {
            let handle = NSEventMonitorHandle(local: .applicationDefined) { event in
                callCount += 1
                return event
            }
            // Post while the handle is live (skip assertion — NSApp may be nil in
            // headless runner; we only need the posting attempt to advance callCount
            // if delivery is possible).
            postSyntheticEvent()
            _ = handle // keep alive until end of pool
        }

        let countAfterRelease = callCount

        // Post again after the handle has been deallocated.
        postSyntheticEvent()

        XCTAssertEqual(
            callCount, countAfterRelease,
            "Handler must not fire after the handle is deallocated (monitor should have been removed)"
        )
    }

    // MARK: - 3. Multiple handles coexist — both live at the same time, deinit cleanly

    func testMultipleHandlesCoexistAndDealloc() {
        // Verify both handles can be created together without assertion failure.
        var countA = 0
        var countB = 0

        let handleA = NSEventMonitorHandle(local: .applicationDefined) { event in
            countA += 1
            return event
        }
        let handleB = NSEventMonitorHandle(local: .applicationDefined) { event in
            countB += 1
            return event
        }

        let delivered = postSyntheticEvent()

        if delivered {
            // If the run loop delivered the event both handlers should have fired.
            XCTAssertGreaterThanOrEqual(countA, 1, "handleA's handler should have fired")
            XCTAssertGreaterThanOrEqual(countB, 1, "handleB's handler should have fired")
        }

        // Dropping both handles here — deinit of each should not crash.
        withExtendedLifetime((handleA, handleB)) {}
    }

    // MARK: - 4. Releasing multiple handles in sequence does not crash

    func testSequentialDeinitsDoNotCrash() {
        var h1: NSEventMonitorHandle? = NSEventMonitorHandle(local: .applicationDefined, handler: { $0 })
        var h2: NSEventMonitorHandle? = NSEventMonitorHandle(local: .applicationDefined, handler: { $0 })
        var h3: NSEventMonitorHandle? = NSEventMonitorHandle(local: .applicationDefined, handler: { $0 })

        h1 = nil
        h2 = nil
        h3 = nil

        // If we get here, deinit did not crash.
        XCTAssertNil(h1)
        XCTAssertNil(h2)
        XCTAssertNil(h3)
    }

    // MARK: - 5. Global init compiles, does not crash, deinits cleanly

    func testGlobalInitAndDeinit() {
        // Global monitors observe events sent to OTHER processes, so we cannot
        // exercise the handler in a unit test. We only verify that creation and
        // deallocation complete without crashing.
        var handle: NSEventMonitorHandle? = NSEventMonitorHandle(global: .mouseMoved) { _ in }
        weak var weakHandle = handle
        XCTAssertNotNil(weakHandle)

        handle = nil

        XCTAssertNil(weakHandle, "Global handle should be deallocated after strong reference is dropped")
    }
}
