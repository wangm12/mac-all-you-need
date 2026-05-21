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
        SetupTaskPage(
            symbol: "mic.badge.plus",
            title: phrases[phraseIndex],
            subtitle: "Press a shortcut, speak naturally, and paste polished text into any Mac app."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Label("Local ASR keeps audio on this Mac by default.", systemImage: "lock")
                Label("Mixed Chinese and English dictation is supported.", systemImage: "globe")
                Label("Cleanup can be local or provider-based, depending on your settings.", systemImage: "text.bubble")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MAYNTheme.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
            )
            .id(phraseIndex)
            .transition(.opacity)
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
