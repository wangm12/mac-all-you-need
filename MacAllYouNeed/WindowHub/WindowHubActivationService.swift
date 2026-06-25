import AppKit
import ApplicationServices
import Foundation

enum WindowHubActivationService {
    static func activate(target: WindowHubTarget, in snapshot: WindowHubSnapshot) async -> WindowHubSwitchResult {
        guard AXIsProcessTrusted() else { return .permissionDenied }
        guard let app = NSRunningApplication(processIdentifier: target.pid) else { return .staleWindow }

        if target.isMinimized, let windowID = target.windowID {
            unminimize(pid: target.pid, windowID: windowID)
        }

        if app.isHidden { app.unhide() }

        switch target.kind {
        case .app:
            app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
            return verifyFrontmost(app: app, expectedTitle: nil)
        case .window:
            guard let windowID = target.windowID else { return .unsupported }
            if await focusChromiumWindow(target: target) {
                return verifyFrontmost(app: app, expectedTitle: target.windowTitle)
            }
            app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
            raiseWindow(pid: target.pid, windowID: windowID, title: target.windowTitle)
            return verifyFrontmost(app: app, expectedTitle: target.windowTitle)
        case .tab:
            guard let windowID = target.windowID else { return .unsupported }
            if await focusChromiumTab(target: target) {
                return verifyFrontmost(app: app, expectedTitle: target.tabTitle ?? target.windowTitle)
            }
            app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
            raiseWindow(pid: target.pid, windowID: windowID, title: target.windowTitle)
            if await focusTab(target: target) {
                return verifyFrontmost(app: app, expectedTitle: target.tabTitle ?? target.windowTitle)
            }
            return .switchedAppOnly
        }
    }

    private static func focusChromiumTab(target: WindowHubTarget) async -> Bool {
        guard target.kind == .tab,
              let bundleID = target.bundleIdentifier,
              BrowserAppleScriptTabReader.isChromium(bundleID),
              let indices = WindowHubAppleScriptTabKey.from(targetID: target.id)
        else { return false }

        return await runOnBackground {
            BrowserAppleScriptTabReader.activateTab(
                bundleIdentifier: bundleID,
                windowIndex: indices.windowIndex,
                tabIndex: indices.tabIndex
            )
        }
    }

    private static func focusChromiumWindow(target: WindowHubTarget) async -> Bool {
        guard target.kind == .window,
              let bundleID = target.bundleIdentifier,
              BrowserAppleScriptTabReader.isChromium(bundleID),
              let windowIndex = BrowserAppleScriptTabCache.assignedWindowIndex(
                pid: target.pid,
                windowID: target.windowID ?? 0
              )
        else { return false }

        return await runOnBackground {
            BrowserAppleScriptTabReader.activateWindow(
                bundleIdentifier: bundleID,
                windowIndex: windowIndex
            )
        }
    }

    private static func raiseWindow(pid: pid_t, windowID: CGWindowID, title: String?) {
        let appElement = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        let currentSpaceWindows = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success
            ? (windowsRef as? [AXUIElement]) ?? []
            : []

        var target = currentSpaceWindows.first { WindowHubAXWindowBridge.windowID(for: $0) == windowID }
        if target == nil, let title {
            target = currentSpaceWindows.first { axWindowTitle($0) == title }
        }
        if target == nil {
            target = WindowHubAXWindowBridge.resolveWindows(pid: pid, targetWindowIDs: [windowID])[windowID]
        }

        guard let window = target ?? currentSpaceWindows.first else { return }
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, window)
    }

    private static func focusTab(target: WindowHubTarget) async -> Bool {
        guard let windowID = target.windowID else { return false }
        let appElement = AXUIElementCreateApplication(target.pid)
        var windowsRef: CFTypeRef?
        let currentSpaceWindows = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success
            ? (windowsRef as? [AXUIElement]) ?? []
            : []

        var window = currentSpaceWindows.first { WindowHubAXWindowBridge.windowID(for: $0) == windowID }
        if window == nil {
            window = currentSpaceWindows.first { axWindowTitle($0) == target.windowTitle }
        }
        if window == nil {
            window = WindowHubAXWindowBridge.resolveWindows(pid: target.pid, targetWindowIDs: [windowID])[windowID]
        }
        guard let window = window ?? currentSpaceWindows.first else {
            return false
        }

        let provider = WindowHubTabProviderRegistry.provider(for: target.bundleIdentifier)
        let tabs = await provider.tabs(
            pid: target.pid,
            windowID: windowID,
            windowElement: window,
            timeoutNanoseconds: 200_000_000
        )
        guard let tab = tabs.first(where: { tabMatchesTarget($0, target: target) })
            ?? tabs.first(where: { $0.title == target.tabTitle })
            ?? tabs.first(where: \.isActive)
        else { return false }

        guard let element = tab.axElement else { return false }

        let pressed = AXUIElementPerformAction(element, kAXPressAction as CFString)
        if pressed == .success { return true }
        return AXUIElementSetAttributeValue(element, kAXSelectedAttribute as CFString, true as CFTypeRef) == .success
    }

    private static func unminimize(pid: pid_t, windowID: CGWindowID) {
        let appElement = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement]
        else { return }
        for window in windows {
            _ = windowID
            var minimizedRef: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedRef)
            if (minimizedRef as? Bool) == true {
                AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, false as CFTypeRef)
            }
        }
    }

    private static func verifyFrontmost(app: NSRunningApplication, expectedTitle: String?) -> WindowHubSwitchResult {
        let front = NSWorkspace.shared.frontmostApplication
        guard front?.processIdentifier == app.processIdentifier else { return .switchedAppOnly }
        guard let expectedTitle, !expectedTitle.isEmpty else { return .switched }
        let windows = collectTitles(pid: app.processIdentifier)
        if windows.contains(where: { $0.localizedCaseInsensitiveContains(expectedTitle) }) {
            return .switched
        }
        return .switchedAppOnly
    }

    private static func collectTitles(pid: pid_t) -> [String] {
        let appElement = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement]
        else { return [] }
        return windows.compactMap(axWindowTitle)
    }

    private static func tabMatchesTarget(_ tab: WindowHubTabProbe, target: WindowHubTarget) -> Bool {
        let parts = target.id.raw.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return tab.key == String(parts[3])
    }

    private static func axWindowTitle(_ window: AXUIElement) -> String? {
        var titleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success else {
            return nil
        }
        return titleRef as? String
    }

    private static func runOnBackground<T>(_ work: @escaping () -> T) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: work())
            }
        }
    }
}
