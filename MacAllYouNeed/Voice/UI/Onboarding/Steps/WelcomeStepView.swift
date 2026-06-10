import SwiftUI

struct VoiceWelcomeStepView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let phrases = [
        "Write emails 5x faster",
        "用中英文混合 dictate",
        "Translate as you speak",
        "Polish your writing automatically"
    ]
    @State private var phraseIndex = 0
    private let timer = Timer.publish(every: 2.1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text(phrases[phraseIndex])
                    .font(.system(size: 24, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .id(phraseIndex)
                    .transition(.opacity)
                Text("Press a shortcut, speak naturally, and paste polished text into any Mac app.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 8) {
                VoiceWelcomeHighlightRow(
                    symbol: "lock",
                    title: "Local ASR",
                    detail: "Audio stays on this Mac by default."
                )
                VoiceWelcomeHighlightRow(
                    symbol: "globe",
                    title: "Mixed languages",
                    detail: "Chinese and English dictation in one session."
                )
                VoiceWelcomeHighlightRow(
                    symbol: "text.bubble",
                    title: "Optional cleanup",
                    detail: "Polish transcripts locally or with a provider."
                )
            }
        }
        .onReceive(timer) { _ in
            if reduceMotion {
                phraseIndex = (phraseIndex + 1) % phrases.count
            } else {
                withAnimation(MAYNMotion.instructionAnimation(reduceMotion: reduceMotion)) {
                    phraseIndex = (phraseIndex + 1) % phrases.count
                }
            }
        }
    }
}

private struct VoiceWelcomeHighlightRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 28, height: 28)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(MAYNTheme.panel, in: RoundedRectangle(cornerRadius: MAYNControlMetrics.panelRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MAYNControlMetrics.panelRadius, style: .continuous)
                .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
        )
    }
}
