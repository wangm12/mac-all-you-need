import ApplicationServices
import Foundation

struct GenericAXWindowProvider: WindowHubTabProvider {
    let providerName = "generic-ax-window"

    func matches(bundleIdentifier: String?) -> Bool { true }

    func capabilities(for bundleIdentifier: String?) -> TabCapability { .windowOnly }

    func tabs(
        pid: pid_t,
        windowID: CGWindowID,
        windowElement: AXUIElement,
        timeoutNanoseconds: UInt64
    ) async -> [WindowHubTabProbe] {
        []
    }
}
