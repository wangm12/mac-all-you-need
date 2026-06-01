import AppKit
import Foundation

/// Cmd+Tab enhancement: show shared preview while Command is held (DockDoor subset).
@MainActor
final class DockCmdTabController {
    private weak var panelController: DockPreviewPanelController?
    private var flagsMonitor: Any?
    private var hubSettings: DockHubSettings = .default
    private var cmdHeld = false

    init(panelController: DockPreviewPanelController) {
        self.panelController = panelController
    }

    func apply(settings: DockHubSettings) {
        hubSettings = settings
        if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
        flagsMonitor = nil
        guard settings.master.enableCmdTabEnhancements, AXIsProcessTrusted() else { return }
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in self?.handleFlags(event) }
        }
    }

    func stop() {
        if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
        flagsMonitor = nil
        cmdHeld = false
        panelController?.dismiss(animated: true)
    }

    private func handleFlags(_ event: NSEvent) {
        let commandDown = event.modifierFlags.contains(.command)
        if commandDown, !cmdHeld {
            cmdHeld = true
            refreshFrontmostPreview()
        } else if !commandDown, cmdHeld {
            cmdHeld = false
            panelController?.dismiss(animated: true)
        } else if commandDown, cmdHeld {
            refreshFrontmostPreview()
        }
    }

    private static func fallbackAnchorRect(for app: NSRunningApplication) -> CGRect {
        _ = app
        let screen = NSScreen.screens.first { screen in
            screen.frame.contains(NSEvent.mouseLocation)
        } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        return CGRect(x: visible.midX, y: visible.minY + 48, width: 1, height: 1)
    }

    private func refreshFrontmostPreview() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        Task {
            var settings = hubSettings.previews
            settings.currentSpaceOnly = hubSettings.cmdTab.currentSpaceOnly
            settings.currentMonitorOnly = hubSettings.cmdTab.currentMonitorOnly
            settings.includeHiddenMinimized = hubSettings.cmdTab.includeHiddenWindows
            settings.showWindowlessApps = hubSettings.cmdTab.showWindowlessApps
            let entries = await DockWindowDiscovery.fetchWindows(
                for: app.processIdentifier,
                settings: settings,
                bundleIdentifier: app.bundleIdentifier
            )
            await MainActor.run {
                guard self.cmdHeld, !entries.isEmpty else { return }
                let anchor = DockAXHelpers.dockIconFrame(for: app)
                    ?? Self.fallbackAnchorRect(for: app)
                self.panelController?.showCmdTab(
                    appName: app.localizedName ?? "",
                    appIcon: app.icon,
                    entries: entries,
                    anchorRect: anchor
                )
            }
        }
    }
}
