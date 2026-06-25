import ApplicationServices
import Foundation

// Private AppKit/HIServices symbols. These are unsupported by Apple but are the
// only reliable way to (a) map an AX window element to its CGWindowID and
// (b) obtain AX elements for windows living on *inactive* Spaces. The public
// `kAXWindowsAttribute` only returns windows on the current Space.
//
// Technique attribution (brute-forced remote tokens):
//   https://github.com/lwouis/alt-tab-macos/issues/1324 (decodism)
//   https://github.com/koekeishiya/yabai window_manager.c
@_silgen_name("_AXUIElementCreateWithRemoteToken")
private func _AXUIElementCreateWithRemoteToken(_ data: CFData) -> Unmanaged<AXUIElement>?

@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ identifier: UnsafeMutablePointer<UInt32>) -> AXError

enum WindowHubAXWindowBridge {
    /// Upper bound on remote-token element IDs probed per app. Window element IDs
    /// are small per-app counters, but the ID space also covers non-window
    /// elements, so we cap the scan and early-exit once all targets are matched.
    private static let maxElementID: UInt64 = 1536

    private static let lock = NSLock()
    private static var tokenCache: [pid_t: [UInt64: CGWindowID]] = [:]

    static func resetForRefresh() {
        lock.lock()
        tokenCache.removeAll()
        lock.unlock()
    }

    static func evict(pid: pid_t) {
        lock.lock()
        tokenCache.removeValue(forKey: pid)
        lock.unlock()
    }

    /// Returns the CGWindowID backing an AX window element, if available.
    static func windowID(for element: AXUIElement) -> CGWindowID? {
        var identifier: UInt32 = 0
        guard _AXUIElementGetWindow(element, &identifier) == .success, identifier != 0 else {
            return nil
        }
        return identifier
    }

    /// Mints AX window elements for windows that the public API omits (inactive
    /// Spaces). Brute-forces remote tokens for `pid` and matches them against the
    /// requested CGWindowIDs.
    static func resolveWindows(pid: pid_t, targetWindowIDs: Set<CGWindowID>) -> [CGWindowID: AXUIElement] {
        guard !targetWindowIDs.isEmpty else { return [:] }
        var remaining = targetWindowIDs
        var resolved: [CGWindowID: AXUIElement] = [:]
        let tid: Int32 = 0x636f_636f // 'coco'

        lock.lock()
        let cached = tokenCache[pid] ?? [:]
        lock.unlock()

        for (elementID, cachedWindowID) in cached where remaining.contains(cachedWindowID) {
            let token = remoteToken(pid: pid, tid: tid, elementID: elementID)
            guard let element = _AXUIElementCreateWithRemoteToken(token as CFData)?.takeRetainedValue() else {
                continue
            }
            guard let wid = Self.windowID(for: element), wid == cachedWindowID else { continue }
            resolved[wid] = element
            remaining.remove(wid)
        }

        var discovered: [UInt64: CGWindowID] = cached
        var elementID: UInt64 = 0
        while elementID < maxElementID, !remaining.isEmpty {
            defer { elementID += 1 }
            if discovered[elementID] != nil { continue }
            let token = remoteToken(pid: pid, tid: tid, elementID: elementID)
            guard let element = _AXUIElementCreateWithRemoteToken(token as CFData)?.takeRetainedValue() else {
                continue
            }
            guard let wid = Self.windowID(for: element), remaining.contains(wid) else { continue }
            resolved[wid] = element
            remaining.remove(wid)
            discovered[elementID] = wid
        }

        lock.lock()
        tokenCache[pid] = discovered
        lock.unlock()

        return resolved
    }

    private static func remoteToken(pid: pid_t, tid: Int32, elementID: UInt64) -> Data {
        var data = Data(count: 0x14) // 20 bytes: pid(4) + pad(4) + tid(4) + elementID(8)
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
