@testable import MacAllYouNeed
import AppKit
import XCTest

final class MacAllYouNeedApplicationDelegateTests: XCTestCase {
    @MainActor
    func testReopenInvokesStartupSurfaceHandlerAndLetsSystemContinue() {
        let delegate = MacAllYouNeedApplicationDelegate()
        var didHandleReopen = false
        delegate.handleReopen = { didHandleReopen = true }

        let shouldContinue = delegate.applicationShouldHandleReopen(
            NSApplication.shared,
            hasVisibleWindows: false
        )

        XCTAssertTrue(didHandleReopen)
        XCTAssertTrue(shouldContinue)
    }
}
