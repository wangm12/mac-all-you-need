import ApplicationServices
import AppKit
import Foundation

/// Chromium browsers expose tab counts via AX but often omit tab titles.
/// Use one JXA fetch per app; skip per-window AX walks during indexing.
struct ChromiumBrowserTabProvider: WindowHubTabProvider {
    let providerName = "chromium-applescript"

    func matches(bundleIdentifier: String?) -> Bool {
        BrowserAppleScriptTabReader.isChromium(bundleIdentifier)
    }

    func capabilities(for bundleIdentifier: String?) -> TabCapability {
        matches(bundleIdentifier: bundleIdentifier) ? .browserScript : []
    }

    func tabs(
        pid: pid_t,
        windowID: CGWindowID,
        windowElement: AXUIElement,
        timeoutNanoseconds: UInt64
    ) async -> [WindowHubTabProbe] {
        guard let bundleIdentifier = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier else {
            return []
        }
        let scriptWindows = BrowserAppleScriptTabCache.windows(pid: pid, bundleIdentifier: bundleIdentifier)
        guard let windowIndex = BrowserAppleScriptTabCache.assignedWindowIndex(pid: pid, windowID: windowID) else {
            return []
        }
        return BrowserAppleScriptTabCache.probes(windowIndex: windowIndex, scriptWindows: scriptWindows)
    }

    /// Batch path used by the enumerator — one JXA round-trip per Chromium app.
    static func prepareSnapshot(
        pid: pid_t,
        bundleIdentifier: String,
        probes: [BrowserAppleScriptTabCache.WindowProbe]
    ) -> [CGWindowID: [WindowHubTabProbe]] {
        BrowserAppleScriptTabCache.beginSnapshot(pid: pid, bundleIdentifier: bundleIdentifier, forceRefresh: true)
        let scriptWindows = BrowserAppleScriptTabCache.windows(pid: pid, bundleIdentifier: bundleIdentifier)
        let assignments = BrowserAppleScriptTabCache.assignAllWindows(pid: pid, probes: probes)
        var result: [CGWindowID: [WindowHubTabProbe]] = [:]
        for (windowID, windowIndex) in assignments.sorted(by: { $0.key < $1.key }) {
            let tabs = BrowserAppleScriptTabCache.probes(windowIndex: windowIndex, scriptWindows: scriptWindows)
            guard !tabs.isEmpty else { continue }
            result[windowID] = tabs
        }
        return result
    }
}

enum WindowHubAppleScriptTabKey {
    static func parse(_ raw: String) -> (windowIndex: Int, tabIndex: Int)? {
        let parts = raw.split(separator: ":")
        guard parts.count >= 3, parts[0] == "as",
              let windowIndex = Int(parts[1]),
              let tabIndex = Int(parts[2])
        else { return nil }
        return (windowIndex, tabIndex)
    }

    static func from(targetID: WindowHubTargetID) -> (windowIndex: Int, tabIndex: Int)? {
        let prefix = targetID.raw.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false)
        guard prefix.count == 4 else { return nil }
        return parse(String(prefix[3]))
    }
}
