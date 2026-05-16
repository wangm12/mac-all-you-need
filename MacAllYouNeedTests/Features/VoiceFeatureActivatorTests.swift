import XCTest
import FeatureCore
@testable import MacAllYouNeed

final class VoiceFeatureActivatorTests: XCTestCase {
    func testActivateStartsVoiceCoordinator() async throws {
        let activator = VoiceFeatureActivator(testMode: true)
        try await activator.activate()
        let running = await activator.isCoordinatorRunning
        XCTAssertTrue(running, "activate should mark the coordinator as running")
        try await activator.deactivate()
        let runningAfter = await activator.isCoordinatorRunning
        XCTAssertFalse(runningAfter)
    }

    func testIdempotency() async throws {
        let activator = VoiceFeatureActivator(testMode: true)
        try await activator.activate()
        try await activator.activate()   // second call must not crash or double-start
        let running = await activator.isCoordinatorRunning
        XCTAssertTrue(running)
        try await activator.deactivate()
        try await activator.deactivate() // second deactivate must not crash
        let runningAfter = await activator.isCoordinatorRunning
        XCTAssertFalse(runningAfter)
    }
}
