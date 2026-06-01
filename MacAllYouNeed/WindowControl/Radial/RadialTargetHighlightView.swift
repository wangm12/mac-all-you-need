import Core
import SwiftUI

/// Glowing border outlining the window that will be moved.
struct RadialTargetHighlightView: View {
    let color: Color
    var cornerRadius: CGFloat = WindowSnapOverlayPresentation.standardCornerRadius

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(color, lineWidth: 2.5)
            .shadow(color: color.opacity(0.85), radius: 10, x: 0, y: 0)
            .shadow(color: color.opacity(0.45), radius: 20, x: 0, y: 0)
    }
}
