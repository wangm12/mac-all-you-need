import AppKit
import Foundation

/// Single floating panel for dock hover, switcher, and Cmd+Tab (DockDoor `SharedPreviewWindowCoordinator` subset).
@MainActor
final class DockPreviewPanelController {
    static weak var active: DockPreviewPanelController?

    let state = DockPreviewStateCoordinator()
    let panel = DockPreviewPanel()
    private let raiseService: DockPreviewRaiseService
    private var hubSettings: DockHubSettings = .default
    private let searchWindow = DockPreviewSearchWindow()

    var mouseIsWithinPreview: Bool { panel.mouseIsWithinPreview }
    var isSearchWindowFocused: Bool { searchWindow.isFocused }

    init(enumerator: any WindowEnumerating = SystemWindowEnumerator()) {
        raiseService = DockPreviewRaiseService(enumerator: enumerator)
        panel.bind(state: state)
        searchWindow.bind(state: state)
        panel.onDismissRequest = { [weak self] in self?.dismiss(animated: true) }
    }

    func reloadSettings(_ settings: DockHubSettings) {
        hubSettings = settings
        state.settings = settings.previews
        state.appearance = DockPreviewAppearanceContext.resolve(
            mode: state.mode,
            settings: settings.previews,
            hubAppearance: settings.appearance
        )
        searchWindow.updateAppearance(state.appearance)
    }

    func showHover(
        pid: pid_t,
        appName: String,
        appIcon: NSImage?,
        entries: [DockPreviewWindowEntry],
        anchorRect: CGRect,
        placementKey: UInt,
        embedded: DockEmbeddedContent = .none,
        bundleIdentifier: String? = nil
    ) {
        Self.active = self
        state.mode = .dockHover
        state.bundleIdentifier = bundleIdentifier
        state.appearance = DockPreviewAppearanceContext.resolve(
            mode: .dockHover,
            settings: hubSettings.previews,
            hubAppearance: hubSettings.appearance
        )
        state.embeddedContent = embedded
        state.appName = appName
        state.appIcon = appIcon
        state.anchorRect = anchorRect
        state.dockEdge = DockPreviewDockPosition.currentEdge()
        panel.setCenterOnScreen(false)
        _ = state.setWindows(entries, preserveSelection: false)
        refreshPanelLayout(reposition: true, placementKey: placementKey)
    }

    func showSwitcher(entries: [DockPreviewWindowEntry], selectedIndex: Int) {
        Self.active = self
        state.mode = .windowSwitcher
        state.appearance = DockPreviewAppearanceContext.resolve(
            mode: .windowSwitcher,
            settings: hubSettings.previews,
            hubAppearance: hubSettings.appearance
        )
        state.embeddedContent = .none
        state.appName = "Windows"
        state.appIcon = nil
        state.anchorRect = switcherAnchorRect()
        state.dockEdge = .bottom
        panel.setCenterOnScreen(true)
        state.windows = entries
        state.selectedIndex = selectedIndex
        state.shouldScrollToIndex = true
        state.hasMovedSinceOpen = false
        state.initialHoverLocation = nil
        refreshPanelLayout(reposition: true, placementKey: 0)
        configureSwitcherSearch()
        updateSwitcherLiveStreams()
    }

    /// Lightweight Tab-cycle update — avoids full panel rebuild.
    func updateSwitcherSelection(selectedIndex: Int) {
        guard state.mode == .windowSwitcher else { return }
        state.selectedIndex = selectedIndex
        state.shouldScrollToIndex = true
        scheduleSwitcherLiveCaptureUpdate()
    }

    /// Refresh window list after background enumeration without resetting placement.
    func mergeSwitcherEntries(_ entries: [DockPreviewWindowEntry]) {
        guard state.mode == .windowSwitcher else { return }
        let changed = state.setWindows(entries, preserveSelection: true)
        guard changed else { return }
        refreshPanelLayout(reposition: false, placementKey: 0)
        updateSwitcherLiveStreams()
    }

    private func switcherAnchorRect() -> CGRect {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        return screen?.visibleFrame ?? .zero
    }

    private var liveCaptureDebounceTask: Task<Void, Never>?

    private func scheduleSwitcherLiveCaptureUpdate() {
        liveCaptureDebounceTask?.cancel()
        liveCaptureDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(40))
            guard !Task.isCancelled, let self else { return }
            self.updateSwitcherLiveStreams()
        }
    }

    private func updateSwitcherLiveStreams() {
        guard hubSettings.advanced.enableLivePreviewForSwitcher else {
            DockPreviewLiveCaptureManager.shared.stopAll()
            return
        }
        let ids = DockPreviewLiveCaptureScope.windowIDs(
            windows: state.windows,
            selectedIndex: state.selectedIndex,
            scope: hubSettings.advanced.switcherLivePreviewScope
        )
        DockPreviewLiveCaptureManager.shared.setActiveWindowIDs(
            ids,
            hub: hubSettings,
            context: .windowSwitcher,
            enabled: true
        )
    }

    private func configureSwitcherSearch() {
        guard hubSettings.switcher.enableSearch,
              let window = panel.underlyingWindow
        else {
            searchWindow.hide()
            return
        }
        searchWindow.show(relativeTo: window)
        if hubSettings.switcher.focusSearchOnOpen {
            searchWindow.focus()
        }
    }

    func focusSearchWindow() {
        searchWindow.focus()
    }

    func updateSearchWindow(text: String) {
        searchWindow.updateText(text)
    }

    func hideSearchWindow() {
        searchWindow.hide()
    }

    func showCmdTab(
        appName: String,
        appIcon: NSImage?,
        entries: [DockPreviewWindowEntry],
        anchorRect: CGRect,
        selectedIndex: Int = 0,
        showFocusHint: Bool = false
    ) {
        Self.active = self
        state.mode = .cmdTab
        state.showCmdTabFocusHint = showFocusHint
        state.appearance = DockPreviewAppearanceContext.resolve(
            mode: .cmdTab,
            settings: hubSettings.previews,
            hubAppearance: hubSettings.appearance
        )
        state.embeddedContent = .none
        state.appName = appName
        state.appIcon = appIcon
        state.anchorRect = anchorRect
        state.dockEdge = .bottom
        panel.setCenterOnScreen(false)
        _ = state.setWindows(entries, preserveSelection: false)
        state.selectedIndex = selectedIndex
        refreshPanelLayout(reposition: true, placementKey: 0)
    }

    func dismiss(animated: Bool = true) {
        hideSearchWindow()
        DockDragPreviewCoordinator.shared.endDragging()
        panel.dismiss(animated: animated)
        if Self.active === self { Self.active = nil }
    }

    func beginFadeOut(duration: TimeInterval, completion: @escaping () -> Void) {
        panel.beginFadeOut(duration: duration, completion: completion)
    }

    func resetFadeState() {
        panel.resetFadeState()
    }

    var panelFrame: CGRect { panel.panelFrame }

    var isVisible: Bool { panel.isVisible }

    func present(
        presentation: DockPreviewPanelPresentation,
        placementKey: UInt,
        reposition: Bool,
        onSelect: @escaping (DockPreviewWindowEntry) -> Void
    ) {
        state.embeddedContent = presentation.embeddedContent
        panel.update(
            presentation: presentation,
            placementKey: placementKey,
            reposition: reposition,
            onSelect: onSelect
        )
    }

    private func refreshPanelLayout(reposition: Bool, placementKey: UInt = 0) {
        var previews = hubSettings.previews
        if hubSettings.advanced.disableImagePreview {
            previews.showThumbnails = false
        }
        let mode = DockPreviewPermissionGate.currentMode(settings: previews, hub: hubSettings)
        let liveEnabled: Bool
        if state.mode == .windowSwitcher {
            liveEnabled = hubSettings.advanced.enableLivePreviewForSwitcher && hubSettings.master.enableDockPreviews
        } else if state.mode == .cmdTab {
            liveEnabled = hubSettings.advanced.enableLivePreviewForDock && hubSettings.master.enableDockPreviews
        } else {
            liveEnabled = previews.enableLivePreview && hubSettings.master.enableDockPreviews
        }
        let presentation = DockPreviewPanelPresentation(
            appIcon: state.appIcon,
            appName: state.appName,
            entries: state.windows,
            mode: mode,
            anchorRect: state.anchorRect,
            dockEdge: state.dockEdge,
            enableLivePreview: liveEnabled,
            embeddedContent: state.embeddedContent
        )
        panel.update(
            presentation: presentation,
            placementKey: placementKey,
            reposition: reposition,
            onSelect: { [weak self] entry in
                Task { await self?.handleSelect(entry) }
            }
        )
        if state.mode == .windowSwitcher,
           hubSettings.switcher.enableSearch,
           let window = panel.underlyingWindow,
           !isVisible || reposition
        {
            searchWindow.show(relativeTo: window)
        }
    }

    private func handleSelect(_ entry: DockPreviewWindowEntry) async {
        await raiseService.raise(entry: entry, settings: hubSettings.previews)
        if state.mode == .windowSwitcher || state.mode == .cmdTab {
            dismiss(animated: true)
        }
    }

}

extension Notification.Name {
    static let dockPreviewResetFadeState = Notification.Name("dockPreviewResetFadeState")
}
