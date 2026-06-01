import SwiftUI

/// Per-card frame constraints (DockDoor `DynamicWindowFrameModifier`).
struct DockPreviewDynamicFrameModifier: ViewModifier {
    let allowDynamicSizing: Bool
    let dimensions: DockPreviewWindowDimensions
    let dockEdge: DockPreviewPanelGeometry.DockEdge
    let isWindowSwitcher: Bool

    func body(content: Content) -> some View {
        if allowDynamicSizing {
            let horizontal = isWindowSwitcher || dockEdge == .bottom
            if isWindowSwitcher {
                content
                    .frame(
                        width: dimensions.size.width > 0 ? dimensions.size.width : nil,
                        height: dimensions.size.height > 0 ? dimensions.size.height : nil,
                        alignment: .center
                    )
                    .frame(
                        maxWidth: dimensions.maxDimensions.width,
                        maxHeight: dimensions.maxDimensions.height
                    )
            } else if horizontal {
                content
                    .frame(height: dimensions.size.height > 0 ? dimensions.size.height : nil)
                    .scaledToFit()
                    .frame(
                        maxWidth: dimensions.maxDimensions.width,
                        maxHeight: dimensions.maxDimensions.height
                    )
            } else {
                content
                    .frame(width: dimensions.size.width > 0 ? dimensions.size.width : nil)
                    .scaledToFit()
                    .frame(
                        maxWidth: dimensions.maxDimensions.width,
                        maxHeight: dimensions.maxDimensions.height
                    )
            }
        } else {
            content
                .frame(
                    width: max(dimensions.size.width, 50),
                    height: dimensions.size.height,
                    alignment: .center
                )
                .frame(
                    maxWidth: dimensions.maxDimensions.width,
                    maxHeight: dimensions.maxDimensions.height
                )
        }
    }
}

extension View {
    func dockPreviewDynamicFrame(
        allowDynamicSizing: Bool,
        dimensions: DockPreviewWindowDimensions,
        dockEdge: DockPreviewPanelGeometry.DockEdge,
        isWindowSwitcher: Bool
    ) -> some View {
        modifier(DockPreviewDynamicFrameModifier(
            allowDynamicSizing: allowDynamicSizing,
            dimensions: dimensions,
            dockEdge: dockEdge,
            isWindowSwitcher: isWindowSwitcher
        ))
    }
}
