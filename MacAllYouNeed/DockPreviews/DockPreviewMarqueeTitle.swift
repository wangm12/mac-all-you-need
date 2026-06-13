import SwiftUI

/// Horizontally scrolling window title with fade edges when text overflows the card width.
struct DockPreviewMarqueeTitle: View {
    let title: String
    let font: Font
    let maxWidth: CGFloat
    let overflowStyle: DockPreviewTitleOverflowStyle
    let reduceMotion: Bool

    @State private var textWidth: CGFloat = 0
    @State private var scrollOffset: CGFloat = 0
    @State private var scrollTask: Task<Void, Never>?

    private var shouldMarquee: Bool {
        guard !reduceMotion else { return false }
        guard textWidth > maxWidth + 1 else { return false }
        switch overflowStyle {
        case .truncateTail:
            return true
        case .truncateMiddle, .truncateHead:
            return false
        }
    }

    var body: some View {
        Group {
            if shouldMarquee {
                marqueeContent
            } else {
                staticContent
            }
        }
        .background {
            Text(title)
                .font(font)
                .lineLimit(1)
                .fixedSize()
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: TitleWidthKey.self, value: proxy.size.width)
                    }
                )
                .hidden()
        }
        .onPreferenceChange(TitleWidthKey.self) { textWidth = $0 }
        .onChange(of: title) { _, _ in
            resetScroll()
        }
        .onDisappear {
            scrollTask?.cancel()
            scrollTask = nil
        }
    }

    private var staticContent: some View {
        Text(title)
            .font(font)
            .lineLimit(1)
            .truncationMode(truncationMode)
            .frame(maxWidth: maxWidth, alignment: .leading)
    }

    private var marqueeContent: some View {
        Text(title)
            .font(font)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .offset(x: scrollOffset)
            .frame(width: maxWidth, alignment: .leading)
            .clipped()
            .dockPreviewScrollFade(axis: .horizontal, fadeLength: 10)
            .onAppear { startScrollIfNeeded() }
            .onChange(of: textWidth) { _, _ in startScrollIfNeeded() }
    }

    private var truncationMode: Text.TruncationMode {
        switch overflowStyle {
        case .truncateTail: .tail
        case .truncateMiddle: .middle
        case .truncateHead: .head
        }
    }

    private func resetScroll() {
        scrollTask?.cancel()
        scrollTask = nil
        scrollOffset = 0
    }

    private func startScrollIfNeeded() {
        scrollTask?.cancel()
        guard shouldMarquee else {
            scrollOffset = 0
            return
        }
        let overflow = max(0, textWidth - maxWidth)
        guard overflow > 0 else { return }
        scrollOffset = 0
        scrollTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, shouldMarquee else { return }
            let duration = max(MAYNMotionBridge.effectiveDuration(.control), Double(overflow / 15))
            withAnimation(MAYNMotion.normalAnimation(reduceMotion: false)) {
                scrollOffset = -overflow
            }
            try? await Task.sleep(for: .seconds(duration + 1.5))
            guard !Task.isCancelled else { return }
            withAnimation(MAYNMotion.hoverAnimation(reduceMotion: false)) {
                scrollOffset = 0
            }
        }
    }
}

private struct TitleWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
