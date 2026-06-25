import SwiftUI

/// Focus-colored destination preview for the Radial Puck HUD.
struct RadialPuckPreviewRectView: View {
    let cornerRadius: CGFloat
    let fullScreenBlend: CGFloat
    let previewOpacity: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(RadialPuckVisualTokens.focusPreviewFill.opacity(
                RadialPuckVisualTokens.previewFillOpacity(fullScreenBlend: fullScreenBlend) * previewOpacity
            ))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        RadialPuckVisualTokens.focusPreviewStroke.opacity(
                            RadialPuckVisualTokens.previewStrokeOpacity(fullScreenBlend: fullScreenBlend) * previewOpacity
                        ),
                        lineWidth: RadialPuckVisualTokens.previewStrokeWidth(fullScreenBlend: fullScreenBlend)
                    )
            }
            .shadow(
                color: RadialPuckVisualTokens.focusPreviewFill.opacity(
                    RadialPuckVisualTokens.previewShadowOpacity(previewOpacity: previewOpacity)
                ),
                radius: 22
            )
    }
}
