import SwiftUI

/// Animated stand-in for the clipboard dock when no bundled demo video is present.
struct ClipboardDockOnboardingPreview: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dockVisible = false
    @State private var focusedIndex = 0
    @State private var focusLoopTask: Task<Void, Never>?

    private static let cardScale: CGFloat = 0.38
    private var cardWidth: CGFloat { DockCardShellPresentation.width * Self.cardScale }
    private var cardHeight: CGFloat { DockCardShellPresentation.height * Self.cardScale }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.96), Color(white: 0.90)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                // Subtle desktop hint — no shortcut chip (lives in the Shortcut section).
                VStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                        .frame(width: proxy.size.width * 0.42, height: 8)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.primary.opacity(0.03))
                        .frame(width: proxy.size.width * 0.56, height: 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 20)
                .padding(.leading, 18)

                dockChrome
                    .frame(width: proxy.size.width - 24)
                    .offset(y: dockVisible ? 0 : 72)
                    .opacity(dockVisible ? 1 : 0)
                    .padding(.bottom, 10)
            }
        }
        .onAppear { startLoop() }
        .onDisappear {
            focusLoopTask?.cancel()
            focusLoopTask = nil
        }
    }

    private var dockChrome: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                dockTab("History", selected: true)
                dockTab("Snippets", selected: false)
                Spacer(minLength: 0)
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(MAYNTheme.elevated)

            Divider()

            HStack(alignment: .top, spacing: 8) {
                ForEach(Array(sampleCards.enumerated()), id: \.offset) { index, card in
                    MiniClipCardPreview(
                        title: card.title,
                        previewText: card.body,
                        footer: card.footer,
                        isFocused: index == focusedIndex
                    )
                    .frame(width: cardWidth, height: cardHeight)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(MAYNTheme.strongBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.10), radius: 10, y: 3)
    }

    private func dockTab(_ title: String, selected: Bool) -> some View {
        Text(title)
            .font(.system(size: 9, weight: selected ? .semibold : .regular))
            .foregroundStyle(selected ? .primary : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(selected ? MAYNTheme.selected : Color.clear, in: Capsule())
    }

    private var sampleCards: [(title: String, body: String, footer: String?)] {
        [
            ("Text", "Quarterly report draft…", nil),
            ("Link", "docs.example.com", nil),
            ("Text", "2 + 2", "= 4"),
        ]
    }

    private func startLoop() {
        guard !reduceMotion else {
            dockVisible = true
            focusedIndex = 0
            return
        }
        dockVisible = false
        focusedIndex = 0
        withAnimation(MAYNMotion.panelAnimation(reduceMotion: false)) {
            dockVisible = true
        }
        focusLoopTask?.cancel()
        focusLoopTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2.4))
                guard !Task.isCancelled else { return }
                withAnimation(MAYNMotion.controlAnimation(reduceMotion: false)) {
                    focusedIndex = (focusedIndex + 1) % sampleCards.count
                }
            }
        }
    }
}

private struct MiniClipCardPreview: View {
    let title: String
    let previewText: String
    let footer: String?
    let isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 8, weight: .semibold))
                    Text("now")
                        .font(.system(size: 7))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Circle()
                    .fill(Color.accentColor.opacity(0.25))
                    .frame(width: 10, height: 10)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(MAYNTheme.elevated)

            Text(previewText)
                .font(.system(size: 8))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(6)

            if let footer {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 7, weight: .semibold))
                    Text(footer)
                        .font(.system(size: 7, weight: .medium))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.white.opacity(0.92))
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.82))
            }
        }
        .background(MAYNTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(isFocused ? MAYNTheme.focusRing : MAYNTheme.subtleBorder, lineWidth: isFocused ? 1.5 : 0.5)
        )
    }
}
