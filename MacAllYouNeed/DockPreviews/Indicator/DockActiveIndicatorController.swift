import AppKit
import SwiftUI

@MainActor
final class DockActiveIndicatorController {
    private var panel: NSPanel?
    private var workspaceObserver: NSObjectProtocol?
    private var hubSettings: DockHubSettings = .default

    func apply(settings: DockHubSettings) {
        hubSettings = settings
        stop()
        guard settings.master.enableActiveAppIndicator, AXIsProcessTrusted() else { return }

        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.update(for: app)
        }

        if let app = NSWorkspace.shared.frontmostApplication {
            update(for: app)
        }
    }

    func stop() {
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
        workspaceObserver = nil
        panel?.close()
        panel = nil
    }

    private func update(for app: NSRunningApplication) {
        guard let frame = dockIconFrame(for: app) else {
            panel?.orderOut(nil)
            return
        }
        let line = indicatorFrame(anchoredTo: frame)
        if panel == nil {
            panel = makePanel()
        }
        guard let panel else { return }
        panel.setFrame(line, display: true)
        panel.orderFrontRegardless()
    }

    private func indicatorFrame(anchoredTo icon: CGRect) -> CGRect {
        let height = hubSettings.indicator.autoSize ? 3 : CGFloat(hubSettings.indicator.height)
        let inset = CGFloat(hubSettings.indicator.offset)
        let edge = DockPreviewDockPosition.currentEdge()
        switch edge {
        case .bottom:
            return CGRect(
                x: icon.minX + inset,
                y: icon.minY - height - 2,
                width: icon.width - inset * 2,
                height: height
            )
        case .left:
            return CGRect(
                x: icon.maxX + 2,
                y: icon.minY + inset,
                width: height,
                height: icon.height - inset * 2
            )
        case .right:
            return CGRect(
                x: icon.minX - height - 2,
                y: icon.minY + inset,
                width: height,
                height: icon.height - inset * 2
            )
        }
    }

    private func dockIconFrame(for app: NSRunningApplication) -> CGRect? {
        DockAXHelpers.dockIconFrame(for: app)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .fullScreenAuxiliary]
        let color = Color(hex: hubSettings.indicator.colorHex) ?? .accentColor
        panel.contentView = NSHostingView(rootView: Rectangle().fill(color))
        return panel
    }
}

private extension Color {
    init?(hex: String) {
        var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitized.hasPrefix("#") { sanitized.removeFirst() }
        guard sanitized.count == 6, let value = UInt64(sanitized, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
