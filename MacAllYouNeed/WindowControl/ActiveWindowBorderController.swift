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
        let previousInner = self.settings.activeWindowBorderInner
        self.settings = settings
        let shouldRun = runtimeEnabled && settings.activeWindowBorderEnabled
        let styleChanged = previousInner != settings.activeWindowBorderInner
        if shouldRun == enabled, !styleChanged { return }
        enabled = shouldRun
        if shouldRun {
            if styleChanged, panel != nil {
                rebuildPanel()
            } else {
                start()
            }
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
        let cgFrame = element.frame
        guard !cgFrame.isNull, !cgFrame.isEmpty else { return nil }
        guard let screen = WindowScreenDetector.current().screen(containing: cgFrame),
              let nsScreen = NSScreen.screens.first(where: { nsScreen in
                  (nsScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
                      .uint32Value == screen.id
              })
        else { return nil }
        return WindowScreenDetector.convertCGDisplayRectToAppKitCoordinates(
            cgRect: cgFrame,
            appKitScreenFrame: nsScreen.frame,
            cgDisplayBounds: CGDisplayBounds(screen.id)
        )
    }

    private func shouldIgnoreFrontmost() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return true }
        let bundle = app.bundleIdentifier
        if let bundle, settings.ignoredBundleIDs.contains(bundle) { return true }
        let title = frontmostWindowTitle()
        return WindowRulesEngine(rules: settings.windowRules).shouldIgnore(bundleID: bundle, title: title)
    }

    private func frontmostWindowTitle() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let axWindow = value,
              CFGetTypeID(axWindow) == AXUIElementGetTypeID()
        else { return nil }
        return WindowAccessibilityElement(axWindow as! AXUIElement).windowTitle
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
        panel.contentView = NSHostingView(rootView: ActiveWindowBorderView(inner: settings.activeWindowBorderInner))
        self.panel = panel
        return panel
    }

    private func rebuildPanel() {
        guard let panel else {
            start()
            return
        }
        panel.contentView = NSHostingView(rootView: ActiveWindowBorderView(inner: settings.activeWindowBorderInner))
        refresh()
    }
}

private enum ActiveWindowBorderVisualTokens {
    static let accent = Color(red: 10 / 255, green: 132 / 255, blue: 1)
    static let strokeOpacity: CGFloat = 0.50
    static let glowOpacity: CGFloat = 0.34
    static let haloOpacity: CGFloat = 0.18
}

private struct ActiveWindowBorderView: View {
    let inner: Bool

    private var strokeColor: Color {
        ActiveWindowBorderVisualTokens.accent.opacity(ActiveWindowBorderVisualTokens.strokeOpacity)
    }

    private var lineWidth: CGFloat {
        inner ? 1.5 : 2
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(ActiveWindowBorderVisualTokens.accent.opacity(0.05))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(strokeColor, lineWidth: lineWidth)
            }
            .shadow(
                color: ActiveWindowBorderVisualTokens.accent.opacity(ActiveWindowBorderVisualTokens.glowOpacity),
                radius: 10,
                x: 0,
                y: 0
            )
            .shadow(
                color: ActiveWindowBorderVisualTokens.accent.opacity(ActiveWindowBorderVisualTokens.haloOpacity),
                radius: 22,
                x: 0,
                y: 0
            )
    }
}
