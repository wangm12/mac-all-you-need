import XCTest
import FeatureCore
@testable import MacAllYouNeed

final class ClipboardFeatureActivatorTests: XCTestCase {
    func testActivateStartsClipboardPolling() async throws {
        let activator = ClipboardFeatureActivator(testMode: true)
        try await activator.activate()
        let polling = await activator.isPolling
        XCTAssertTrue(polling, "activate should start the pasteboard poller")
        try await activator.deactivate()
        let pollingAfter = await activator.isPolling
        XCTAssertFalse(pollingAfter)
    }

    func testActivateIsIdempotent() async throws {
        let activator = ClipboardFeatureActivator(testMode: true)
        try await activator.activate()
        try await activator.activate()  // second call must not crash or double-register
        let polling = await activator.isPolling
        XCTAssertTrue(polling)
        try await activator.deactivate()
    }

    func testDeactivateIsIdempotent() async throws {
        let activator = ClipboardFeatureActivator(testMode: true)
        try await activator.deactivate()  // already inactive
        let polling = await activator.isPolling
        XCTAssertFalse(polling)
    }
}
