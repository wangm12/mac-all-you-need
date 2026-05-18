import AppKit
import Core
import SwiftUI

enum SnippetCardPresentation {
    static let width: CGFloat = DockCardShellPresentation.width
    static let height: CGFloat = DockCardShellPresentation.height
    static let cornerRadius: CGFloat = DockCardShellPresentation.cornerRadius
    static let contentPadding: CGFloat = 10
    static let focusedBorderWidth: CGFloat = DockCardShellPresentation.focusedBorderWidth
    static let unfocusedBorderWidth: CGFloat = 1
    static let usesClipboardCardBackground = true
    static let usesPersistentUnfocusedBorder = true
}

struct SnippetCard: View {
    let snippet: Snippet
    let isFocused: Bool
    let onPaste: (Bool) -> Void
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

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
        .padding(SnippetCardPresentation.contentPadding)
        .modifier(SnippetCardShell(isFocused: isFocused, alignment: .topLeading))
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

struct SnippetCardShell: ViewModifier {
    let isFocused: Bool
    let alignment: Alignment

    private var cardBackground: Color {
        Color(NSColor.controlBackgroundColor)
    }

    private var borderColor: Color {
        isFocused ? MAYNTheme.focusRing : MAYNTheme.subtleBorder
    }

    private var borderWidth: CGFloat {
        isFocused ? SnippetCardPresentation.focusedBorderWidth : SnippetCardPresentation.unfocusedBorderWidth
    }

    func body(content: Content) -> some View {
        content
            .frame(
                width: SnippetCardPresentation.width,
                height: SnippetCardPresentation.height,
                alignment: alignment
            )
            .background(
                cardBackground,
                in: RoundedRectangle(cornerRadius: SnippetCardPresentation.cornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SnippetCardPresentation.cornerRadius, style: .continuous)
                    .stroke(borderColor, lineWidth: borderWidth)
            )
            .contentShape(
                RoundedRectangle(cornerRadius: SnippetCardPresentation.cornerRadius, style: .continuous)
            )
    }
}
