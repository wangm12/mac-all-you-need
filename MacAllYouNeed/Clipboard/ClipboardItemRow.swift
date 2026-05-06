import Core
import SwiftUI

struct ClipboardItemRow: View {
    let item: ClipboardXPCMeta
    let isSelected: Bool
    var body: some View {
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
    }
}
