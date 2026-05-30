import ApplicationServices
import Foundation

/// Enumerates windows for a given app PID using ScreenCaptureKit + AX fallback.
protocol WindowEnumerating: Sendable {
    func windows(for pid: pid_t) async -> [DockPreviewWindowEntry]
}

/// Live enumerator using CGWindowListCopyWindowInfo (simpler than SCK for initial implementation).
final class SystemWindowEnumerator: WindowEnumerating, @unchecked Sendable {
    func windows(for pid: pid_t) async -> [DockPreviewWindowEntry] {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[CFString: Any]] else { return [] }

        let pidWindows = list.filter { ($0[kCGWindowOwnerPID] as? Int32) == pid }
        return pidWindows.compactMap { info -> DockPreviewWindowEntry? in
            guard let windowID = info[kCGWindowNumber] as? CGWindowID else { return nil }
            let title = info[kCGWindowName] as? String ?? ""
            let boundsDict = info[kCGWindowBounds] as? [String: CGFloat]
            let frame = CGRect(
                x: boundsDict?["X"] ?? 0,
                y: boundsDict?["Y"] ?? 0,
                width: boundsDict?["Width"] ?? 0,
                height: boundsDict?["Height"] ?? 0
            )
            return DockPreviewWindowEntry(
                id: windowID, pid: pid, title: title, frame: frame,
                thumbnail: nil, isMinimized: false, isOnScreen: true
            )
        }
    }
}
