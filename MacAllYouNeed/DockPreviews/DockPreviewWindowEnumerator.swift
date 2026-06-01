import ApplicationServices
import AppKit
import Foundation
import ScreenCaptureKit

protocol WindowEnumerating: Sendable {
    func windows(
        for pid: pid_t,
        settings: DockPreviewSettings,
        bundleIdentifier: String?
    ) async -> [DockPreviewWindowEntry]
}

final class SystemWindowEnumerator: WindowEnumerating, @unchecked Sendable {
    private let api: any DockPreviewPrivateAPI

    init(api: any DockPreviewPrivateAPI = SystemDockPreviewPrivateAPI()) {
        self.api = api
    }

    func windows(
        for pid: pid_t,
        settings: DockPreviewSettings,
        bundleIdentifier: String?
    ) async -> [DockPreviewWindowEntry] {
        let pids = targetPIDs(primary: pid, bundleIdentifier: bundleIdentifier, settings: settings)
        var combined: [DockPreviewWindowEntry] = []
        var seenIDs = Set<CGWindowID>()
        for targetPID in pids {
            let entries = await windowsForSinglePID(targetPID, settings: settings)
            for entry in entries where seenIDs.insert(entry.id).inserted {
                combined.append(entry)
            }
        }
        combined = DockPreviewWindowFilter.filter(combined, settings: settings)
        combined = DockPreviewWindowFilter.filterBySpace(combined, settings: settings)
        combined = DockPreviewWindowOrderStore.sort(combined, bundleIdentifier: bundleIdentifier, order: settings.sortOrder)
        if settings.ignoreSingleWindowApps, combined.count <= 1 {
            return []
        }
        return combined
    }

    private func targetPIDs(primary: pid_t, bundleIdentifier: String?, settings: DockPreviewSettings) -> [pid_t] {
        guard settings.groupAppInstances,
              let bundleIdentifier,
              !bundleIdentifier.isEmpty
        else { return [primary] }
        let matches = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        if matches.isEmpty { return [primary] }
        return matches.map(\.processIdentifier)
    }

    private func windowsForSinglePID(_ pid: pid_t, settings: DockPreviewSettings) async -> [DockPreviewWindowEntry] {
        let scWindows = await scWindows(for: pid)
        let axWindows = axWindowInfos(for: pid)
        return DockPreviewWindowMatcher.merge(ax: axWindows, sc: scWindows, pid: pid)
    }

    private func scWindows(for pid: pid_t) async -> [DockPreviewWindowMatcher.SCWindowInfo] {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) else {
            return cgFallbackWindows(for: pid)
        }
        let candidates = content.windows.filter { window in
            guard window.owningApplication?.processID == pid else { return false }
            let frame = window.frame
            return frame.width >= 120 && frame.height >= 80
        }
        return filterNestedWindows(candidates).map { window in
            DockPreviewWindowMatcher.SCWindowInfo(
                windowID: CGWindowID(window.windowID),
                frame: window.frame,
                pid: pid,
                title: window.title ?? ""
            )
        }
    }

    private func filterNestedWindows(_ windows: [SCWindow]) -> [SCWindow] {
        windows.filter { candidate in
            let candidateArea = candidate.frame.width * candidate.frame.height
            guard candidateArea > 0 else { return false }
            let dominated = windows.contains { other in
                guard other.windowID != candidate.windowID else { return false }
                let otherArea = other.frame.width * other.frame.height
                guard otherArea > candidateArea * 1.05 else { return false }
                return other.frame.contains(candidate.frame)
            }
            return !dominated
        }
    }

    private func cgFallbackWindows(for pid: pid_t) -> [DockPreviewWindowMatcher.SCWindowInfo] {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[CFString: Any]] else { return [] }
        return list.compactMap { info -> DockPreviewWindowMatcher.SCWindowInfo? in
            guard (info[kCGWindowOwnerPID] as? Int32) == pid,
                  let windowID = info[kCGWindowNumber] as? CGWindowID
            else { return nil }
            let boundsDict = info[kCGWindowBounds] as? [String: CGFloat]
            let frame = CGRect(
                x: boundsDict?["X"] ?? 0,
                y: boundsDict?["Y"] ?? 0,
                width: boundsDict?["Width"] ?? 0,
                height: boundsDict?["Height"] ?? 0
            )
            let title = (info[kCGWindowName] as? String) ?? ""
            return DockPreviewWindowMatcher.SCWindowInfo(windowID: windowID, frame: frame, pid: pid, title: title)
        }
    }

    private func axWindowInfos(for pid: pid_t) -> [DockPreviewWindowMatcher.AXWindowInfo] {
        let appElement = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let axWindows = windowsRef as? [AXUIElement]
        else { return [] }

        return axWindows.compactMap { window -> DockPreviewWindowMatcher.AXWindowInfo? in
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
            let title = titleRef as? String ?? ""

            var minimizedRef: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedRef)
            let isMinimized = (minimizedRef as? Bool) ?? false

            var position: CFTypeRef?
            var size: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &position)
            AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &size)
            var point = CGPoint.zero
            var cgSize = CGSize.zero
            if let posValue = position { AXValueGetValue(posValue as! AXValue, .cgPoint, &point) }
            if let sizeValue = size { AXValueGetValue(sizeValue as! AXValue, .cgSize, &cgSize) }
            let frame = CGRect(origin: point, size: cgSize)

            let windowID = api.axWindowID(for: window) ?? 0
            return DockPreviewWindowMatcher.AXWindowInfo(
                title: title,
                isMinimized: isMinimized,
                frame: frame,
                windowID: windowID == 0 ? nil : windowID
            )
        }
    }
}
