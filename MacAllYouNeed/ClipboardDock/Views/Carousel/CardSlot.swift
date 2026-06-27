import AppKit
import SwiftUI

enum DockCardDragPreviewStyle: Equatable {
    case compactIcon
}

enum DockCardReorderPlacement: Equatable {
    case before
    case after
}

struct DockCardReorderTarget: Equatable {
    let itemID: String
    let placement: DockCardReorderPlacement
}

struct DockCardDropFrame: Equatable {
    let itemID: String
    let rect: CGRect
}

enum DockCardDropResolver {
    private static let verticalTolerance: CGFloat = 18
    private static let appendAfterLastHorizontalTolerance: CGFloat = 96

    static func reorderTarget(
        at location: CGPoint,
        in frames: [DockCardDropFrame]
    ) -> DockCardReorderTarget? {
        let cardFrames = frames.sorted { $0.rect.minX < $1.rect.minX }
        guard !cardFrames.isEmpty,
              let verticalRange = cardFrames.verticalRange,
              location.y >= verticalRange.lowerBound - verticalTolerance,
              location.y <= verticalRange.upperBound + verticalTolerance
        else { return nil }

        if let direct = cardFrames.first(where: { $0.hitRect.contains(location) }) {
            return DockCardReorderTarget(
                itemID: direct.itemID,
                placement: location.x < direct.rect.midX ? .before : .after
            )
        }

        if let last = cardFrames.last,
           location.x > last.rect.maxX,
           location.x <= last.rect.maxX + appendAfterLastHorizontalTolerance
        {
            return DockCardReorderTarget(itemID: last.itemID, placement: .after)
        }

        return nil
    }
}

enum DockCardReorderPresentation {
    static let usesNSItemProviderCompatibleDropTarget = true
    static let usesAppKitDropBackstop = true
    static let usesDirectLocalDragGesture = true
    static let appKitDropSurfaceRequiresNativeCardDrag = true
    static let usesNativeDragInsideReorderablePinboards = false
    static let acceptsUTF8PlainTextPayloads = DockDragPayloadTypes.acceptedTypeIdentifiers.contains("public.utf8-plain-text")
    static let dragPreviewStyle: DockCardDragPreviewStyle = .compactIcon
    static let trailingDropTargetWidth: CGFloat = 56
    static let dropCoordinateSpace = "DockCardDropCoordinateSpace"
}

enum DockCardShellPresentation {
    static let width: CGFloat = 220
    static let height: CGFloat = 240
    static let cornerRadius: CGFloat = MAYNControlMetrics.cardRadius
    static let focusedBorderWidth: CGFloat = 2
    /// `CardSlot` paints a ⌘1…⌘9 chip over the bottom-leading corner; smart
    /// text footers reserve this much **extra** leading inset so labels never
    /// draw under the chip (chip pad 6 + ~⌘9 width + margin).
    static let pasteShortcutChipGutter: CGFloat = 50
}

enum DockCardDragStatePolicy {
    static func shouldClearLocalDrag(
        draggedCardID: DockItem.ID?,
        nativeDraggedCardID: DockItem.ID?,
        activeDraggedItemID: DockItem.ID?,
        isDockDragSurfaceActive: Bool
    ) -> Bool {
        guard draggedCardID != nil || nativeDraggedCardID != nil else { return false }
        return activeDraggedItemID == nil && !isDockDragSurfaceActive
    }

    static func shouldShowDraggedCardDim(
        cardID: DockItem.ID,
        draggedCardID: DockItem.ID?,
        activeDraggedItemID: DockItem.ID?,
        isDockDragSurfaceActive: Bool
    ) -> Bool {
        draggedCardID == cardID &&
            activeDraggedItemID == cardID &&
            isDockDragSurfaceActive
    }
}

private extension DockCardDropFrame {
    var hitRect: CGRect {
        rect.insetBy(dx: -3, dy: -6)
    }
}

private extension [DockCardDropFrame] {
    var verticalRange: ClosedRange<CGFloat>? {
        guard let first else { return nil }
        var minY = first.rect.minY
        var maxY = first.rect.maxY
        for frame in dropFirst() {
            minY = Swift.min(minY, frame.rect.minY)
            maxY = Swift.max(maxY, frame.rect.maxY)
        }
        return minY ... maxY
    }
}

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
    @Binding var nativeDraggedCardID: String?
    let onLocalReorderDragChanged: (String, CGPoint) -> Void
    let onLocalReorderDragEnded: (String, CGPoint) -> Void
    @Environment(ClipboardDockModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
            cardBackground: cardBackground,
            isHighlighted: isHighlighted,
            showsPasteShortcutChip: index < 9
        )
        .frame(width: DockCardShellPresentation.width, height: DockCardShellPresentation.height)
        .maynSelectionBackground(
            isSelected: isHighlighted,
            shape: .rounded(DockCardShellPresentation.cornerRadius)
        )
        .clipShape(
            RoundedRectangle(cornerRadius: DockCardShellPresentation.cornerRadius, style: .continuous)
        )
        .animation(MAYNMotion.hoverAnimation(reduceMotion: reduceMotion), value: isHighlighted)
        .overlay(alignment: .bottomLeading) {
            if index < 9 {
                ShortcutChip(text: "⌘\(index + 1)", height: HotkeyChipPresentation.compactHeight)
                    .padding(6)
            }
        }
        // Native NSPasteboard drag is only needed when dragging cards from
        // non-reorderable lists onto pinboard tabs. Inside a pinboard, card
        // reorder stays local so the bottom panel cannot cover or steal the
        // drag interaction.
        .modifier(
            CardNativeDragModifier(
                enabled: !model.isActiveListReorderable,
                item: item,
                draggedCardID: $draggedCardID,
                nativeDraggedCardID: $nativeDraggedCardID,
                onDragStarted: scheduleCardDragTimeout(for:)
            )
        )
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
            // moving. Tie the visual to the global drag session too, so a
            // stale local drag ID cannot leave a post-drop shadow behind.
            Color.clear
                .background(isDimmedForActiveDrag ? Color.black.opacity(0.18) : Color.clear)
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
        .modifier(
            LocalCardReorderGesture(
                enabled: model.isActiveListReorderable,
                itemID: item.id,
                draggedCardID: $draggedCardID,
                nativeDraggedCardID: $nativeDraggedCardID,
                onChanged: onLocalReorderDragChanged,
                onEnded: onLocalReorderDragEnded
            )
        )
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

    private var isDimmedForActiveDrag: Bool {
        DockCardDragStatePolicy.shouldShowDraggedCardDim(
            cardID: item.id,
            draggedCardID: draggedCardID,
            activeDraggedItemID: model.activeDraggedItemID,
            isDockDragSurfaceActive: model.isDockDragSurfaceActive
        )
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
            if nativeDraggedCardID == id {
                nativeDraggedCardID = nil
            }
            if model.activeDraggedItemID == id {
                model.activeDraggedItemID = nil
            }
            model.isDockDragSurfaceActive = false
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
            nativeDraggedCardID = nil
            model.activeDraggedItemID = nil
            model.isDockDragSurfaceActive = false
            return false
        }
        Task { @MainActor in
            await model.reorderCardInActivePinboard(
                movingID: sourceID,
                targetID: item.id,
                placement: .before
            )
            draggedCardID = nil
            nativeDraggedCardID = nil
            model.activeDraggedItemID = nil
            model.isDockDragSurfaceActive = false
        }
        return true
    }
}

private struct CardNativeDragModifier: ViewModifier {
    let enabled: Bool
    let item: DockItem
    @Binding var draggedCardID: String?
    @Binding var nativeDraggedCardID: String?
    let onDragStarted: (String) -> Void
    @Environment(ClipboardDockModel.self) private var model

    func body(content: Content) -> some View {
        if enabled {
            content.onDrag {
                draggedCardID = item.id
                nativeDraggedCardID = item.id
                model.activeDraggedItemID = item.id
                model.isDockDragSurfaceActive = true
                onDragStarted(item.id)
                return NSItemProvider(
                    object: DockItemDrag.encode(recordID: item.id) as NSString
                )
            } preview: {
                DockDragPreview(item: item)
            }
        } else {
            content
        }
    }
}

private struct LocalCardReorderGesture: ViewModifier {
    let enabled: Bool
    let itemID: String
    @Binding var draggedCardID: String?
    @Binding var nativeDraggedCardID: String?
    let onChanged: (String, CGPoint) -> Void
    let onEnded: (String, CGPoint) -> Void

    func body(content: Content) -> some View {
        if enabled {
            content.highPriorityGesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .local)
                    .onChanged { value in
                        if draggedCardID == nil {
                            draggedCardID = itemID
                        }
                        // This is an in-process reorder, not an NSPasteboard
                        // drag; keep the AppKit drop backstop out of the
                        // gesture path so it cannot cover the active card.
                        nativeDraggedCardID = nil
                        onChanged(itemID, value.location)
                    }
                    .onEnded { value in
                        onEnded(itemID, value.location)
                    }
            )
        } else {
            content
        }
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
            content.onDrop(
                of: DockDragPayloadTypes.acceptedTypeIdentifiers,
                delegate: CardReorderDropDelegate(isTargeted: $isTargeted, action: action)
            )
        } else {
            content
        }
    }
}

private struct CardReorderDropDelegate: DropDelegate {
    @Binding var isTargeted: Bool
    let action: ([String]) -> Bool

    func validateDrop(info: DropInfo) -> Bool {
        !info.itemProviders(for: DockDragPayloadTypes.acceptedTypeIdentifiers).isEmpty
    }

    func dropUpdated(info _: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropEntered(info _: DropInfo) {
        isTargeted = true
    }

    func dropExited(info _: DropInfo) {
        isTargeted = false
    }

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: DockDragPayloadTypes.acceptedTypeIdentifiers)
        guard !providers.isEmpty else {
            isTargeted = false
            return false
        }

        DockDragPayloadLoader.strings(from: providers) { strings in
            _ = action(strings)
            isTargeted = false
        }
        return true
    }
}

/// Small, mouse-cursor-anchored thumbnail that floats alongside the cursor
/// during a card drag. Replaces SwiftUI's default full-card preview so the
/// drop targets aren't visually obscured.
private struct DockDragPreview: View {
    let item: DockItem

    var body: some View {
        Image(systemName: kindSymbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 34, height: 34)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(Color.secondary.opacity(0.24), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.14), radius: 10, x: 0, y: 4)
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

}
