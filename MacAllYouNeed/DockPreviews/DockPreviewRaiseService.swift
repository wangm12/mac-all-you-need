import AppKit
import ApplicationServices
import Foundation

@MainActor
final class DockPreviewRaiseService {
    private let api: any DockPreviewPrivateAPI
    private let enumerator: any WindowEnumerating

    init(
        api: any DockPreviewPrivateAPI = SystemDockPreviewPrivateAPI(),
        enumerator: any WindowEnumerating = SystemWindowEnumerator()
    ) {
        self.api = api
        self.enumerator = enumerator
    }

    func raise(entry: DockPreviewWindowEntry, settings: DockPreviewSettings = DockPreviewSettingsStore.load()) async {
        var target = entry
        if !windowExists(target.id, pid: target.pid) {
            let fresh = await enumerator.windows(for: target.pid, settings: settings)
            if let match = fresh.first(where: { $0.title == entry.title }) ?? fresh.first {
                target = match
            }
        }

        unminimizeIfNeeded(pid: target.pid, windowID: target.id)
        axRaise(pid: target.pid, windowID: target.id)

        if let app = NSRunningApplication(processIdentifier: target.pid) {
            if app.isHidden { app.unhide() }
            app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        }
        _ = api.raiseWindow(windowID: target.id, pid: target.pid)
    }

    private func windowExists(_ windowID: CGWindowID, pid: pid_t) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[CFString: Any]] else {
            return false
        }
        return list.contains { info in
            (info[kCGWindowNumber] as? CGWindowID) == windowID
                && (info[kCGWindowOwnerPID] as? Int32) == pid
        }
    }

    private func unminimizeIfNeeded(pid: pid_t, windowID: CGWindowID) {
        let appElement = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement]
        else { return }
        for window in windows {
            guard api.axWindowID(for: window) == windowID else { continue }
            var minimized: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimized)
            if (minimized as? Bool) == true {
                AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, false as CFTypeRef)
            }
            break
        }
    }

    private func axRaise(pid: pid_t, windowID: CGWindowID) {
        let appElement = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement]
        else { return }
        for window in windows where api.axWindowID(for: window) == windowID {
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            break
        }
    }
}
