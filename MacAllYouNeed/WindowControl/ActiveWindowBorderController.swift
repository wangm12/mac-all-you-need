import AppKit
import ApplicationServices
import Core
import Platform
import SwiftUI

/// Draws an inner or outer border around the frontmost window (Tangrid-style).
///
/// Driven by AX notifications (kAXWindowMovedNotification, kAXWindowResizedNotification,
/// kAXFocusedWindowChangedNotification) instead of a periodic timer, so the border
/// updates reactively with zero idle-CPU cost.
@MainActor
final class ActiveWindowBorderController {
    private var panel: NSPanel?
    private var settings: WindowControlSettings = .default
    private var enabled = false

    // AX observer wired to the currently-frontmost app's PID.
    private let axCoordinator = AXObserverCoordinator(engine: SystemAXObserverEngine())
    // Workspace observer — re-subscribes AX when the active app changes.
    private var workspaceObserver: NSObjectProtocol?
    // PID of the app the coordinator is currently subscribed to.
    private var observedPID: pid_t?

    private static let axNotifications: [String] = [
        kAXWindowMovedNotification as String,
        kAXWindowResizedNotification as String,
        kAXFocusedWindowChangedNotification as String,
    ]

    func apply(settings: WindowControlSettings, runtimeEnabled: Bool) {
        self.settings = settings
        let shouldRun = runtimeEnabled && settings.activeWindowBorderEnabled
        if shouldRun == enabled { return }
        enabled = shouldRun
        if shouldRun {
            start()
        } else {
            stop()
        }
    }

    func stop() {
        axCoordinator.stop()
        observedPID = nil
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
            self.workspaceObserver = nil
        }
        panel?.orderOut(nil)
        panel = nil
    }

    private func start() {
        stop()
        installWorkspaceObserver()
        attachObserver(to: NSWorkspace.shared.frontmostApplication)
        refresh()
    }

    /// Subscribe the AX coordinator to `app`, replacing any previous subscription.
    private func attachObserver(to app: NSRunningApplication?) {
        guard let app else {
            axCoordinator.stop()
            observedPID = nil
            return
        }
        let pid = app.processIdentifier
        guard pid != observedPID else { return }
        observedPID = pid
        axCoordinator.start(pid: pid, notifications: Self.axNotifications) { [weak self] _, _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    private func installWorkspaceObserver() {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self, self.enabled else { return }
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self.attachObserver(to: app)
            self.refresh()
        }
    }

    private func refresh() {
        guard enabled else { return }
        guard let frame = frontmostWindowFrame(),
              !shouldIgnoreFrontmost()
        else {
            panel?.orderOut(nil)
            return
        }
        let inset: CGFloat = settings.activeWindowBorderInner ? 4 : -3
        let borderFrame = frame.insetBy(dx: inset, dy: inset)
        let panel = ensurePanel()
        panel.setFrame(borderFrame, display: true)
        panel.orderFrontRegardless()
    }

    private func shouldIgnoreFrontmost() -> Bool {
        guard let bundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return true }
        return settings.ignoredBundleIDs.contains(bundle)
    }

    private func frontmostWindowFrame() -> CGRect? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let axWindow = value
        else { return nil }
        let axElement = axWindow as! AXUIElement
        let element = WindowAccessibilityElement(axElement)
        guard element.isSupportedForWindowControl else { return nil }
        let frame = element.frame
        guard !frame.isNull, !frame.isEmpty else { return nil }
        guard let screen = NSScreen.screens.first else { return nil }
        let appKitY = screen.frame.height - frame.origin.y - frame.height
        return CGRect(x: frame.origin.x, y: appKitY, width: frame.width, height: frame.height)
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = true
        let hosting = NSHostingView(rootView: ActiveWindowBorderView(inner: settings.activeWindowBorderInner))
        panel.contentView = hosting
        self.panel = panel
        return panel
    }
}

private struct ActiveWindowBorderView: View {
    let inner: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(Color.accentColor.opacity(0.9), lineWidth: inner ? 2 : 3)
    }
}
