import AppKit
import SwiftUI

struct CardSlot: View {
    let item: DockItem
    let index: Int
    let isFocused: Bool
    let imageLoader: ImageBlobLoader
    let fileLoader: FileURLLoader
    let favicons: FaviconCache

    private var cardBackground: Color {
        Color(NSColor.controlBackgroundColor)
    }

    var body: some View {
        ClipCard(
            item: item,
            imageLoader: imageLoader,
            fileLoader: fileLoader,
            favicons: favicons,
            cardBackground: cardBackground
        )
        .frame(width: 220, height: 240)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isFocused ? Color.accentColor : .clear, lineWidth: 2)
        )
        .overlay(alignment: .bottomLeading) {
            if index < 9 {
                Text("⌘\(index + 1)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .padding(6)
            }
        }
    }
}
