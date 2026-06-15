import Core
@testable import MacAllYouNeed
import XCTest

@MainActor
final class WindowControlMovementFeedbackTests: XCTestCase {
    override func setUp() {
        super.setUp()
        WindowControlMovementFeedback.resetForTesting()
    }

    func testMessagesForFailureStatuses() {
        XCTAssertEqual(
            WindowControlMovementFeedback.message(for: .fixedSizeWindow, axTrusted: true),
            "This window can't be resized"
        )
        XCTAssertEqual(
            WindowControlMovementFeedback.message(for: .writeFailed, axTrusted: true),
            "Couldn't move this window"
        )
        XCTAssertEqual(
            WindowControlMovementFeedback.message(for: .writeFailed, axTrusted: false),
            "Couldn't move this window — check Accessibility permission"
        )
        XCTAssertEqual(
            WindowControlMovementFeedback.message(for: .unsupportedWindow, axTrusted: true),
            "This window can't be moved with Window Layouts"
        )
        XCTAssertNil(WindowControlMovementFeedback.message(for: .moved, axTrusted: true))
    }

    func testPresentDebouncesIdenticalMessages() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        WindowControlMovementFeedback.present(status: .fixedSizeWindow, axTrusted: true, now: now)
        WindowControlMovementFeedback.present(
            status: .fixedSizeWindow,
            axTrusted: true,
            now: now.addingTimeInterval(0.5)
        )
        // Second call within debounce window should be a no-op (no crash).
    }
}
