import AppKit
import ApplicationServices
import Core
import Platform
import SwiftUI

/// Draws an inner or outer border around the frontmost window (Tangrid-style).
@MainActor
final class ActiveWindowBorderController {
    private var panel: NSPanel?
    private var timer: Timer?
    private var settings: WindowControlSettings = .default
    private var enabled = false

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
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
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
        let element = WindowAccessibilityElement(axWindow as! AXUIElement)
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
