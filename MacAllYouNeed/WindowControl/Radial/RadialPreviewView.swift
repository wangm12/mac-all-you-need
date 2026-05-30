import SwiftUI

/// Screen-sized translucent highlight of the window's proposed destination.
/// `frame` and `screenFrame` are in AppKit (bottom-left origin) coordinates.
struct RadialPreviewView: View {
    let frame: CGRect
    let screenFrame: CGRect

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            RoundedRectangle(cornerRadius: MAYNControlMetrics.cardRadius, style: .continuous)
                .fill(MAYNTheme.focusRing.opacity(0.22))
                .overlay(
                    RoundedRectangle(cornerRadius: MAYNControlMetrics.cardRadius, style: .continuous)
                        .strokeBorder(MAYNTheme.focusRing.opacity(0.6), lineWidth: 2)
                )
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX - screenFrame.minX, y: screenFrame.maxY - frame.maxY)
        }
    }
}
