import SwiftUI

struct VoiceTranscriptRowMenu: View {
    let hasAudio: Bool
    let onRetry: () -> Void
    let onDownload: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Menu {
            if hasAudio {
                Button(action: onRetry) {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                Button(action: onDownload) {
                    Label("Download audio", systemImage: "arrow.down.circle")
                }
                Divider()
            }
            Button(role: .destructive, action: onDelete) {
                Label("Delete transcript", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 22, height: 22)
    }
}
