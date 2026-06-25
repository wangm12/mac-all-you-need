import ApplicationServices
import Foundation

/// Resolves the outer application shell AX window for a CGWindowID.
///
/// Chromium browsers expose each tab as a separate movable `AXWindow`. Matching
/// by frame against `kAXWindows` routinely picks the tab under the cursor.
/// Remote-token lookup maps to the real window-server window for the CGWindowID.
public enum WindowAXShellResolver {
    private struct CacheKey: Hashable {
        let pid: pid_t
        let windowID: CGWindowID
    }

    private static let cacheLock = NSLock()
    private static var cache: [CacheKey: AXUIElement] = [:]
    private static let maxRemoteTokenScan: UInt64 = 1536
    private static let remoteTokenTID: Int32 = 0x636f_636f // 'coco'

    public static let browserBundleIdentifiers: Set<String> = [
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "com.apple.Safari",
        "company.thebrowser.Browser",
        "org.mozilla.firefox",
        "com.microsoft.edgemac",
        "com.brave.Browser",
        "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera",
    ]

    public static let chromiumBundleIdentifiers: Set<String> = [
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "com.microsoft.edgemac",
        "com.brave.Browser",
        "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera",
    ]

    public static func isBrowserBundle(_ bundleIdentifier: String) -> Bool {
        browserBundleIdentifiers.contains(bundleIdentifier)
    }

    public static func isChromiumBundle(_ bundleIdentifier: String) -> Bool {
        chromiumBundleIdentifiers.contains(bundleIdentifier)
    }

    public static func shellElement(
        processIdentifier: pid_t,
        windowID: CGWindowID,
        ownerBundleIdentifier: String?
    ) -> WindowAccessibilityElement? {
        guard windowID != 0 else { return nil }
        configureApplicationAX(processIdentifier)

        if let cached = cachedElement(processIdentifier: processIdentifier, windowID: windowID) {
            return WindowAccessibilityElement(cached)
        }

        let api = SystemWindowServerPrivateAPI.shared
        if let element = resolveViaRemoteToken(api: api, processIdentifier: processIdentifier, windowID: windowID) {
            storeCachedElement(element, processIdentifier: processIdentifier, windowID: windowID)
            return WindowAccessibilityElement(element)
        }

        return fallbackFromAXWindows(
            processIdentifier: processIdentifier,
            windowID: windowID,
            ownerBundleIdentifier: ownerBundleIdentifier
        )
    }

    public static func clearCache() {
        cacheLock.lock()
        cache.removeAll()
        cacheLock.unlock()
    }

    private static func cachedElement(processIdentifier: pid_t, windowID: CGWindowID) -> AXUIElement? {
        let key = CacheKey(pid: processIdentifier, windowID: windowID)
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return cache[key]
    }

    private static func storeCachedElement(
        _ element: AXUIElement,
        processIdentifier: pid_t,
        windowID: CGWindowID
    ) {
        let key = CacheKey(pid: processIdentifier, windowID: windowID)
        cacheLock.lock()
        cache[key] = element
        cacheLock.unlock()
    }

    private static func configureApplicationAX(_ processIdentifier: pid_t) {
        let appElement = AXUIElementCreateApplication(processIdentifier)
        AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
    }

    private static func resolveViaRemoteToken(
        api: SystemWindowServerPrivateAPI,
        processIdentifier: pid_t,
        windowID: CGWindowID
    ) -> AXUIElement? {
        var elementID: UInt64 = 0
        while elementID < maxRemoteTokenScan {
            defer { elementID += 1 }
            let token = remoteToken(pid: processIdentifier, tid: remoteTokenTID, elementID: elementID)
            guard let element = api.axElementWithRemoteToken(token) else { continue }
            guard api.axWindowID(for: element) == windowID else { continue }
            return element
        }
        return nil
    }

    private static func fallbackFromAXWindows(
        processIdentifier: pid_t,
        windowID: CGWindowID,
        ownerBundleIdentifier: String?
    ) -> WindowAccessibilityElement? {
        let windows = WindowAccessibilityElement.windows(for: processIdentifier)
        var pool = windows.filter { $0.cgWindowID == windowID }
        if pool.isEmpty {
            pool = windows
        }

        if let ownerBundleIdentifier, isChromiumBundle(ownerBundleIdentifier) {
            let shells = pool.filter { $0.isBrowserShellWindow }
            if let shell = shells.max(by: { $0.frame.area < $1.frame.area }) {
                return shell
            }
        }

        return pool.max(by: { $0.windowTargetSelectionPriority < $1.windowTargetSelectionPriority })
    }

    private static func remoteToken(pid: pid_t, tid: Int32, elementID: UInt64) -> Data {
        var data = Data(count: 0x14)
        data.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            var pidValue = UInt32(bitPattern: pid)
            var tidValue = tid
            var idValue = elementID
            memcpy(base, &pidValue, 4)
            memset(base + 4, 0, 4)
            memcpy(base + 8, &tidValue, 4)
            memcpy(base + 12, &idValue, 8)
        }
        return data
    }
}

private extension CGRect {
    var area: CGFloat { width * height }
}
