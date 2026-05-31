import ApplicationServices
import Foundation

@MainActor
public final class AXObserverCoordinator {
    public typealias EventCallback = (_ notification: String, _ pid: pid_t) -> Void
    private let engine: AXObserverEngine
    private let healthCheckInterval: TimeInterval
    private let now: () -> Date
    private var handle: AXObserverHandle?
    private var pid: pid_t?
    private var notifications: [String] = []
    private var callback: EventCallback?
    private var healthCheckTask: Task<Void, Never>?
    private var isHandleLive = false
    private var targetElement: AXUIElement?

    public init(engine: AXObserverEngine, healthCheckInterval: TimeInterval = 3, now: @escaping () -> Date = { Date() }) {
        self.engine = engine; self.healthCheckInterval = healthCheckInterval; self.now = now
    }

    public func start(pid: pid_t, notifications: [String], onEvent: @escaping EventCallback) {
        start(pid: pid, targetElement: nil, notifications: notifications, onEvent: onEvent)
    }

    public func start(pid: pid_t, targetElement: AXUIElement? = nil, notifications: [String], onEvent: @escaping EventCallback) {
        stop() // clears everything including targetElement
        self.targetElement = targetElement  // set AFTER stop
        self.pid = pid
        self.notifications = notifications
        self.callback = onEvent
        subscribeAll()
        startHealthCheckTimer()
    }

    public func stop() {
        healthCheckTask?.cancel(); healthCheckTask = nil
        if let handle {
            for notification in notifications { engine.unsubscribe(handle, notification: notification) }
            engine.teardown(handle)
        }
        handle = nil; pid = nil; notifications = []; callback = nil; isHandleLive = false; targetElement = nil
    }

    func dispatch(notification: String) {
        guard let pid else { return }
        callback?(notification, pid)
    }

    func healthCheckNow() {
        guard pid != nil else { return }
        guard !isHandleLive else { return }
        if let handle {
            for notification in notifications { engine.unsubscribe(handle, notification: notification) }
            engine.teardown(handle)
        }
        handle = nil
        subscribeAll()
    }

    func markStaleForTesting() { isHandleLive = false }

    private func subscribeAll() {
        guard let pid else { return }
        guard var newHandle = engine.makeObserver(pid: pid, onEvent: { [weak self] notification in
            self?.dispatch(notification: notification)
        }) else { handle = nil; return }
        if let targetElement { newHandle.targetElement = targetElement }
        var allOK = true
        for notification in notifications where !engine.subscribe(newHandle, notification: notification) { allOK = false }
        handle = newHandle
        isHandleLive = allOK
    }

    private func startHealthCheckTimer() {
        healthCheckTask?.cancel()
        let interval = healthCheckInterval
        healthCheckTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                self.healthCheckNow()
            }
        }
    }
}
