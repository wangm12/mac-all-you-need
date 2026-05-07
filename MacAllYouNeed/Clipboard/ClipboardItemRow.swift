import Core
import Platform
import SwiftUI

struct ClipboardItemRow: View {
    let item: ClipboardXPCMeta
    let isSelected: Bool
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(alignment: .leading, spacing: 4) {
                PasteboardPreview(text: item.preview)
                Spacer(minLength: 0)
                Text(item.modified, style: .relative).font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(8)
            .frame(width: 220, height: 180, alignment: .topLeading)
            .background(isSelected ? Color.accentColor.opacity(0.18) : Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2))

            if let videoURL = URLDetector.videoBearingURL(in: item.preview) {
                Button {
                    NotificationCenter.default.post(name: .clipboardDownloadRequested, object: videoURL)
                } label: {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.white, Color.accentColor)
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .padding(6)
            }
        }
    }
}
