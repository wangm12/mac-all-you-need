import SwiftUI

/// Scroll edge fade (DockDoor `fadeOnEdges` subset).
struct DockPreviewScrollFadeModifier: ViewModifier {
    let axis: Axis
    let fadeLength: CGFloat
    var disableLeading: Bool = false

    func body(content: Content) -> some View {
        content.mask {
            GeometryReader { proxy in
                let size = proxy.size
                if axis == .horizontal {
                    HStack(spacing: 0) {
                        if !disableLeading {
                            LinearGradient(
                                colors: [.clear, .black],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: fadeLength)
                        }
                        Rectangle().fill(.black)
                        LinearGradient(
                            colors: [.black, .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: fadeLength)
                    }
                    .frame(width: size.width, height: size.height)
                } else {
                    VStack(spacing: 0) {
                        if !disableLeading {
                            LinearGradient(
                                colors: [.clear, .black],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: fadeLength)
                        }
                        Rectangle().fill(.black)
                        LinearGradient(
                            colors: [.black, .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: fadeLength)
                    }
                    .frame(width: size.width, height: size.height)
                }
            }
        }
    }
}

extension View {
    func dockPreviewScrollFade(
        axis: Axis,
        fadeLength: CGFloat = 20,
        disableLeading: Bool = false
    ) -> some View {
        modifier(DockPreviewScrollFadeModifier(
            axis: axis,
            fadeLength: fadeLength,
            disableLeading: disableLeading
        ))
    }
}
