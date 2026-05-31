import AppKit
import SwiftUI
import UI

@MainActor
final class DockPreviewFolderPanel {
    private var panelController: NonActivatingFloatingPanelController<DockPreviewFolderPanelView>?
    var mouseIsWithinPreview = false

    func show(
        title: String,
        url: URL,
        showHidden: Bool,
        anchorRect: CGRect,
        dockEdge: DockPreviewPanelGeometry.DockEdge
    ) {
        let items = folderEntries(url: url, showHidden: showHidden)
        let view = DockPreviewFolderPanelView(
            title: title,
            items: items,
            onMouseInPanel: { [weak self] inside in self?.mouseIsWithinPreview = inside }
        )
        let size = DockPreviewLayout.folderPanelSize
        let origin = panelOrigin(anchorRect: anchorRect, panelSize: size, dockEdge: dockEdge)

        if panelController == nil {
            panelController = NonActivatingFloatingPanelController(
                styleMask: [.borderless, .nonactivatingPanel],
                level: DockPreviewWindowLayering.windowLevel,
                collectionBehavior: DockPreviewWindowLayering.collectionBehavior,
                hasShadow: true,
                showAnimationDuration: MAYNMotionBridge.effectiveDuration(.toastIn),
                hideAnimationDuration: MAYNMotionBridge.effectiveDuration(.toastOut)
            ) { panel, panelSize in
                panel.setFrameOrigin(NSPoint(x: origin.x, y: origin.y))
                _ = panelSize
            }
        }
        panelController?.present(rootView: view, size: size, animated: true)
        panelController?.currentPanel?.ignoresMouseEvents = false
    }

    func dismiss() {
        mouseIsWithinPreview = false
        panelController?.dismiss(animated: true)
    }

    var isVisible: Bool { panelController?.isPresented == true }
    var panelFrame: CGRect { panelController?.currentPanel?.frame ?? .zero }

    private func folderEntries(url: URL, showHidden: Bool) -> [String] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey]
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: keys,
            options: showHidden ? [] : [.skipsHiddenFiles]
        ) else { return [] }
        return contents
            .map { FileManager.default.displayName(atPath: $0.path) }
            .sorted()
            .prefix(24)
            .map { String($0) }
    }

    private func panelOrigin(anchorRect: CGRect, panelSize: CGSize, dockEdge: DockPreviewPanelGeometry.DockEdge) -> CGPoint {
        let screen = DockPreviewDockCoordinates.screen(containingAXPoint: anchorRect.origin)
        let buffer = CGFloat(DockPreviewSettingsStore.load().bufferFromDock)
        return DockPreviewPanelGeometry.panelOrigin(
            axIconRect: anchorRect,
            panelSize: panelSize,
            screen: screen,
            dockEdge: dockEdge,
            bufferFromDock: buffer
        )
    }
}

struct DockPreviewFolderPanelView: View {
    let title: String
    let items: [String]
    let onMouseInPanel: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(items, id: \.self) { name in
                        Text(name)
                            .font(.subheadline)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial)
        .onHover { onMouseInPanel($0) }
    }
}
