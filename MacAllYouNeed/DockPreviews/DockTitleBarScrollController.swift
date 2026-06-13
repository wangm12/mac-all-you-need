import AppKit
import ApplicationServices
import Foundation

/// Title-bar scroll to maximize/center windows (DockDoor `handleTitleBarScroll` subset).
@MainActor
final class DockTitleBarScrollController {
    private var cachedTitleBarRect: CGRect?
    private var cachedWindowPID: pid_t?
    private var cachedWindowID: CGWindowID?
    private let privateAPI = SystemDockPreviewPrivateAPI()
    private var lastActionTime = Date.distantPast
    private var pendingRestoreFrame: CGRect?
    private var pendingRestoreExpiry = Date.distantPast
    private let debounce: TimeInterval = 0.35

    func handleScroll(_ event: CGEvent, settings: DockGestureSettingsFull) -> Bool {
        guard settings.enableTitleBarScrollGesture else { return false }
        let deltaY = event.getDoubleValueField(.scrollWheelEventDeltaAxis1)
        let deltaX = event.getDoubleValueField(.scrollWheelEventDeltaAxis2)
        guard abs(deltaY) > 0.15 || abs(deltaX) > 0.15 else { return false }
        if event.getIntegerValueField(.scrollWheelEventMomentumPhase) != 0 { return false }

        refreshTitleBarCacheIfNeeded()
        guard let titleBar = cachedTitleBarRect,
              titleBar.contains(NSEvent.mouseLocation),
              let pid = cachedWindowPID,
              let windowID = cachedWindowID
        else { return false }

        let now = Date()
        guard now.timeIntervalSince(lastActionTime) >= debounce else { return true }
        lastActionTime = now

        let natural = NSEvent(cgEvent: event)?.isDirectionInvertedFromDevice ?? false
        let normalizedY = natural ? -deltaY : deltaY

        let entry = DockPreviewWindowEntry(
            id: windowID,
            pid: pid,
            title: "",
            frame: .zero,
            thumbnail: nil,
            isMinimized: false,
            isOnScreen: true
        )

        if normalizedY > 0 {
            if let restore = pendingRestoreFrame, pendingRestoreExpiry > now {
                setWindowFrame(restore, entry: entry)
                pendingRestoreFrame = nil
            } else {
                pendingRestoreFrame = currentWindowFrame(entry: entry)
                pendingRestoreExpiry = now.addingTimeInterval(settings.titleBarRestoreInterval)
                DockPreviewWindowActions.zoom(entry: entry)
            }
        } else {
            centerWindow(entry: entry, settings: settings)
        }
        return true
    }

    private func refreshTitleBarCacheIfNeeded() {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            cachedTitleBarRect = nil
            return
        }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedRef) == .success,
              let windowRef = focusedRef,
              CFGetTypeID(windowRef) == AXUIElementGetTypeID()
        else {
            cachedTitleBarRect = nil
            return
        }
        let window = windowRef as! AXUIElement
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posValue = posRef, let sizeValue = sizeRef,
              CFGetTypeID(posValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID(),
              AXValueGetType(posValue as! AXValue) == .cgPoint,
              AXValueGetType(sizeValue as! AXValue) == .cgSize
        else { return }

        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posValue as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)

        let titleBarHeight = min(28, size.height * 0.08)
        cachedTitleBarRect = CGRect(x: position.x, y: position.y, width: size.width, height: titleBarHeight)
        cachedWindowPID = app.processIdentifier
        cachedWindowID = privateAPI.axWindowID(for: window)
    }

    private func currentWindowFrame(entry: DockPreviewWindowEntry) -> CGRect? {
        guard let window = axWindow(for: entry) else { return nil }
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posValue = posRef, let sizeValue = sizeRef,
              CFGetTypeID(posValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posValue as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return CGRect(origin: position, size: size)
    }

    private func setWindowFrame(_ frame: CGRect, entry: DockPreviewWindowEntry) {
        guard let window = axWindow(for: entry) else { return }
        var position = frame.origin
        var size = frame.size
        if let posValue = AXValueCreate(.cgPoint, &position),
           let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }
    }

    private func centerWindow(entry: DockPreviewWindowEntry, settings: DockGestureSettingsFull) {
        guard let screen = NSScreen.main else { return }
        guard var frame = currentWindowFrame(entry: entry) else { return }
        let scale = settings.titleBarSizingMode == .uniform
            ? settings.titleBarCenteredScale
            : min(settings.titleBarCenteredWidthScale, settings.titleBarCenteredHeightScale)
        frame.size.width = screen.visibleFrame.width * scale
        frame.size.height = screen.visibleFrame.height * scale
        frame.origin.x = screen.visibleFrame.midX - frame.width / 2
        frame.origin.y = screen.visibleFrame.midY - frame.height / 2
        setWindowFrame(frame, entry: entry)
    }

    private func axWindow(for entry: DockPreviewWindowEntry) -> AXUIElement? {
        let app = AXUIElementCreateApplication(entry.pid)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement]
        else { return nil }
        return windows.first { privateAPI.axWindowID(for: $0) == entry.id } ?? windows.first
    }
}
