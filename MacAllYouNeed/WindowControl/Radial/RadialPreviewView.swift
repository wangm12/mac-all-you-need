import SwiftUI

/// Screen-sized overlay showing the proposed destination frame (snap overlay style).
struct RadialPreviewView: View {
    let frame: CGRect
    let screenFrame: CGRect

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            WindowLayoutPreviewRectView(
                cornerRadius: WindowSnapOverlayPresentation.cornerRadius(
                    for: CGSize(width: frame.width, height: frame.height)
                )
            )
            .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX - screenFrame.minX, y: screenFrame.maxY - frame.maxY)
        }
    }
}
