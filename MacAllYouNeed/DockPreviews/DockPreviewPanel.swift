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
}

@MainActor
final class DockPreviewPanel {
    private var panelController: NonActivatingFloatingPanelController<DockPreviewPanelHostView>?
    private var pinnedOrigin: CGPoint?
    private var pinnedPlacementKey: UInt?
    private var bufferFromDock: CGFloat = CGFloat(DockPreviewSettings.default.bufferFromDock)

    var mouseIsWithinPreview = false
    var onSelect: ((DockPreviewWindowEntry) -> Void)?

    func update(
        presentation: DockPreviewPanelPresentation,
        placementKey: UInt,
        reposition: Bool,
        onSelect: @escaping (DockPreviewWindowEntry) -> Void
    ) {
        self.onSelect = onSelect
        bufferFromDock = CGFloat(DockPreviewSettingsStore.load().bufferFromDock)
        let size = panelSize(for: presentation.entries.count)
        let firstPresent = panelController?.isPresented != true
        let switchingIcon = placementKey != pinnedPlacementKey
        let needsInitialPin = firstPresent || pinnedOrigin == nil
        let needsPlacementUpdate = needsInitialPin || (reposition && switchingIcon)

        if needsPlacementUpdate {
            pinnedOrigin = panelOrigin(presentation: presentation, panelSize: size)
            pinnedPlacementKey = placementKey
        }

        let host = DockPreviewPanelHostView(
            presentation: presentation,
            onSelect: { [weak self] entry in self?.onSelect?(entry) },
            onMouseInPanel: { [weak self] inside in self?.mouseIsWithinPreview = inside }
        )

        if panelController == nil {
            panelController = NonActivatingFloatingPanelController(
                styleMask: [.borderless, .nonactivatingPanel],
                level: DockPreviewWindowLayering.windowLevel,
                collectionBehavior: DockPreviewWindowLayering.collectionBehavior,
                hasShadow: false,
                showAnimationDuration: MAYNMotionBridge.effectiveDuration(.toastIn),
                hideAnimationDuration: MAYNMotionBridge.effectiveDuration(.toastOut)
            )
        }

        if firstPresent {
            panelController?.present(rootView: host, size: size, animated: true)
        } else {
            panelController?.update(rootView: host)
            if let panel = panelController?.currentPanel,
               panel.frame.size != size {
                panel.setContentSize(size)
            }
        }

        if let panel = panelController?.currentPanel, let origin = pinnedOrigin {
            if needsPlacementUpdate {
                panel.setFrameOrigin(NSPoint(x: origin.x, y: origin.y))
            }
            panel.ignoresMouseEvents = false
            panel.hidesOnDeactivate = false
            DockPreviewWindowLayering.orderFront(panel)
        }
    }

    func dismiss(animated: Bool = true) {
        mouseIsWithinPreview = false
        pinnedOrigin = nil
        pinnedPlacementKey = nil
        panelController?.dismiss(animated: animated)
    }

    var isVisible: Bool { panelController?.isPresented == true }

    var panelFrame: CGRect { panelController?.currentPanel?.frame ?? .zero }

    private func panelSize(for entryCount: Int) -> CGSize {
        let cardCount = max(1, min(entryCount, 6))
        let cardW = DockPreviewLayout.cardWidth
        let panelWidth = CGFloat(cardCount) * (cardW + DockPreviewLayout.itemSpacing)
            - DockPreviewLayout.itemSpacing
            + DockPreviewLayout.outerPadding * 2
        return CGSize(width: panelWidth, height: DockPreviewLayout.panelHeight)
    }

    private func panelOrigin(presentation: DockPreviewPanelPresentation, panelSize: CGSize) -> CGPoint {
        guard presentation.anchorRect != .zero else {
            let mouse = NSEvent.mouseLocation
            return CGPoint(x: mouse.x - panelSize.width / 2, y: mouse.y + 24)
        }
        let screen = DockPreviewDockCoordinates.screen(containingAXPoint: presentation.anchorRect.origin)
        return DockPreviewPanelGeometry.panelOrigin(
            axIconRect: presentation.anchorRect,
            panelSize: panelSize,
            screen: screen,
            dockEdge: presentation.dockEdge,
            bufferFromDock: bufferFromDock
        )
    }
}

private struct DockPreviewPanelHostView: View {
    let presentation: DockPreviewPanelPresentation
    let onSelect: (DockPreviewWindowEntry) -> Void
    let onMouseInPanel: (Bool) -> Void

    var body: some View {
        DockPreviewPanelView(
            appIcon: presentation.appIcon,
            appName: presentation.appName,
            entries: presentation.entries,
            mode: presentation.mode,
            enableLivePreview: presentation.enableLivePreview,
            onSelect: onSelect
        )
        .onHover { onMouseInPanel($0) }
    }
}
