import Core
import SwiftUI

// MARK: - Visual tab strip

/// Renders the pill-shaped tab strip with per-tab backgrounds, dot colors,
/// drag previews, and accessibility annotations. All drag/drop wiring is
/// injected via closures so this view has no knowledge of the reorder state
/// machine or drop-target detection.
struct DockListTabStrip: View {
    @Bindable var model: ClipboardDockModel
    @Binding var dropTargetSelector: DockListSelector?
    @Binding var dropConfirmedSelector: DockListSelector?
    @Binding var tabDropFrames: [DockListTabDropFrame]
    @Binding var draggedTabID: RecordID?

    let liveReorderTab: (RecordID, DockListTabReorderTarget) -> Void
    let handleDrop: ([String], DockListSelector) -> Bool
    let runDropConfirmation: (DockListSelector) -> Void
    let onTapTab: (DockListSelector) -> Void
    let onDragBegan: (RecordID) -> Void
    let onDeletePinboard: (RecordID) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionNamespace

    var body: some View {
        tabPill
    }

    // MARK: - Pill container

    private var tabPill: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            tabStripDropSurface
        }
        // The drop target lives on the strip content, not the ScrollView
        // viewport. This keeps DropInfo.location in the same coordinate space
        // as the tab frames reported by DockListTabFrameReporter.
        // ScrollView-level drops were fragile in the bottom NSPanel because
        // the tab/card gesture layers could prevent location resolution from
        // matching the visible tab under the cursor.
        .frame(height: 38)
        .layoutPriority(1)
    }

    private var tabStripDropSurface: some View {
        tabStripContent
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(MAYNTheme.panel, in: Capsule())
            .overlay(Capsule().stroke(MAYNTheme.strongBorder, lineWidth: 1))
            .coordinateSpace(name: DockListTabsPresentation.dropCoordinateSpace)
            .onPreferenceChange(DockListTabDropFramePreferenceKey.self) { frames in
                tabDropFrames = frames
            }
            // Animate the HStack reorder so tabs slide into their new
            // positions during a live drag instead of jumping.
            .animation(MAYNMotion.tabAnimation(reduceMotion: reduceMotion), value: model.availableLists.map(\.id))
            .onDrop(
                of: DockDragPayloadTypes.acceptedTypeIdentifiers,
                delegate: DockListStripDropDelegate(
                    tabFrames: tabDropFrames,
                    dropTargetSelector: $dropTargetSelector,
                    draggedTabID: $draggedTabID,
                    reduceMotion: reduceMotion,
                    liveReorderTab: liveReorderTab,
                    handleDrop: handleDrop,
                    runDropConfirmation: runDropConfirmation
                )
            )
            .overlay {
                if dropSurfaceIsActive {
                    DockListStripAppKitDropSurface(
                        tabFrames: tabDropFrames,
                        dropTargetSelector: $dropTargetSelector,
                        draggedTabID: $draggedTabID,
                        reduceMotion: reduceMotion,
                        liveReorderTab: liveReorderTab,
                        handleDrop: handleDrop,
                        runDropConfirmation: runDropConfirmation
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .zIndex(20)
                }
            }
    }

    private var tabStripContent: some View {
        HStack(spacing: 6) {
            tab(label: DockListTabsPresentation.historyLabel, selector: .history, dotColor: nil)
            tab(label: DockListTabsPresentation.snippetsLabel, selector: .snippets, dotColor: nil)

            // Pinned is no longer special — it appears here just like any
            // user-created pinboard, ordered by creation time via
            // PinboardStore.sort_order.
            ForEach(model.availableLists, id: \.id) { board in
                tab(label: board.name, selector: .pinboard(board.id), dotColor: displayDotColor(for: board))
                    .onDrag {
                        onDragBegan(board.id)
                        return NSItemProvider(
                            object: DockTabDrag.encode(boardID: board.id.rawValue) as NSString
                        )
                    } preview: {
                        tabDragPreview(label: board.name, dotColor: board.color)
                    }
                    .contextMenu {
                        Button("Rename…") {}
                        Button("Delete", role: .destructive) {
                            onDeletePinboard(board.id)
                        }
                    }
            }
        }
    }

    // MARK: - Drop surface activation

    private var dropSurfaceIsActive: Bool {
        DockListDropSurfaceState.isActive(
            draggedTabID: draggedTabID,
            activeDraggedItemID: model.activeDraggedItemID,
            windowDragIsActive: model.isDockDragSurfaceActive
        )
    }

    // MARK: - Per-tab rendering

    @ViewBuilder
    private func tab(label: String, selector: DockListSelector, dotColor: String?) -> some View {
        let active = model.activeList == selector
        // Suppress the "drop here" highlight while a tab-reorder drag is
        // active; the live slide already communicates where the tab will land.
        let isDropping = dropTargetSelector == selector && draggedTabID == nil
        let isConfirmed = dropConfirmedSelector == selector

        HStack(spacing: 6) {
            if let dotColor, let color = colorFromHex(dotColor) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
            } else {
                Image(systemName: tabSymbol(for: selector))
                    .font(.system(size: 11, weight: .semibold))
            }
            Text(label)
                .font(.callout.weight(.medium))
                .lineLimit(1)
        }
        .foregroundStyle(active ? .primary : .secondary)
        .padding(.horizontal, 14)
        .frame(height: 30)
        .background(tabBackground(active: active, isDropping: isDropping))
        .background(DockListTabFrameReporter(selector: selector))
        .contentShape(Capsule())
        .scaleEffect(isConfirmed && !reduceMotion ? 1.035 : (isDropping && !reduceMotion ? 1.02 : 1.0))
        .offset(y: isDropping && !reduceMotion ? -3 : 0)
        // Dim ONLY when this exact tab is being dragged. Original
        // condition (`draggedTabID == pinboardID(of: selector)`)
        // collapsed to nil == nil for non-pinboard tabs at rest, so
        // History/Snippets stayed at 40% opacity permanently.
        .opacity(isThisTabBeingDragged(selector: selector) ? 0.4 : 1.0)
        .zIndex(isDropping || isConfirmed ? 30 : 0)
        .modifier(
            DockListItemTabDropTarget(
                selector: selector,
                dropTargetSelector: $dropTargetSelector,
                draggedTabID: $draggedTabID,
                reduceMotion: reduceMotion,
                liveReorderTab: liveReorderTab,
                handleDrop: handleDrop,
                runDropConfirmation: runDropConfirmation
            )
        )
        .onTapGesture {
            onTapTab(selector)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(active ? "Selected" : "")
        .animation(MAYNMotion.tabAnimation(reduceMotion: reduceMotion), value: isDropping)
        .animation(MAYNMotion.tabAnimation(reduceMotion: reduceMotion), value: isConfirmed)
    }

    @ViewBuilder
    private func tabBackground(active: Bool, isDropping: Bool) -> some View {
        if isDropping {
            Capsule()
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(Capsule().stroke(MAYNTheme.focusRing.opacity(0.95), lineWidth: 1.5))
                .shadow(color: Color.black.opacity(0.16), radius: 10, x: 0, y: 4)
        } else if active {
            MAYNSelectionGlassBackground(isSelected: true, isHovering: false, shape: .capsule)
                .matchedGeometryEffect(id: "dock-tab-selection", in: selectionNamespace)
        } else {
            Capsule()
                .fill(Color.clear)
        }
    }

    // MARK: - Helpers

    private func tabSymbol(for selector: DockListSelector) -> String {
        switch selector {
        case .history:
            return "clock"
        case .snippets:
            return "text.quote"
        case .pinboard:
            return "pin"
        }
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

    private func colorFromHex(_ hex: String) -> Color? {
        let normalized = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard normalized.count == 6, let value = UInt64(normalized, radix: 16) else { return nil }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    private func displayDotColor(for board: Pinboard) -> String? {
        if board.name == PinnedPinboard.displayName {
            return PinnedPinboard.displayColor
        }
        return board.color
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
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.secondary.opacity(0.24), lineWidth: 1))
    }
}
