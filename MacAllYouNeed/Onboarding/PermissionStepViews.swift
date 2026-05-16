import SwiftUI

struct WelcomeStep: View {
    let next: () -> Void
    var body: some View {
        SetupTaskPage(
            symbol: "sparkles",
            title: "Welcome to Mac All You Need",
            subtitle: "Your Mac, with everything you need — clipboard search, folder previews, video downloads, and voice dictation. All opt-in."
        ) {
            VStack(alignment: .leading, spacing: 10) {
                setupItem("Universal clipboard with search and snippets", "doc.on.clipboard")
                setupItem("Quick Look folders and archives", "folder")
                setupItem("Video downloads with queue and progress", "arrow.down.circle")
                setupItem("Voice dictation — cloud or local, private", "mic")
            }
        }
    }

    private func setupItem(_ title: String, _ symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.callout)
            .foregroundStyle(.primary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MAYNTheme.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
            )
    }
}
