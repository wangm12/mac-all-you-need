import SwiftUI

/// Frosted pill for titles and traffic lights (DockDoor `MaterialPill`).
struct DockPreviewMaterialPillModifier: ViewModifier {
    let background: DockPreviewResolvedBackgroundAppearance

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background {
                DockPreviewBlurView(cornerRadius: 999, appearance: background)
            }
            .clipShape(Capsule(style: .continuous))
            .dockPreviewBorderedBackground(
                Color.primary.opacity(0.1),
                lineWidth: 1.5,
                shape: Capsule(style: .continuous)
            )
    }
}

extension View {
    func dockPreviewMaterialPill(background: DockPreviewResolvedBackgroundAppearance) -> some View {
        modifier(DockPreviewMaterialPillModifier(background: background))
    }
}
