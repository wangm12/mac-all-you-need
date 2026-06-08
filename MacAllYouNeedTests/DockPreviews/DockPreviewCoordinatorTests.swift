import Platform
import XCTest
@testable import MacAllYouNeed

final class DockPreviewCoordinatorTests: XCTestCase {
    @MainActor func testStartAndStop() {
        let coord = AXObserverCoordinator(engine: FakeDockAXObserverEngine(), healthCheckInterval: 999)
        let panel = DockPreviewPanelController()
        let dockCoord = DockPreviewCoordinator(
            panelController: panel,
            coordinator: coord,
            dockWorker: DockPreviewWorker()
        )
        dockCoord.start()
        dockCoord.stop()
        // No crash on the start/stop lifecycle.
    }
}
