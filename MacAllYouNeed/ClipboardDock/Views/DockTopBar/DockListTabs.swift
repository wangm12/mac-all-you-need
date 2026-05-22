import AppKit
import Core
import SwiftUI

// design.md §11 exception: this strip cannot adopt FunctionSegmentedTabStrip
// because it requires custom drag-reorder and drop-target behavior. The visual
// appearance mirrors the standard tab strip. Internal decomposition is permitted.
struct DockListTabs: View {
    @Bindable var model: ClipboardDockModel
    @State private var showNew = false
    @State private var dropTargetSelector: DockListSelector?
    /// Selector that just received a successful drop, used to drive a
    /// short "pulse" animation as drop confirmation.
    @State private var dropConfirmedSelector: DockListSelector?
    @State private var tabDropFrames: [DockListTabDropFrame] = []
    /// Set when a user pinboard tab begins a drag; cleared on drop or after a
    /// safety timeout. Used to distinguish a tab-reorder drag (live shift) from
    /// an item-pin drag (highlight + drop) when `isTargeted` fires on a tab.
    @State private var draggedTabID: RecordID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            DockListTabStrip(
                model: model,
                dropTargetSelector: $dropTargetSelector,
                dropConfirmedSelector: $dropConfirmedSelector,
                tabDropFrames: $tabDropFrames,
                draggedTabID: $draggedTabID,
                liveReorderTab: liveReorderTab(draggedID:target:),
                handleDrop: handleDrop(_:on:),
                runDropConfirmation: runDropConfirmation(on:),
                onTapTab: { selector in Task { await model.switchList(selector) } },
                onDragBegan: { id in
                    draggedTabID = id
                    // Safety: clear the drag state if no drop fires
                    // within a few seconds (drag cancelled, dropped
                    // off-window, etc.) so the bar doesn't get stuck
                    // in "live reorder" mode forever.
                    scheduleDragTimeout(for: id)
                },
                onDeletePinboard: { id in
                    Task { await model.deletePinboard(id: id) }
                }
            )
            addListButton
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 38)
        .animation(MAYNMotion.normalAnimation(reduceMotion: reduceMotion), value: model.activeList.animationID)
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

    // MARK: - Add button

    private var addListButton: some View {
        Button {
            showNew = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: MAYNControlMetrics.controlHeight, height: MAYNControlMetrics.controlHeight)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .background(MAYNTheme.panel, in: Circle())
        .overlay(Circle().stroke(MAYNTheme.strongBorder, lineWidth: 1))
        .contentShape(Circle())
        .help("New tab")
    }

    // MARK: - Drag-reorder

    /// In-memory move: place `draggedID` before/after `target` and animate the
    /// HStack into the new layout. Persist happens on drop.
    private func liveReorderTab(draggedID: RecordID, target: DockListTabReorderTarget) {
        guard draggedID != target.targetID else { return }
        var ids = model.availableLists.map(\.id)
        guard let from = ids.firstIndex(of: draggedID) else { return }
        ids.remove(at: from)
        guard let targetIndex = ids.firstIndex(of: target.targetID) else { return }
        let insertIndex: Int
        switch target.placement {
        case .before:
            insertIndex = targetIndex
        case .after:
            insertIndex = min(targetIndex + 1, ids.count)
        }
        ids.insert(draggedID, at: insertIndex)
        withAnimation(MAYNMotion.tabAnimation(reduceMotion: reduceMotion)) {
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
                model.isDockDragSurfaceActive = false
                // The in-memory order may diverge from disk if the user
                // dragged but never dropped — sync it back so a relaunch
                // sees the actual stored order.
                await model.loadAvailableLists()
            }
        }
    }

    // MARK: - Drop handling

    private func handleDrop(_ rawStrings: [String], on selector: DockListSelector) -> Bool {
        // Tab-reorder drop — live shift already happened during hover; just
        // persist the final order. Only valid on user pinboard tabs; built-ins
        // (Pinned, History, Snippets) ignore tab-reorder drops entirely.
        if rawStrings.contains(where: { DockTabDrag.decode($0) != nil }) {
            guard case .pinboard = selector else {
                draggedTabID = nil
                model.isDockDragSurfaceActive = false
                return false
            }
            Task { @MainActor in
                await model.persistPinboardOrder()
                draggedTabID = nil
                model.isDockDragSurfaceActive = false
            }
            return true
        }

        // Item-pin path.
        let recordIDs = rawStrings.compactMap(DockItemDrag.decode)
        guard !recordIDs.isEmpty else { return false }
        model.finishDockDrag()
        Task { @MainActor in
            switch selector {
            case .snippets:
                await model.switchList(.snippets)
                await model.beginSnippetDraftFromClipboard(itemIDs: recordIDs)
            case .pinboard(let boardID):
                await model.addToPinboard(itemIDs: recordIDs, boardID: boardID)
                await model.loadAvailableLists()
            default:
                break
            }
        }
        return true
    }

    /// Brief pulse on the dropped tab to acknowledge the action.
    private func runDropConfirmation(on selector: DockListSelector) {
        withAnimation(MAYNMotion.tabAnimation(reduceMotion: reduceMotion)) {
            dropConfirmedSelector = selector
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(MAYNMotionDuration.panel * 1000)))
            withAnimation(MAYNMotion.controlAnimation(reduceMotion: reduceMotion)) {
                dropConfirmedSelector = nil
            }
        }
    }
}
