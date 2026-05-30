import Platform
import XCTest
@testable import MacAllYouNeed

final class DockPreviewCoordinatorTests: XCTestCase {
    @MainActor func testStartAndStop() {
        let coord = AXObserverCoordinator(engine: FakeDockAXObserverEngine(), healthCheckInterval: 999)
        let dockCoord = DockPreviewCoordinator(coordinator: coord)
        dockCoord.start()
        dockCoord.stop()
        // No crash on the start/stop lifecycle.
    }
}
