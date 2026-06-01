import AppKit
import Foundation
import Platform

@MainActor
final class DockKeybindController {
    private weak var panelController: DockPreviewPanelController?
    private var hotkey: GlobalHotkey?
    private var flagsMonitor: Any?
    private var hubSettings: DockHubSettings = .default
    private var entries: [DockPreviewWindowEntry] = []
    private var selectedIndex = 0
    private var sessionActive = false

    init(panelController: DockPreviewPanelController) {
        self.panelController = panelController
    }

    func apply(settings: DockHubSettings) {
        hubSettings = settings
        hotkey?.unregister()
        hotkey = nil
        stopSession()
        guard settings.master.enableWindowSwitcher, AXIsProcessTrusted() else { return }

        let shortcut = HotkeyDescriptor(
            keyCode: UInt32(settings.switcher.shortcutKeyCode),
            modifiers: HotkeyDescriptor.Modifiers(rawValue: UInt32(settings.switcher.shortcutModifiers))
        )
        hotkey = GlobalHotkey(descriptor: shortcut) { [weak self] in
            Task { @MainActor in self?.handleHotkeyPressed() }
        }
        try? hotkey?.register()

        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            Task { @MainActor in self?.handleSessionEvent(event) }
        }
    }

    func stop() {
        hotkey?.unregister()
        hotkey = nil
        if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
        flagsMonitor = nil
        stopSession()
    }

    private func handleHotkeyPressed() {
        if sessionActive {
            activateSelection()
            stopSession()
        } else {
            beginSession()
        }
    }

    private func beginSession() {
        let switcher = hubSettings.switcher
        if switcher.instantSwitcher {
            Task { await cycleInstant() }
            return
        }
        Task {
            var collected: [DockPreviewWindowEntry] = []
            let previewSettings = previewSettingsForSwitcher()
            for app in DockWindowDiscovery.runningRegularApplications() {
                let windows = await DockWindowDiscovery.fetchWindows(
                    for: app.processIdentifier,
                    settings: previewSettings,
                    bundleIdentifier: app.bundleIdentifier
                )
                collected.append(contentsOf: windows)
            }
            await MainActor.run {
                guard !collected.isEmpty else { return }
                self.entries = collected
                self.selectedIndex = 0
                self.sessionActive = true
                self.panelController?.state.searchQuery = ""
                self.panelController?.showSwitcher(entries: collected, selectedIndex: 0)
            }
        }
    }

    private func stopSession() {
        sessionActive = false
        entries = []
        panelController?.dismiss(animated: true)
    }

    private func handleSessionEvent(_ event: NSEvent) {
        guard sessionActive else { return }
        if event.type == .flagsChanged, !switcherShortcutModifiersHeld(event.modifierFlags) {
            activateSelection()
            stopSession()
            return
        }
        if event.type == .keyDown, event.keyCode == 48 { // Tab
            cycleSelection(delta: event.modifierFlags.contains(.shift) ? -1 : 1)
        }
    }

    private func switcherShortcutModifiersHeld(_ flags: NSEvent.ModifierFlags) -> Bool {
        let required = NSEvent.ModifierFlags(rawValue: UInt(hubSettings.switcher.shortcutModifiers))
        let tracked: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        let requiredSubset = required.intersection(tracked)
        guard !requiredSubset.isEmpty else { return true }
        return flags.intersection(tracked).isSuperset(of: requiredSubset)
    }

    private func cycleSelection(delta: Int) {
        guard !entries.isEmpty, let panelController else { return }
        panelController.state.selectNext(delta: delta)
        selectedIndex = panelController.state.selectedIndex
        panelController.state.shouldScrollToIndex = true
        panelController.showSwitcher(entries: entries, selectedIndex: selectedIndex)
    }

    private func activateSelection() {
        guard entries.indices.contains(selectedIndex) else { return }
        let entry = entries[selectedIndex]
        Task {
            await DockPreviewRaiseService(enumerator: SystemWindowEnumerator())
                .raise(entry: entry, settings: hubSettings.previews)
        }
    }

    private func cycleInstant() async {
        var collected: [DockPreviewWindowEntry] = []
        let previewSettings = previewSettingsForSwitcher()
        for app in DockWindowDiscovery.runningRegularApplications() {
            let windows = await DockWindowDiscovery.fetchWindows(
                for: app.processIdentifier,
                settings: previewSettings,
                bundleIdentifier: app.bundleIdentifier
            )
            collected.append(contentsOf: windows)
        }
        guard let first = collected.first else { return }
        await DockPreviewRaiseService(enumerator: SystemWindowEnumerator())
            .raise(entry: first, settings: hubSettings.previews)
    }

    private func previewSettingsForSwitcher() -> DockPreviewSettings {
        var settings = hubSettings.previews
        settings.currentSpaceOnly = hubSettings.switcher.currentSpaceOnly
        settings.currentMonitorOnly = hubSettings.switcher.currentMonitorOnly
        settings.includeHiddenMinimized = hubSettings.switcher.includeHiddenWindows
        settings.showWindowlessApps = hubSettings.switcher.showWindowlessApps
        return settings
    }
}
