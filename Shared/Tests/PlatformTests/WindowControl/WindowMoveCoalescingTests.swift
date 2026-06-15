import Core
import Foundation
@testable import Platform
import XCTest

final class WindowMoveCoalescingTests: XCTestCase {
    func testSameWindowNewerActionSupersedesWithinSettlingWindow() {
        let started = Date(timeIntervalSinceReferenceDate: 100)
        let now = started.addingTimeInterval(0.02)
        XCTAssertTrue(
            WindowMoveCoalescing.shouldSupersedeInFlightMove(
                sameWindow: true,
                inFlightStartedAt: started,
                now: now
            )
        )
    }

    func testSameWindowDoesNotSupersedeAfterSettlingWindow() {
        let started = Date(timeIntervalSinceReferenceDate: 100)
        let now = started.addingTimeInterval(0.06)
        XCTAssertFalse(
            WindowMoveCoalescing.shouldSupersedeInFlightMove(
                sameWindow: true,
                inFlightStartedAt: started,
                now: now
            )
        )
    }

    func testDifferentWindowDoesNotSupersede() {
        let started = Date(timeIntervalSinceReferenceDate: 100)
        let now = started.addingTimeInterval(0.02)
        XCTAssertFalse(
            WindowMoveCoalescing.shouldSupersedeInFlightMove(
                sameWindow: false,
                inFlightStartedAt: started,
                now: now
            )
        )
    }
}
