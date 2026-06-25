import ApplicationServices
import AppKit
import Foundation

protocol WindowHubTabProvider: Sendable {
    var providerName: String { get }
    func matches(bundleIdentifier: String?) -> Bool
    func capabilities(for bundleIdentifier: String?) -> TabCapability
    func tabs(
        pid: pid_t,
        windowID: CGWindowID,
        windowElement: AXUIElement,
        timeoutNanoseconds: UInt64
    ) async -> [WindowHubTabProbe]
}

struct WindowHubTabProbe: Sendable {
    let key: String
    let title: String
    let domain: String?
    let isActive: Bool
    let isPinned: Bool
    let isAudible: Bool
    let isPrivate: Bool
    let axElement: AXUIElement?
}

enum WindowHubTabProviderRegistry {
    static let all: [any WindowHubTabProvider] = [
        ChromiumBrowserTabProvider(),
        BrowserAXTabProvider(),
        BrowserAppleScriptActionProvider(),
        NativeAXTabProvider(),
        EditorWindowProvider(),
        GenericAXWindowProvider(),
    ]

    static func provider(for bundleIdentifier: String?) -> any WindowHubTabProvider {
        all.first { $0.matches(bundleIdentifier: bundleIdentifier) } ?? GenericAXWindowProvider()
    }
}
