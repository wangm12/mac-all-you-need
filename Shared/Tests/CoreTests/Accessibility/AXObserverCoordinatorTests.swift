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

    @MainActor
    func testEngineEventReachesCallbackWithPID() {
        let engine = FakeAXObserverEngine()
        let coordinator = AXObserverCoordinator(engine: engine, healthCheckInterval: 999, now: { Date() })
        var received: [(String, pid_t)] = []
        coordinator.start(pid: 11, notifications: ["AXWindowCreated"]) { n, pid in received.append((n, pid)) }
        coordinator.dispatch(notification: "AXWindowCreated")
        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(received.first?.0, "AXWindowCreated")
        XCTAssertEqual(received.first?.1, 11)
    }

    @MainActor
    func testDispatchAfterStopIsIgnored() {
        let engine = FakeAXObserverEngine()
        let coordinator = AXObserverCoordinator(engine: engine, healthCheckInterval: 999)
        var count = 0
        coordinator.start(pid: 1, notifications: ["AXWindowCreated"]) { _, _ in count += 1 }
        coordinator.stop()
        coordinator.dispatch(notification: "AXWindowCreated")
        XCTAssertEqual(count, 0)
        XCTAssertEqual(engine.torndown, 1)
    }

    @MainActor
    func testHealthCheckReSubscribesWhenHandleIsStale() {
        let engine = FakeAXObserverEngine()
        let coordinator = AXObserverCoordinator(engine: engine, healthCheckInterval: 999)
        coordinator.start(pid: 5, notifications: ["AXWindowCreated"]) { _, _ in }
        XCTAssertEqual(engine.created, [5])
        XCTAssertEqual(engine.subscriptions.count, 1)
        coordinator.markStaleForTesting()
        coordinator.healthCheckNow()
        XCTAssertEqual(engine.created, [5, 5])
        XCTAssertEqual(engine.subscriptions.count, 2)
        XCTAssertEqual(engine.torndown, 1)
    }

    @MainActor
    func testHealthCheckIsNoOpWhenHandleIsHealthy() {
        let engine = FakeAXObserverEngine()
        let coordinator = AXObserverCoordinator(engine: engine, healthCheckInterval: 999)
        coordinator.start(pid: 5, notifications: ["AXWindowCreated"]) { _, _ in }
        coordinator.healthCheckNow()
        XCTAssertEqual(engine.created, [5])
        XCTAssertEqual(engine.subscriptions.count, 1)
        XCTAssertEqual(engine.torndown, 0)
    }

    func testSystemEngineConstructs() {
        let engine = SystemAXObserverEngine()
        XCTAssertNotNil(engine as AXObserverEngine)
    }

    @MainActor
    func testChildElementSubscriptionRoutesEvents() {
        let engine = FakeAXObserverEngine()
        let coordinator = AXObserverCoordinator(engine: engine, healthCheckInterval: 999)
        let dockList = AXUIElementCreateApplication(0)
        var received: [String] = []
        coordinator.start(pid: 99, targetElement: dockList, notifications: ["AXSelectedChildrenChanged"]) { notification, _ in received.append(notification) }
        XCTAssertEqual(engine.created, [99])
        XCTAssertEqual(engine.subscriptions.count, 1)
        XCTAssertEqual(engine.subscriptions.first?.notification, "AXSelectedChildrenChanged")
        coordinator.dispatch(notification: "AXSelectedChildrenChanged")
        XCTAssertEqual(received, ["AXSelectedChildrenChanged"])
    }
}
