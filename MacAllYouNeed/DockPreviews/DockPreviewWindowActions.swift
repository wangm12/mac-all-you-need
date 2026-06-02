import AppKit
import ApplicationServices
import Foundation

enum DockPreviewWindowActions {
    static func close(entry: DockPreviewWindowEntry) {
        perform(entry: entry, action: kAXPressAction)
    }

    static func minimize(entry: DockPreviewWindowEntry) {
        var minimized: CFTypeRef = kCFBooleanTrue
        setAttribute(entry: entry, attribute: kAXMinimizedAttribute as CFString, value: minimized)
    }

    static func unminimize(entry: DockPreviewWindowEntry) {
        var minimized: CFTypeRef = kCFBooleanFalse
        setAttribute(entry: entry, attribute: kAXMinimizedAttribute as CFString, value: minimized)
    }

    static func applySwipe(_ action: DockWindowSwipeAction, entry: DockPreviewWindowEntry) {
        switch action {
        case .none: break
        case .minimize: minimize(entry: entry)
        case .maximize: zoom(entry: entry)
        case .close: close(entry: entry)
        case .quit: quitApplication(pid: entry.pid)
        case .toggleFullScreen: toggleFullScreen(entry: entry)
        }
    }

    static func zoom(entry: DockPreviewWindowEntry) {
        perform(entry: entry, action: "AXZoom")
    }

    static func toggleFullScreen(entry: DockPreviewWindowEntry) {
        perform(entry: entry, action: "AXFullScreen")
    }

    static func quitApplication(pid: pid_t) {
        guard pid != 0 else { return }
        if let app = NSRunningApplication(processIdentifier: pid) {
            app.terminate()
        }
    }

    private static func perform(entry: DockPreviewWindowEntry, action: String) {
        guard let window = axWindow(for: entry) else { return }
        AXUIElementPerformAction(window, action as CFString)
    }

    private static func setAttribute(entry: DockPreviewWindowEntry, attribute: CFString, value: CFTypeRef) {
        guard let window = axWindow(for: entry) else { return }
        AXUIElementSetAttributeValue(window, attribute, value)
    }

    private static func axWindow(for entry: DockPreviewWindowEntry) -> AXUIElement? {
        let app = AXUIElementCreateApplication(entry.pid)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement]
        else { return nil }
        let api = SystemDockPreviewPrivateAPI()
        for window in windows {
            if api.axWindowID(for: window) == entry.id {
                return window
            }
        }
        return windows.first
    }
}
