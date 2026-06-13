import AppKit
import SwiftUI
import UI

@MainActor
struct DockPreviewPanelPresentation: Equatable {
    var appIcon: NSImage?
    var appName: String
    var entries: [DockPreviewWindowEntry]
    var mode: DockPreviewPermissionGate.Mode
    var anchorRect: CGRect
    var dockEdge: DockPreviewPanelGeometry.DockEdge
    var enableLivePreview: Bool
    var embeddedContent: DockEmbeddedContent = .none
}

/// Floating dock preview panel (DockDoor `SharedPreviewWindowCoordinator` subset).
@MainActor
final class DockPreviewPanel {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<DockPreviewHoverContainer>?
    private weak var stateCoordinator: DockPreviewStateCoordinator?

    private var pinnedPlacementKey: UInt?
    private var hasPerformedInitialShow = false
    private var bufferFromDock: CGFloat = CGFloat(DockPreviewSettings.default.bufferFromDock)
    private var centerOnScreen = false

    var mouseIsWithinPreview = false
    var isFadingOut = false
    var onSelect: ((DockPreviewWindowEntry) -> Void)?
    var onDismissRequest: (() -> Void)?
    var onDismissPreservePendingShow: (() -> Void)?

    func bind(state: DockPreviewStateCoordinator) {
        stateCoordinator = state
        state.onFrameRefreshNeeded = { [weak self] in
            self?.relayoutFromState(reposition: false, animated: true, isSizeChange: true)
        }
    }

    func update(
        presentation: DockPreviewPanelPresentation,
        placementKey: UInt,
        reposition: Bool,
        onSelect: @escaping (DockPreviewWindowEntry) -> Void
    ) {
        self.onSelect = onSelect
        let hub = DockHubSettingsStore.load()
        let settings = hub.previews
        bufferFromDock = CGFloat(settings.bufferFromDock)

        guard let state = stateCoordinator else { return }
        state.appName = presentation.appName
        state.appIcon = presentation.appIcon
        state.anchorRect = presentation.anchorRect
        state.dockEdge = presentation.dockEdge
        state.settings = settings
        state.appearance = DockPreviewAppearanceContext.resolve(
            mode: state.mode,
            settings: settings,
            hubAppearance: hub.appearance
        )
        state.presentationMode = presentation.mode
        state.enableLivePreview = presentation.enableLivePreview
        state.embeddedContent = presentation.embeddedContent

        let switchingIcon = placementKey != pinnedPlacementKey
        state.dockItemToken = placementKey
        let mergeOnly = panel?.isVisible == true && !switchingIcon && hasPerformedInitialShow
        if switchingIcon || !hasPerformedInitialShow {
            _ = state.setWindows(presentation.entries, preserveSelection: !switchingIcon)
        } else {
            _ = state.mergeWindows(presentation.entries)
        }

        ensurePanel()
        let firstShow = !hasPerformedInitialShow
        let shouldReposition = (reposition || switchingIcon) && !mergeOnly
        relayoutFromState(
            reposition: shouldReposition,
            animated: settings.showPreviewAnimations && (firstShow || switchingIcon),
            isSizeChange: mergeOnly,
            isFirstShow: firstShow
        )

        if switchingIcon || pinnedPlacementKey == nil {
            pinnedPlacementKey = placementKey
        }
        if switchingIcon, panel?.isVisible == true {
            panel?.alphaValue = 1
            NotificationCenter.default.post(name: .dockPreviewResetFadeState, object: nil)
        }
        hasPerformedInitialShow = true

        if presentation.enableLivePreview, presentation.mode == .fullPreview {
            let context: DockPreviewLiveCaptureContext = state.mode == .windowSwitcher
                ? .windowSwitcher
                : .dockHover
            let ids: [CGWindowID]
            if state.mode == .windowSwitcher {
                ids = DockPreviewLiveCaptureScope.windowIDs(
                    windows: state.windows,
                    selectedIndex: state.selectedIndex,
                    scope: hub.advanced.switcherLivePreviewScope
                )
            } else {
                ids = state.windows.filter { !$0.title.isEmpty }.map(\.id)
            }
            DockPreviewLiveCaptureManager.shared.setActiveWindowIDs(
                ids,
                hub: hub,
                context: context,
                enabled: true
            )
        } else {
            DockPreviewLiveCaptureManager.shared.stopAll()
        }
    }

    func setCenterOnScreen(_ center: Bool) {
        centerOnScreen = center
    }

    private func ensurePanel() {
        if panel != nil { return }
        guard let state = stateCoordinator else { return }
        rebuildHostingView(state: state)
        let newPanel = NSPanel(
            contentRect: NSRect(origin: .zero, size: CGSize(width: 320, height: 200)),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        newPanel.level = DockPreviewWindowLayering.windowLevel
        newPanel.collectionBehavior = DockPreviewWindowLayering.collectionBehavior
        newPanel.hasShadow = false
        newPanel.backgroundColor = .clear
        newPanel.isFloatingPanel = true
        newPanel.worksWhenModal = true
        newPanel.isReleasedWhenClosed = false
        newPanel.animationBehavior = .none
        newPanel.becomesKeyOnlyIfNeeded = true
        newPanel.contentView = hostingView
        panel = newPanel
    }

    private func rebuildHostingView(state: DockPreviewStateCoordinator) {
        let root = DockPreviewHoverContainer(
            state: state,
            onSelect: { [weak self] entry in self?.onSelect?(entry) },
            onMouseInPanel: { [weak self] inside in self?.mouseIsWithinPreview = inside },
            onDismissRequest: { [weak self] in self?.onDismissRequest?() },
            onDismissPreservePendingShow: { [weak self] in
                self?.onDismissPreservePendingShow?()
            },
            onMinimizeAll: { [weak self] in self?.minimizeAllWindows() },
            onCloseAll: { [weak self] in self?.closeAllWindows() },
            onQuitApp: { [weak self] in self?.quitHoveredApp() }
        )
        if let hostingView {
            hostingView.rootView = root
        } else {
            hostingView = NSHostingView(rootView: root)
        }
    }

    private func relayoutFromState(
        reposition: Bool,
        animated: Bool,
        isSizeChange: Bool,
        isFirstShow: Bool = false
    ) {
        guard let panel, let hostingView, let state = stateCoordinator else { return }

        // Dimensions must be computed from settings card size before measuring the panel (DockDoor order).
        state.recomputeAndPublishDimensions()

        var input = DockPreviewPanelLayoutEngine.LayoutInput(
            anchorRect: state.anchorRect,
            anchoredIconRect: state.settings.anchorToDockIcon ? state.anchorRect : nil,
            dockEdge: state.dockEdge,
            bufferFromDock: bufferFromDock,
            expectedContentSize: state.expectedContentSize,
            showAnimations: animated && state.settings.showPreviewAnimations,
            centerOnScreen: centerOnScreen,
            isCmdTab: state.mode == .cmdTab
        )

        let previous = panel.frame
        var result = DockPreviewPanelLayoutEngine.measureAndLayout(
            panel: panel,
            hostingView: hostingView,
            input: input,
            previousFrame: previous
        )

        if state.expectedContentSize != input.expectedContentSize {
            input.expectedContentSize = state.expectedContentSize
            result = DockPreviewPanelLayoutEngine.measureAndLayout(
                panel: panel,
                hostingView: hostingView,
                input: input,
                previousFrame: previous
            )
        }

        let target: CGRect
        if isSizeChange, panel.isVisible, !isFirstShow,
           let screen = DockPreviewDockCoordinates.screen(containingAXPoint: state.anchorRect.origin)
        {
            target = DockPreviewPanelLayoutEngine.resizedFrameKeepingAnchor(
                currentFrame: previous,
                newSize: result.frame.size,
                dockEdge: state.dockEdge,
                screen: screen
            )
        } else {
            target = result.frame
        }

        let animate = animated && state.settings.showPreviewAnimations
            && MAYNMotionBridge.effectiveDuration(.hover) > 0

        if !panel.isVisible {
            DockPreviewPanelLayoutEngine.applyFrame(
                panel: panel,
                target: target,
                dockEdge: state.dockEdge,
                animated: animate,
                isFirstShow: true
            )
            DockPreviewWindowLayering.orderFront(panel)
        } else {
            DockPreviewPanelLayoutEngine.applyFrame(
                panel: panel,
                target: target,
                dockEdge: state.dockEdge,
                animated: animate && (reposition || isSizeChange),
                isFirstShow: false
            )
        }
        panel.ignoresMouseEvents = false
        panel.hidesOnDeactivate = false
    }

    private func minimizeAllWindows() {
        guard let state = stateCoordinator else { return }
        for entry in state.windows {
            DockPreviewWindowActions.minimize(entry: entry)
        }
    }

    private func closeAllWindows() {
        guard let state = stateCoordinator else { return }
        for entry in state.windows {
            DockPreviewWindowActions.close(entry: entry)
        }
    }

    private func quitHoveredApp() {
        guard let state = stateCoordinator else { return }
        let pid = state.windows.first?.pid ?? 0
        DockPreviewWindowActions.quitApplication(pid: pid)
        dismiss(animated: true)
        onDismissRequest?()
    }

    func beginFadeOut(duration: TimeInterval, completion: @escaping () -> Void) {
        guard let panel else {
            completion()
            return
        }
        isFadingOut = true
        if duration <= 0 {
            panel.alphaValue = 0
            completion()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            panel.animator().alphaValue = 0
        } completionHandler: {
            completion()
        }
    }

    func resetFadeState() {
        isFadingOut = false
        panel?.alphaValue = 1
        NotificationCenter.default.post(name: .dockPreviewResetFadeState, object: nil)
    }

    func clearMouseInPreview() {
        mouseIsWithinPreview = false
    }

    /// Hides the panel when sliding to another dock icon without tearing down the host view or LRU thumbnails.
    func hideForDockIconTransition() {
        mouseIsWithinPreview = false
        isFadingOut = false
        pinnedPlacementKey = nil
        panel?.alphaValue = 1
        panel?.orderOut(nil)
    }

    func dismiss(animated: Bool = true) {
        mouseIsWithinPreview = false
        isFadingOut = false
        pinnedPlacementKey = nil
        hasPerformedInitialShow = false
        centerOnScreen = false
        if animated, let panel, panel.isVisible {
            let duration = MAYNMotionBridge.effectiveDuration(.toastOut)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                panel.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                self?.tearDown()
            }
        } else {
            tearDown()
        }
    }

    var isVisible: Bool { panel?.isVisible == true }

    var panelFrame: CGRect { panel?.frame ?? .zero }

    var underlyingWindow: NSWindow? { panel }

    private func tearDown() {
        DockPreviewFullSizeOverlay.shared.dismiss()
        stateCoordinator?.dismissalAnchorDockItem = nil
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
    }
}
