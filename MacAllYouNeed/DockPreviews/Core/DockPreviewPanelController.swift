import AppKit
import Foundation

/// Single floating panel for dock hover, switcher, and Cmd+Tab (DockDoor `SharedPreviewWindowCoordinator` subset).
@MainActor
final class DockPreviewPanelController {
    static weak var active: DockPreviewPanelController?

    let state = DockPreviewStateCoordinator()
    let panel = DockPreviewPanel()
    private let searchWindow = DockPreviewSearchWindow()
    private let raiseService: DockPreviewRaiseService
    private var hubSettings: DockHubSettings = .default

    var mouseIsWithinPreview: Bool { panel.mouseIsWithinPreview }

    init(enumerator: any WindowEnumerating = SystemWindowEnumerator()) {
        raiseService = DockPreviewRaiseService(enumerator: enumerator)
        panel.bind(state: state)
        searchWindow.bind(state: state)
        panel.onDismissRequest = { [weak self] in self?.requestDismiss() }
        panel.shouldKeepOpen = { [weak self] in self?.shouldKeepOpen() ?? false }
    }

    func reloadSettings(_ settings: DockHubSettings) {
        hubSettings = settings
        state.settings = settings.previews
        state.appearance = DockPreviewAppearanceContext.resolve(mode: state.mode, settings: settings.previews)
    }

    func showHover(
        pid: pid_t,
        appName: String,
        appIcon: NSImage?,
        entries: [DockPreviewWindowEntry],
        anchorRect: CGRect,
        placementKey: UInt,
        embedded: DockEmbeddedContent = .none
    ) {
        Self.active = self
        state.mode = .dockHover
        state.appearance = DockPreviewAppearanceContext.resolve(mode: .dockHover, settings: hubSettings.previews)
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
        state.appearance = DockPreviewAppearanceContext.resolve(mode: .windowSwitcher, settings: hubSettings.previews)
        state.embeddedContent = .none
        state.appName = "Windows"
        state.appIcon = nil
        state.anchorRect = NSScreen.screens.first.map { $0.visibleFrame } ?? .zero
        state.dockEdge = .bottom
        panel.setCenterOnScreen(true)
        state.windows = entries
        state.selectedIndex = selectedIndex
        if hubSettings.switcher.enableSearch && hubSettings.previews.detachedSwitcherSearch,
           let window = panel.underlyingWindow
        {
            searchWindow.show(relativeTo: window)
        }
        refreshPanelLayout(reposition: true, placementKey: 0)
    }

    func showCmdTab(
        appName: String,
        appIcon: NSImage?,
        entries: [DockPreviewWindowEntry],
        anchorRect: CGRect
    ) {
        Self.active = self
        state.mode = .cmdTab
        state.appearance = DockPreviewAppearanceContext.resolve(mode: .cmdTab, settings: hubSettings.previews)
        state.embeddedContent = .none
        state.appName = appName
        state.appIcon = appIcon
        state.anchorRect = anchorRect
        state.dockEdge = .bottom
        panel.setCenterOnScreen(false)
        _ = state.setWindows(entries, preserveSelection: false)
        refreshPanelLayout(reposition: true, placementKey: 0)
    }

    func dismiss(animated: Bool = true) {
        searchWindow.hide()
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
        let mode = DockPreviewPermissionGate.currentMode(settings: previews)
        let presentation = DockPreviewPanelPresentation(
            appIcon: state.appIcon,
            appName: state.appName,
            entries: state.windows,
            mode: mode,
            anchorRect: state.anchorRect,
            dockEdge: state.dockEdge,
            enableLivePreview: previews.enableLivePreview && hubSettings.master.enableDockPreviews,
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
    }

    private func handleSelect(_ entry: DockPreviewWindowEntry) async {
        await raiseService.raise(entry: entry, settings: hubSettings.previews)
        if state.mode == .windowSwitcher || state.mode == .cmdTab {
            dismiss(animated: true)
        }
    }

    private func requestDismiss() {
        NotificationCenter.default.post(name: .dockPreviewPanelDismissRequested, object: nil)
    }

    private func shouldKeepOpen() -> Bool {
        hubSettings.previews.preventDockAutoHideWhileOpen && isVisible
    }
}

extension Notification.Name {
    static let dockPreviewPanelDismissRequested = Notification.Name("dockPreviewPanelDismissRequested")
    static let dockPreviewPanelDismissPreservePendingShow = Notification.Name("dockPreviewPanelDismissPreservePendingShow")
}
