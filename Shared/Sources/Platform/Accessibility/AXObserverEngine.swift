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
