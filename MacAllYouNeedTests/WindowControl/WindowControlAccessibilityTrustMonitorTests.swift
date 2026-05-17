@testable import MacAllYouNeed
import XCTest

@MainActor
final class WindowControlAccessibilityTrustMonitorTests: XCTestCase {
    func testStartReportsInitialTrust() {
        var reported: [Bool] = []
        let monitor = WindowControlAccessibilityTrustMonitor(
            accessibilityTrust: { true },
            onTrustChanged: { reported.append($0) },
            shouldPoll: { false }
        )

        monitor.start()

        XCTAssertEqual(reported, [true])
    }

    func testRefreshReportsOnlyWhenTrustChanges() {
        var trusted = false
        var reported: [Bool] = []
        let monitor = WindowControlAccessibilityTrustMonitor(
            accessibilityTrust: { trusted },
            onTrustChanged: { reported.append($0) },
            shouldPoll: { false }
        )
        monitor.start()

        monitor.refreshNow()
        trusted = true
        monitor.refreshNow()
        monitor.refreshNow()

        XCTAssertEqual(reported, [false, true])
    }

    func testPollingEligibilityRequiresEnabledRecoverableState() {
        XCTAssertTrue(WindowControlAccessibilityTrustMonitor.shouldPoll(runtimeEnabled: true, coordinatorState: .needsAccessibility))
        XCTAssertTrue(WindowControlAccessibilityTrustMonitor.shouldPoll(runtimeEnabled: true, coordinatorState: .active))
        XCTAssertFalse(WindowControlAccessibilityTrustMonitor.shouldPoll(runtimeEnabled: false, coordinatorState: .needsAccessibility))
        XCTAssertFalse(WindowControlAccessibilityTrustMonitor.shouldPoll(runtimeEnabled: true, coordinatorState: .off))
        XCTAssertFalse(WindowControlAccessibilityTrustMonitor.shouldPoll(runtimeEnabled: true, coordinatorState: .suspended(.hotkeyRecording)))
    }
}
