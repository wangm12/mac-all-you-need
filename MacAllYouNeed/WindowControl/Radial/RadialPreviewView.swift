import SwiftUI

/// Screen-sized overlay showing the proposed destination frame (focus-colored puck style).
struct RadialPreviewView: View {
    let frame: CGRect
    let screenFrame: CGRect
    let fullScreenBlend: CGFloat
    let previewOpacity: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            RadialPuckPreviewRectView(
                cornerRadius: cornerRadius,
                fullScreenBlend: fullScreenBlend,
                previewOpacity: previewOpacity
            )
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX - screenFrame.minX, y: screenFrame.maxY - frame.maxY)
        }
    }
}
