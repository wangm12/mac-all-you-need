import Foundation
import Platform
import XCTest
@testable import MacAllYouNeed

/// Minimal in-app fake conforming to the public `AXObserverEngine` protocol so
/// the Dock preview AX coordinator can be exercised without a live Dock.
final class FakeDockAXObserverEngine: AXObserverEngine, @unchecked Sendable {
    func makeObserver(pid: pid_t) -> AXObserverHandle? {
        AXObserverHandle(pid: pid, token: 1)
    }
    func subscribe(_ handle: AXObserverHandle, notification: String) -> Bool { true }
    func unsubscribe(_ handle: AXObserverHandle, notification: String) {}
    func teardown(_ handle: AXObserverHandle) {}
}

final class DockHoverObserverTests: XCTestCase {
    @MainActor func testObserverInitializes() {
        let coord = AXObserverCoordinator(engine: FakeDockAXObserverEngine(), healthCheckInterval: 999)
        let observer = DockHoverObserver(coordinator: coord)
        XCTAssertNotNil(observer)
    }
}
