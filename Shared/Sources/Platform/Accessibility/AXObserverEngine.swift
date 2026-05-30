import ApplicationServices
import Foundation

public struct AXObserverHandle {
    public let pid: pid_t
    let token: Int
    var axObserver: AXObserver?
    var appElement: AXUIElement?
    var targetElement: AXUIElement?

    public init(pid: pid_t, token: Int, axObserver: AXObserver? = nil, appElement: AXUIElement? = nil, targetElement: AXUIElement? = nil) {
        self.pid = pid; self.token = token; self.axObserver = axObserver; self.appElement = appElement; self.targetElement = targetElement
    }
}

public protocol AXObserverEngine: Sendable {
    func makeObserver(pid: pid_t) -> AXObserverHandle?
    func subscribe(_ handle: AXObserverHandle, notification: String) -> Bool
    func unsubscribe(_ handle: AXObserverHandle, notification: String)
    func teardown(_ handle: AXObserverHandle)
}

public final class SystemAXObserverEngine: AXObserverEngine, @unchecked Sendable {
    private final class Box {
        let onEvent: (String) -> Void
        init(_ onEvent: @escaping (String) -> Void) { self.onEvent = onEvent }
    }
    private var boxes: [Int: Box] = [:]
    private var nextToken = 0
    private let onEventFactory: (pid_t) -> (String) -> Void

    public init(onEventFactory: @escaping (pid_t) -> (String) -> Void = { _ in { _ in } }) {
        self.onEventFactory = onEventFactory
    }

    public func makeObserver(pid: pid_t) -> AXObserverHandle? {
        var observer: AXObserver?
        let callback: AXObserverCallback = { _, _, notification, refcon in
            guard let refcon else { return }
            Unmanaged<Box>.fromOpaque(refcon).takeUnretainedValue().onEvent(notification as String)
        }
        guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { return nil }
        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
        nextToken += 1
        boxes[nextToken] = Box(onEventFactory(pid))
        let appElement = AXUIElementCreateApplication(pid)
        return AXObserverHandle(pid: pid, token: nextToken, axObserver: observer, appElement: appElement)
    }

    public func subscribe(_ handle: AXObserverHandle, notification: String) -> Bool {
        guard let observer = handle.axObserver,
              let element = handle.targetElement ?? handle.appElement,
              let box = boxes[handle.token] else { return false }
        let refcon = Unmanaged.passUnretained(box).toOpaque()
        return AXObserverAddNotification(observer, element, notification as CFString, refcon) == .success
    }

    public func unsubscribe(_ handle: AXObserverHandle, notification: String) {
        guard let observer = handle.axObserver, let element = handle.appElement else { return }
        AXObserverRemoveNotification(observer, element, notification as CFString)
    }

    public func teardown(_ handle: AXObserverHandle) {
        if let observer = handle.axObserver {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        boxes[handle.token] = nil
    }
}
