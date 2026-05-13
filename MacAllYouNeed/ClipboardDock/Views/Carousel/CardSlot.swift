import AppKit
import SwiftUI

struct CardSlot: View {
    let item: DockItem
    let index: Int
    let isFocused: Bool
    let imageLoader: ImageBlobLoader
    let fileLoader: FileURLLoader
    let fileThumbnailLoader: FileThumbnailLoader
    let favicons: FaviconCache
    /// Shared with sibling slots via ClipCarousel's @State so each slot's
    /// drop target knows whether the in-flight drag is a card-reorder.
    @Binding var draggedCardID: String?
    @Environment(ClipboardDockModel.self) private var model
    @State private var showingRename = false
    @State private var isCardDropTarget = false

    private var cardBackground: Color {
        Color(NSColor.controlBackgroundColor)
    }

    /// Show a neutral focus border when the card is in the selection set OR is
    /// the focused (keyboard arrow) target with no explicit selection. With
    /// `selectOnly` semantics, single-clicking a card both focuses it AND
    /// makes it the only selection — both signals collapse to the same
    /// border, which mirrors the Paste-style multi-select look.
    private var isHighlighted: Bool {
        if model.selection.contains(item.id) { return true }
        if model.selection.isEmpty, isFocused { return true }
        return false
    }

    var body: some View {
        ClipCard(
            item: item,
            imageLoader: imageLoader,
            fileLoader: fileLoader,
            fileThumbnailLoader: fileThumbnailLoader,
            favicons: favicons,
            cardBackground: cardBackground
        )
        .frame(width: 220, height: 240)
        // Selection border. Any selected card gets the neutral stroke — single
        // or multi-select look identical, matching Paste-style UX. Focus
        // (arrow-key target) shares the indicator since the focused card is
        // always the most-recently single-selected one.
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isHighlighted ? MAYNTheme.focusRing : .clear, lineWidth: 2)
        )
        .overlay(alignment: .bottomLeading) {
            if index < 9 {
                Text("⌘\(index + 1)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .padding(6)
            }
        }
        // Card drag uses .onDrag (not .draggable) so we can flip the
        // shared `draggedCardID` synchronously when the drag starts —
        // the dimming overlay (and any future drag-time UI) needs to
        // know the source ID.
        .onDrag {
            draggedCardID = item.id
            scheduleCardDragTimeout(for: item.id)
            return NSItemProvider(
                object: DockItemDrag.encode(recordID: item.id) as NSString
            )
        } preview: {
            DockDragPreview(item: item)
        }
        // In a pinboard, dropping a card on top of another reorders the
        // dragged card to the target's position. History/Snippets ignore
        // (those orderings aren't user-editable). Live shift during hover
        // produced a SwiftUI hit-test ping-pong (the moved card slid out
        // from under the cursor and the next neighbor immediately fired
        // another reorder); a clear leading-edge insertion indicator is
        // both reliable and easier to read.
        .modifier(
            CardReorderDropTarget(
                enabled: model.isActiveListReorderable,
                isTargeted: $isCardDropTarget,
                action: { strings in
                    handleCardReorderDrop(strings: strings)
                }
            )
        )
        .overlay(
            // While being dragged this card dims so the user sees what's
            // moving. Other cards stay normal.
            Color.clear
                .background(draggedCardID == item.id ? Color.black.opacity(0.18) : Color.clear)
                .allowsHitTesting(false)
        )
        .overlay(alignment: .leading) {
            // Vertical accent bar on the leading edge of the card under the
            // cursor — signals "drop here to insert before this card".
            // Only shown for foreign drags (not when this card is the one
            // being dragged) to avoid confusion.
            if isCardDropTarget,
               let dragged = draggedCardID,
               dragged != item.id
            {
                Rectangle()
                    .fill(MAYNTheme.focusRing)
                    .frame(width: 4)
                    .padding(.vertical, 4)
                    .transition(.opacity)
            }
        }
        .contextMenu {
            CardContextMenu(item: item, model: model, renamingItemID: Binding(
                get: { showingRename ? item.id : nil },
                set: { showingRename = ($0 == item.id) }
            ))
        }
        .sheet(isPresented: $showingRename) {
            RenameCardSheet(item: item, isPresented: $showingRename) { label in
                Task { await model.renameItem(itemID: item.id, label: label) }
            }
        }
    }

    /// On hover, drive the live in-memory reorder. On exit, do nothing —
    /// the new order persists when the user releases (handleCardReorderDrop).
    private var dropTargetedBinding: Binding<Bool> {
        Binding<Bool>(
            get: { isCardDropTarget },
            set: { newValue in
                isCardDropTarget = newValue
            }
        )
    }

    /// Cancel-safe drag state cleanup — if the drop never lands (released
    /// off-window, escape pressed) we still need to clear `draggedCardID`.
    private func scheduleCardDragTimeout(for id: String) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            if draggedCardID == id {
                draggedCardID = nil
            }
        }
    }

    /// Drop landed on this card → ask the model to move the source card
    /// to this slot's position in the active pinboard. Self-drops are
    /// filtered (we only get here if the source != this card).
    private func handleCardReorderDrop(strings: [String]) -> Bool {
        guard let raw = strings.first(where: { DockItemDrag.decode($0) != nil }),
              let sourceID = DockItemDrag.decode(raw),
              sourceID != item.id
        else {
            draggedCardID = nil
            return false
        }
        Task { @MainActor in
            await model.reorderCardInActivePinboard(movingID: sourceID, beforeID: item.id)
            draggedCardID = nil
        }
        return true
    }
}

/// Per-card drop target that only attaches when the active list is a
/// reorderable pinboard. History/Snippets get the no-op branch so the cursor
/// doesn't show a green plus while hovering them mid-drag.
private struct CardReorderDropTarget: ViewModifier {
    let enabled: Bool
    @Binding var isTargeted: Bool
    let action: ([String]) -> Bool

    func body(content: Content) -> some View {
        if enabled {
            content.dropDestination(for: String.self) { strings, _ in
                action(strings)
            } isTargeted: { isTargeted = $0 }
        } else {
            content
        }
    }
}

/// Small, mouse-cursor-anchored thumbnail that floats alongside the cursor
/// during a card drag. Replaces SwiftUI's default full-card preview so the
/// drop targets aren't visually obscured.
private struct DockDragPreview: View {
    let item: DockItem

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: kindSymbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
            Text(previewText)
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: 220)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.24), lineWidth: 1)
        )
    }

    private var kindSymbol: String {
        switch item.kind {
        case .text, .rtf: return "text.alignleft"
        case .image: return "photo"
        case .file: return "doc.fill"
        case .link: return "link"
        case .color: return "circle.fill"
        case .code: return "chevron.left.forwardslash.chevron.right"
        }
    }

    private var previewText: String {
        let trimmed = item.preview.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Clipboard item" : trimmed
    }
}
