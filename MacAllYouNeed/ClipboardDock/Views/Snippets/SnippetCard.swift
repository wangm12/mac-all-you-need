import AppKit
import Core
import SwiftUI

struct SnippetCard: View {
    let snippet: Snippet
    let isFocused: Bool
    let onPaste: (Bool) -> Void
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    private var cardBackground: Color {
        Color(NSColor.controlBackgroundColor)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(snippet.name)
                    .font(.callout)
                    .bold()
                    .lineLimit(1)
                Spacer()
                if let trigger = snippet.trigger {
                    Text(trigger)
                        .font(.caption2.monospaced())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                }
            }

            Text(snippet.body)
                .font(.system(.callout, design: .monospaced))
                .lineLimit(6)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .frame(width: 220, height: 240, alignment: .topLeading)
        .padding(10)
        .background(cardBackground)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isFocused ? Color.accentColor : .clear, lineWidth: 2)
        )
        .onTapGesture {
            onPaste(NSEvent.modifierFlags.contains(.option))
        }
        .contextMenu {
            Button("Edit…", action: onEdit)
            Button("Duplicate", action: onDuplicate)
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        }
    }
}
