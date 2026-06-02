import AppKit
import Carbon.HIToolbox
import Foundation

/// Cmd+Tab enhancement: show shared preview while Command is held (DockDoor subset).
@MainActor
final class DockCmdTabController {
    private weak var panelController: DockPreviewPanelController?
    private var flagsMonitor: Any?
    private var keyMonitor: Any?
    private var hubSettings: DockHubSettings = .default
    private var cmdHeld = false
    private var cmdTabEntries: [DockPreviewWindowEntry] = []
    private var cmdTabSelectedIndex = 0

    init(panelController: DockPreviewPanelController) {
        self.panelController = panelController
    }

    func apply(settings: DockHubSettings) {
        hubSettings = settings
        if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        flagsMonitor = nil
        keyMonitor = nil
        guard settings.master.enableCmdTabEnhancements, AXIsProcessTrusted() else { return }
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in self?.handleFlags(event) }
        }
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in self?.handleKeyDown(event) }
        }
    }

    func stop() {
        if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        flagsMonitor = nil
        keyMonitor = nil
        cmdHeld = false
        cmdTabEntries = []
        panelController?.dismiss(animated: true)
    }

    private func handleFlags(_ event: NSEvent) {
        let commandDown = event.modifierFlags.contains(.command)
        if commandDown, !cmdHeld {
            cmdHeld = true
            refreshFrontmostPreview()
        } else if !commandDown, cmdHeld {
            cmdHeld = false
            cmdTabEntries = []
            panelController?.dismiss(animated: true)
        } else if commandDown, cmdHeld {
            refreshFrontmostPreview()
        }
    }

    private func handleKeyDown(_ event: NSEvent) {
        guard cmdHeld, event.modifierFlags.contains(.command) else { return }
        guard !cmdTabEntries.isEmpty, let panelController else { return }
        let cycleKey = hubSettings.cmdTab.cycleKeyCode == 0 ? UInt16(kVK_Tab) : hubSettings.cmdTab.cycleKeyCode
        let backwardKey = hubSettings.cmdTab.backwardCycleKeyCode
        if event.keyCode == cycleKey {
            cycleCmdTab(delta: event.modifierFlags.contains(.shift) ? -1 : 1)
        } else if backwardKey != 0, event.keyCode == backwardKey {
            cycleCmdTab(delta: -1)
        }
    }

    private func cycleCmdTab(delta: Int) {
        guard !cmdTabEntries.isEmpty, let panelController else { return }
        cmdTabSelectedIndex = (cmdTabSelectedIndex + delta + cmdTabEntries.count) % cmdTabEntries.count
        panelController.state.selectedIndex = cmdTabSelectedIndex
        panelController.state.shouldScrollToIndex = true
        panelController.showCmdTab(
            appName: panelController.state.appName,
            appIcon: panelController.state.appIcon,
            entries: cmdTabEntries,
            anchorRect: panelController.state.anchorRect,
            selectedIndex: cmdTabSelectedIndex
        )
        markFocusHintSeenIfNeeded()
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
            settings.useBroadWindowDiscovery = true
            let entries = await DockWindowDiscovery.fetchWindows(
                for: app.processIdentifier,
                settings: settings,
                bundleIdentifier: app.bundleIdentifier
            )
            await MainActor.run {
                guard self.cmdHeld, !entries.isEmpty else { return }
                self.cmdTabEntries = entries
                let start = hubSettings.cmdTab.autoSelectFirstWindow ? 0 : max(0, min(self.cmdTabSelectedIndex, entries.count - 1))
                self.cmdTabSelectedIndex = start
                let anchor = DockAXHelpers.dockIconFrame(for: app)
                    ?? Self.fallbackAnchorRect(for: app)
                self.panelController?.showCmdTab(
                    appName: app.localizedName ?? "",
                    appIcon: app.icon,
                    entries: entries,
                    anchorRect: anchor,
                    selectedIndex: start,
                    showFocusHint: !self.hubSettings.cmdTab.hasSeenFocusHint
                )
            }
        }
    }

    private func markFocusHintSeenIfNeeded() {
        guard !hubSettings.cmdTab.hasSeenFocusHint else { return }
        hubSettings.cmdTab.hasSeenFocusHint = true
        DockHubSettingsStore.save(hubSettings)
        panelController?.state.showCmdTabFocusHint = false
    }
}
