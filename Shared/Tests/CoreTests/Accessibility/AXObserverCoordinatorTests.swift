import ApplicationServices
import Foundation
@testable import Platform
import XCTest

final class FakeAXObserverEngine: AXObserverEngine, @unchecked Sendable {
    struct Subscription: Equatable {
        let pid: pid_t
        let notification: String
    }
    private(set) var created: [pid_t] = []
    private(set) var subscriptions: [Subscription] = []
    private(set) var removed: [Subscription] = []
    private(set) var torndown = 0
    var failNextCreate = false
    var failSubscribeForPID: pid_t?
    func makeObserver(pid: pid_t) -> AXObserverHandle? {
        if failNextCreate { return nil }
        created.append(pid)
        return AXObserverHandle(pid: pid, token: created.count)
    }
    func subscribe(_ handle: AXObserverHandle, notification: String) -> Bool {
        if let failSubscribeForPID, failSubscribeForPID == handle.pid { return false }
        subscriptions.append(.init(pid: handle.pid, notification: notification))
        return true
    }
    func unsubscribe(_ handle: AXObserverHandle, notification: String) {
        removed.append(.init(pid: handle.pid, notification: notification))
    }
    func teardown(_ handle: AXObserverHandle) { torndown += 1 }
}

final class AXObserverCoordinatorTests: XCTestCase {
    func testMakeObserverHandleCarriesPID() {
        let engine = FakeAXObserverEngine()
        let handle = engine.makeObserver(pid: 42)
        XCTAssertEqual(handle?.pid, 42)
        XCTAssertEqual(engine.created, [42])
    }

    @MainActor
    func testStartSubscribesToEveryNotification() {
        let engine = FakeAXObserverEngine()
        let coordinator = AXObserverCoordinator(engine: engine, healthCheckInterval: 999, now: { Date() })
        var received: [String] = []
        coordinator.start(pid: 7, notifications: ["AXWindowCreated", "AXFocusedWindowChanged"]) { notification, _ in received.append(notification) }
        XCTAssertEqual(engine.created, [7])
        XCTAssertEqual(engine.subscriptions, [.init(pid: 7, notification: "AXWindowCreated"), .init(pid: 7, notification: "AXFocusedWindowChanged")])
        XCTAssertTrue(received.isEmpty)
    }
}
