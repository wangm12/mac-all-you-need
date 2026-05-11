import AppKit
import Core
import SwiftUI

struct DockListTabs: View {
    @Bindable var model: ClipboardDockModel
    @State private var showNew = false
    @State private var dropTargetSelector: DockListSelector?
    /// Selector that just received a successful drop, used to drive a
    /// short "pulse" animation as drop confirmation.
    @State private var dropConfirmedSelector: DockListSelector?
    /// Set when a user pinboard tab begins a drag; cleared on drop or after a
    /// safety timeout. Used to distinguish a tab-reorder drag (live shift) from
    /// an item-pin drag (highlight + drop) when `isTargeted` fires on a tab.
    @State private var draggedTabID: RecordID?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                tab(label: "Clipboard History", selector: .history, dotColor: nil)
                tab(label: "Snippets", selector: .snippets, dotColor: nil)

                // Pinned is no longer special — it appears here just like any
                // user-created pinboard, ordered by creation time via
                // PinboardStore.sort_order.
                ForEach(model.availableLists, id: \.id) { board in
                    tab(label: board.name, selector: .pinboard(board.id), dotColor: board.color)
                        .onDrag {
                            draggedTabID = board.id
                            // Safety: clear the drag state if no drop fires
                            // within a few seconds (drag cancelled, dropped
                            // off-window, etc.) so the bar doesn't get stuck
                            // in "live reorder" mode forever.
                            scheduleDragTimeout(for: board.id)
                            return NSItemProvider(
                                object: DockTabDrag.encode(boardID: board.id.rawValue) as NSString
                            )
                        } preview: {
                            tabDragPreview(label: board.name, dotColor: board.color)
                        }
                        .contextMenu {
                            Button("Rename…") {}
                            Button("Delete", role: .destructive) {
                                Task {
                                    try? model.pinboards.delete(id: board.id)
                                    await model.loadAvailableLists()
                                }
                            }
                        }
                }

                Button {
                    showNew = true
                } label: {
                    Image(systemName: "plus")
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 6)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            // Animate the HStack reorder so tabs slide into their new
            // positions during a live drag instead of jumping.
            .animation(.easeInOut(duration: 0.18), value: model.availableLists.map(\.id))
        }
        .task {
            await model.loadAvailableLists()
        }
        .sheet(isPresented: $showNew) {
            NewListSheet(isPresented: $showNew) { name, color in
                Task {
                    _ = try? model.pinboards.create(name: name, color: color)
                    await model.loadAvailableLists()
                }
            }
        }
    }

    @ViewBuilder
    private func tab(label: String, selector: DockListSelector, dotColor: String?) -> some View {
        let active = model.activeList == selector
        // Suppress the "drop here" highlight while a tab-reorder drag is
        // active; the live slide already communicates where the tab will land.
        let isDropping = dropTargetSelector == selector && draggedTabID == nil
        let isConfirmed = dropConfirmedSelector == selector
        let acceptsDrop = canAcceptDrop(on: selector)
        let dropTargetedBinding = Binding<Bool>(
            get: { dropTargetSelector == selector },
            set: { newValue in
                // Tab-reorder branch: live in-memory shift when the dragged
                // tab crosses another user pinboard tab.
                if newValue,
                   let draggedID = draggedTabID,
                   case let .pinboard(targetID) = selector,
                   draggedID != targetID
                {
                    liveReorderTab(draggedID: draggedID, targetID: targetID)
                    return
                }
                // While a tab-reorder drag is active, suppress every other
                // hover effect (Pinned scale-glow, etc.). The drag is not an
                // item-pin operation, and lighting up unrelated targets is
                // misleading and visually noisy.
                if draggedTabID != nil { return }
                // Item-pin branch.
                withAnimation(.spring(response: 0.22, dampingFraction: 0.75)) {
                    dropTargetSelector = newValue ? selector : nil
                }
            }
        )

        Button {
            Task { await model.switchList(selector) }
        } label: {
            HStack(spacing: 4) {
                if let dotColor, let color = colorFromHex(dotColor) {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                }
                Text(label)
                    .font(.callout)
                    .fontWeight(isDropping ? .semibold : .regular)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(tabBackground(active: active, isDropping: isDropping))
            .clipShape(Capsule())
            .overlay {
                if isDropping {
                    Capsule()
                        .stroke(Color.accentColor, lineWidth: 2)
                }
            }
            .scaleEffect(isConfirmed ? 1.5 : (isDropping ? 1.32 : 1.0))
            .shadow(
                color: isDropping ? Color.accentColor.opacity(0.6) : .clear,
                radius: isDropping ? 14 : 0,
                x: 0, y: 0
            )
            // Dim ONLY when this exact tab is being dragged. Original
            // condition (`draggedTabID == pinboardID(of: selector)`)
            // collapsed to nil == nil for non-pinboard tabs at rest, so
            // History/Snippets stayed at 40% opacity permanently.
            .opacity(isThisTabBeingDragged(selector: selector) ? 0.4 : 1.0)
            .zIndex(isDropping || isConfirmed ? 1 : 0)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.22, dampingFraction: 0.75), value: isDropping)
        .animation(.spring(response: 0.32, dampingFraction: 0.55), value: isConfirmed)
        .modifier(
            ConditionalDropTarget(
                enabled: acceptsDrop,
                isTargeted: dropTargetedBinding,
                action: { strings in
                    let accepted = handleDrop(strings, on: selector)
                    if accepted, draggedTabID == nil {
                        // Only pulse on item-pin drops; tab-reorder drops
                        // are already self-evident from the slide.
                        runDropConfirmation(on: selector)
                    }
                    return accepted
                }
            )
        )
    }

    private func canAcceptDrop(on selector: DockListSelector) -> Bool {
        switch selector {
        case .pinboard:
            return true
        case .history, .snippets:
            // Still need a drop target during tab-reorder drags so the
            // dragged tab can pass through these on its way to a destination.
            // They never actually receive an item drop.
            return false
        }
    }

    private func tabBackground(active: Bool, isDropping: Bool) -> Color {
        if isDropping { return Color.accentColor.opacity(0.28) }
        if active { return Color(nsColor: Self.activeTabFill) }
        return .clear
    }

    /// Fully-opaque "selected pill" color that adapts to dark/light. Using
    /// `Color.secondary.opacity(0.2)` left the panel showing through and
    /// made the active pill look hazy compared to the inactive tabs.
    private static let activeTabFill = NSColor(name: nil) { appearance in
        switch appearance.bestMatch(from: [.darkAqua, .vibrantDark]) {
        case .some:
            return NSColor(srgbRed: 0.27, green: 0.27, blue: 0.28, alpha: 1)
        default:
            return NSColor(srgbRed: 0.86, green: 0.86, blue: 0.87, alpha: 1)
        }
    }

    private func pinboardID(of selector: DockListSelector) -> RecordID? {
        if case let .pinboard(id) = selector { return id }
        return nil
    }

    /// True when there's an active tab-reorder drag AND this tab is the
    /// source. Used to dim the dragged tab so the user sees what's moving.
    /// Returns false when no drag is in progress, so non-pinboard tabs
    /// (History/Snippets) don't accidentally appear dimmed at rest.
    private func isThisTabBeingDragged(selector: DockListSelector) -> Bool {
        guard let draggedTabID,
              case let .pinboard(id) = selector
        else { return false }
        return draggedTabID == id
    }

    private func handleDrop(_ rawStrings: [String], on selector: DockListSelector) -> Bool {
        // Tab-reorder drop — live shift already happened during hover; just
        // persist the final order. Only valid on user pinboard tabs; built-ins
        // (Pinned, History, Snippets) ignore tab-reorder drops entirely.
        if rawStrings.contains(where: { DockTabDrag.decode($0) != nil }) {
            guard case .pinboard = selector else {
                draggedTabID = nil
                return false
            }
            Task { @MainActor in
                await model.persistPinboardOrder()
                draggedTabID = nil
            }
            return true
        }

        // Item-pin path.
        let recordIDs = rawStrings.compactMap(DockItemDrag.decode)
        guard !recordIDs.isEmpty else { return false }
        Task { @MainActor in
            switch selector {
            case .pinboard(let boardID):
                await model.addToPinboard(itemIDs: recordIDs, boardID: boardID)
                await model.loadAvailableLists()
            default:
                break
            }
        }
        return true
    }

    /// In-memory swap: move `draggedID` to `targetID`'s slot and animate the
    /// HStack into the new layout. Persist happens on drop.
    private func liveReorderTab(draggedID: RecordID, targetID: RecordID) {
        var ids = model.availableLists.map(\.id)
        guard let from = ids.firstIndex(of: draggedID),
              let to = ids.firstIndex(of: targetID),
              from != to
        else { return }
        ids.remove(at: from)
        let insertIndex = min(to, ids.count)
        ids.insert(draggedID, at: insertIndex)
        withAnimation(.easeInOut(duration: 0.18)) {
            model.reorderPinboardsLocally(orderedIDs: ids)
        }
    }

    /// Clear `draggedTabID` after a few seconds in case the drag is cancelled
    /// (released off-window, escape pressed) and `handleDrop` never fires.
    private func scheduleDragTimeout(for id: RecordID) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            if draggedTabID == id {
                draggedTabID = nil
                // The in-memory order may diverge from disk if the user
                // dragged but never dropped — sync it back so a relaunch
                // sees the actual stored order.
                await model.persistPinboardOrder()
            }
        }
    }

    /// Brief pulse on the dropped tab to acknowledge the action.
    private func runDropConfirmation(on selector: DockListSelector) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.55)) {
            dropConfirmedSelector = selector
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(280))
            withAnimation(.easeOut(duration: 0.18)) {
                dropConfirmedSelector = nil
            }
        }
    }

    private func colorFromHex(_ hex: String) -> Color? {
        let normalized = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard normalized.count == 6, let value = UInt64(normalized, radix: 16) else { return nil }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    @ViewBuilder
    private func tabDragPreview(label: String, dotColor: String?) -> some View {
        HStack(spacing: 4) {
            if let dotColor, let color = colorFromHex(dotColor) {
                Circle().fill(color).frame(width: 8, height: 8)
            }
            Text(label).font(.callout)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.regularMaterial)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.accentColor.opacity(0.5), lineWidth: 1))
    }
}

/// Applies `.dropDestination(for: String.self)` only when the target tab is
/// droppable. History/Snippets use the no-op branch so the cursor doesn't
/// show the green plus while hovering them.
private struct ConditionalDropTarget: ViewModifier {
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
