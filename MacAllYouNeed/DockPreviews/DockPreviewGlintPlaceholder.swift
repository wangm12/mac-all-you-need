import SwiftUI

/// Diagonal shimmer placeholder for window cards awaiting thumbnails (DockDoor `GlintPlaceholder` subset).
struct DockPreviewGlintPlaceholder: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.primary.opacity(0.06)
                if !reduceMotion {
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                        let cycle = 1.2
                        let phase = context.date.timeIntervalSinceReferenceDate
                            .truncatingRemainder(dividingBy: cycle) / cycle
                        LinearGradient(
                            colors: [
                                Color.clear,
                            Color.primary.opacity(0.10),
                            Color.white.opacity(0.28),
                            Color.primary.opacity(0.10),
                            Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .frame(width: proxy.size.width * 0.55)
                        .offset(x: (-1 + phase * 2) * proxy.size.width * 0.7)
                    }
                }
            }
        }
    }
}
