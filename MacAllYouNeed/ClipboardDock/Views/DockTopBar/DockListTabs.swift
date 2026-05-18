import AppKit
import Core
import SwiftUI

enum DockListAddButtonPlacement: Equatable {
    case outsidePill
}

enum DockListTabScrollSizing: Equatable {
    case flexibleViewport
}

enum DockListTabDropTargetPlacement: Equatable {
    case stripContent
}

enum DockListDropTargetLiftStyle: Equatable {
    case liftedTab
}

enum DockListDropSurfaceActivation: Equatable {
    case windowDragOrActiveDrag
}

enum DockListTabReorderPlacement: Equatable {
    case before
    case after
}

struct DockListTabReorderTarget: Equatable {
    let targetID: RecordID
    let placement: DockListTabReorderPlacement

    var selector: DockListSelector {
        .pinboard(targetID)
    }
}

enum DockListItemTabDropPolicy {
    static func acceptsPerTabDrop(draggedTabID: RecordID?) -> Bool {
        draggedTabID == nil
    }
}

enum DockListTabsPresentation {
    static let historyLabel = "Clipboard History"
    static let snippetsLabel = "Snippets"
    static let addButtonPlacement: DockListAddButtonPlacement = .outsidePill
    static let usesNSItemProviderCompatibleDropTarget = true
    static let inactiveTabsKeepTransparentDropSurface = true
    static let tabDropSurfaceAvoidsNestedButton = true
    static let scrollSizing: DockListTabScrollSizing = .flexibleViewport
    static let usesSingleStripDropCoordinator = true
    static let usesAppKitDropBackstop = true
    static let usesPerItemTabDropTarget = true
    static let dropSurfaceActivation: DockListDropSurfaceActivation = .windowDragOrActiveDrag
    static let appKitDropSurfaceFillsTabPill = true
    static let dropTargetPlacement: DockListTabDropTargetPlacement = .stripContent
    static let dropTargetLiftStyle: DockListDropTargetLiftStyle = .liftedTab
    static let dropCoordinateSpace = "DockListTabsDropCoordinateSpace"

    static func pillTabLabels(pinboardNames: [String]) -> [String] {
        [historyLabel, snippetsLabel] + pinboardNames
    }
}

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
    @Namespace private var selectionNamespace

    var body: some View {
        HStack(spacing: 8) {
            tabPill
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
                    liveReorderTab: liveReorderTab(draggedID:target:),
                    handleDrop: handleDrop(_:on:),
                    runDropConfirmation: runDropConfirmation(on:)
                )
            )
            .overlay {
                if dropSurfaceIsActive {
                    DockListStripAppKitDropSurface(
                        tabFrames: tabDropFrames,
                        dropTargetSelector: $dropTargetSelector,
                        draggedTabID: $draggedTabID,
                        reduceMotion: reduceMotion,
                        liveReorderTab: liveReorderTab(draggedID:target:),
                        handleDrop: handleDrop(_:on:),
                        runDropConfirmation: runDropConfirmation(on:)
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
        }
    }

    private var dropSurfaceIsActive: Bool {
        DockListDropSurfaceState.isActive(
            draggedTabID: draggedTabID,
            activeDraggedItemID: model.activeDraggedItemID,
            windowDragIsActive: model.isDockDragSurfaceActive
        )
    }

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
                liveReorderTab: liveReorderTab(draggedID:target:),
                handleDrop: handleDrop(_:on:),
                runDropConfirmation: runDropConfirmation(on:)
            )
        )
        .onTapGesture {
            Task { await model.switchList(selector) }
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
            Capsule()
                .fill(MAYNTheme.tabSelectedFill)
                .overlay(Capsule().stroke(MAYNTheme.tabSelectedBorder, lineWidth: 1))
                .shadow(color: MAYNTheme.tabSelectedShadow, radius: 2, x: 0, y: 1)
                .matchedGeometryEffect(id: "dock-tab-selection", in: selectionNamespace)
        } else {
            Capsule()
                .fill(Color.clear)
        }
    }

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

struct DockListTabDropFrame: Equatable {
    let selector: DockListSelector
    let rect: CGRect
}

enum DockListTabDropResolver {
    private static let verticalTolerance: CGFloat = 12
    private static let nearestHorizontalTolerance: CGFloat = 24
    private static let appendAfterLastHorizontalTolerance: CGFloat = 80

    static func targetSelector(
        at location: CGPoint,
        in frames: [DockListTabDropFrame],
        requiresItemDropTarget: Bool
    ) -> DockListSelector? {
        guard !frames.isEmpty else { return nil }
        let candidates = requiresItemDropTarget ? frames.filter(\.acceptsItemDrop) : frames

        if let direct = candidates.first(where: { $0.hitRect.contains(location) }) {
            return direct.selector
        }

        if requiresItemDropTarget,
           frames.contains(where: { !$0.acceptsItemDrop && $0.hitRect.contains(location) })
        {
            return nil
        }

        guard let verticalRange = frames.verticalRange,
              location.y >= verticalRange.lowerBound - verticalTolerance,
              location.y <= verticalRange.upperBound + verticalTolerance
        else { return nil }

        let nearest = candidates.min { lhs, rhs in
            lhs.horizontalDistance(to: location.x) < rhs.horizontalDistance(to: location.x)
        }
        guard let nearest,
              nearest.horizontalDistance(to: location.x) <= nearestHorizontalTolerance
        else { return nil }
        return nearest.selector
    }

    static func reorderTarget(
        at location: CGPoint,
        in frames: [DockListTabDropFrame]
    ) -> DockListTabReorderTarget? {
        let pinboardFrames = frames.filter(\.isPinboard).sorted { $0.rect.minX < $1.rect.minX }
        guard !pinboardFrames.isEmpty else { return nil }

        if frames.contains(where: { !$0.isPinboard && $0.hitRect.contains(location) }) {
            return nil
        }

        guard let verticalRange = frames.verticalRange,
              location.y >= verticalRange.lowerBound - verticalTolerance,
              location.y <= verticalRange.upperBound + verticalTolerance
        else { return nil }

        if let direct = pinboardFrames.first(where: { $0.hitRect.contains(location) }),
           case let .pinboard(id) = direct.selector
        {
            return DockListTabReorderTarget(
                targetID: id,
                placement: location.x < direct.rect.midX ? .before : .after
            )
        }

        if let last = pinboardFrames.last,
           location.x > last.rect.maxX,
           location.x <= last.rect.maxX + appendAfterLastHorizontalTolerance,
           case let .pinboard(id) = last.selector
        {
            return DockListTabReorderTarget(targetID: id, placement: .after)
        }

        if let first = pinboardFrames.first,
           location.x < first.rect.minX,
           first.rect.minX - location.x <= nearestHorizontalTolerance,
           case let .pinboard(id) = first.selector
        {
            return DockListTabReorderTarget(targetID: id, placement: .before)
        }

        return nil
    }
}

enum DockListDropSurfaceState {
    static func isActive(
        draggedTabID: RecordID?,
        activeDraggedItemID: DockItem.ID?,
        windowDragIsActive: Bool
    ) -> Bool {
        draggedTabID != nil || activeDraggedItemID != nil || windowDragIsActive
    }
}

private struct DockListTabFrameReporter: View {
    let selector: DockListSelector

    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: DockListTabDropFramePreferenceKey.self,
                value: [
                    DockListTabDropFrame(
                        selector: selector,
                        rect: proxy.frame(in: .named(DockListTabsPresentation.dropCoordinateSpace))
                    )
                ]
            )
        }
    }
}

private struct DockListTabDropFramePreferenceKey: PreferenceKey {
    static var defaultValue: [DockListTabDropFrame] = []

    static func reduce(value: inout [DockListTabDropFrame], nextValue: () -> [DockListTabDropFrame]) {
        value.append(contentsOf: nextValue())
    }
}

private struct DockListStripDropDelegate: DropDelegate {
    let tabFrames: [DockListTabDropFrame]
    @Binding var dropTargetSelector: DockListSelector?
    @Binding var draggedTabID: RecordID?
    let reduceMotion: Bool
    let liveReorderTab: (RecordID, DockListTabReorderTarget) -> Void
    let handleDrop: ([String], DockListSelector) -> Bool
    let runDropConfirmation: (DockListSelector) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        !info.itemProviders(for: DockDragPayloadTypes.acceptedTypeIdentifiers).isEmpty &&
            resolvedTarget(for: info) != nil
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard updateDropTarget(for: info) != nil else { return nil }
        return DropProposal(operation: draggedTabID == nil ? .copy : .move)
    }

    func dropEntered(info: DropInfo) {
        _ = updateDropTarget(for: info)
    }

    func dropExited(info _: DropInfo) {
        if draggedTabID == nil {
            withAnimation(MAYNMotion.tabAnimation(reduceMotion: reduceMotion)) {
                dropTargetSelector = nil
            }
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: DockDragPayloadTypes.acceptedTypeIdentifiers)
        guard let target = resolvedTarget(for: info), !providers.isEmpty else {
            dropTargetSelector = nil
            draggedTabID = nil
            return false
        }
        if let draggedID = draggedTabID,
           let reorderTarget = resolvedReorderTarget(for: info),
           draggedID != reorderTarget.targetID
        {
            liveReorderTab(draggedID, reorderTarget)
        }

        DockDragPayloadLoader.strings(from: providers) { strings in
            let isTabReorder = strings.contains { DockTabDrag.decode($0) != nil }
            let accepted = handleDrop(strings, target)
            if accepted, !isTabReorder {
                runDropConfirmation(target)
            }
            dropTargetSelector = nil
        }
        return true
    }

    private func updateDropTarget(for info: DropInfo) -> DockListSelector? {
        let target = resolvedTarget(for: info)

        if let draggedID = draggedTabID,
           let reorderTarget = resolvedReorderTarget(for: info),
           draggedID != reorderTarget.targetID
        {
            liveReorderTab(draggedID, reorderTarget)
            dropTargetSelector = nil
            return target
        }

        guard draggedTabID == nil else { return target }
        withAnimation(MAYNMotion.tabAnimation(reduceMotion: reduceMotion)) {
            dropTargetSelector = target
        }
        return target
    }

    private func resolvedTarget(for info: DropInfo) -> DockListSelector? {
        if draggedTabID != nil {
            return resolvedReorderTarget(for: info)?.selector
        }
        return DockListTabDropResolver.targetSelector(
            at: info.location,
            in: tabFrames,
            requiresItemDropTarget: true
        )
    }

    private func resolvedReorderTarget(for info: DropInfo) -> DockListTabReorderTarget? {
        DockListTabDropResolver.reorderTarget(at: info.location, in: tabFrames)
    }
}

private struct DockListItemTabDropTarget: ViewModifier {
    let selector: DockListSelector
    @Binding var dropTargetSelector: DockListSelector?
    @Binding var draggedTabID: RecordID?
    let reduceMotion: Bool
    let liveReorderTab: (RecordID, DockListTabReorderTarget) -> Void
    let handleDrop: ([String], DockListSelector) -> Bool
    let runDropConfirmation: (DockListSelector) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if selector.acceptsItemDrop {
            content.onDrop(
                of: DockDragPayloadTypes.acceptedTypeIdentifiers,
                delegate: DockListItemTabDropDelegate(
                    selector: selector,
                    dropTargetSelector: $dropTargetSelector,
                    draggedTabID: $draggedTabID,
                    reduceMotion: reduceMotion,
                    liveReorderTab: liveReorderTab,
                    handleDrop: handleDrop,
                    runDropConfirmation: runDropConfirmation
                )
            )
        } else {
            content
        }
    }
}

private struct DockListItemTabDropDelegate: DropDelegate {
    let selector: DockListSelector
    @Binding var dropTargetSelector: DockListSelector?
    @Binding var draggedTabID: RecordID?
    let reduceMotion: Bool
    let liveReorderTab: (RecordID, DockListTabReorderTarget) -> Void
    let handleDrop: ([String], DockListSelector) -> Bool
    let runDropConfirmation: (DockListSelector) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        DockListItemTabDropPolicy.acceptsPerTabDrop(draggedTabID: draggedTabID) &&
            !info.itemProviders(for: DockDragPayloadTypes.acceptedTypeIdentifiers).isEmpty
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard DockListItemTabDropPolicy.acceptsPerTabDrop(draggedTabID: draggedTabID) else {
            return nil
        }
        guard !info.itemProviders(for: DockDragPayloadTypes.acceptedTypeIdentifiers).isEmpty else {
            return nil
        }
        updateDropTarget()
        return DropProposal(operation: draggedTabID == nil ? .copy : .move)
    }

    func dropEntered(info _: DropInfo) {
        guard DockListItemTabDropPolicy.acceptsPerTabDrop(draggedTabID: draggedTabID) else { return }
        updateDropTarget()
    }

    func dropExited(info _: DropInfo) {
        if draggedTabID == nil {
            withAnimation(MAYNMotion.tabAnimation(reduceMotion: reduceMotion)) {
                dropTargetSelector = nil
            }
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: DockDragPayloadTypes.acceptedTypeIdentifiers)
        guard DockListItemTabDropPolicy.acceptsPerTabDrop(draggedTabID: draggedTabID),
              !providers.isEmpty
        else {
            dropTargetSelector = nil
            draggedTabID = nil
            return false
        }

        DockDragPayloadLoader.strings(from: providers) { strings in
            let isTabReorder = strings.contains { DockTabDrag.decode($0) != nil }
            let accepted = handleDrop(strings, selector)
            if accepted, !isTabReorder {
                runDropConfirmation(selector)
            }
            dropTargetSelector = nil
            if !accepted {
                draggedTabID = nil
            }
        }
        return true
    }

    private func updateDropTarget() {
        guard DockListItemTabDropPolicy.acceptsPerTabDrop(draggedTabID: draggedTabID) else { return }
        withAnimation(MAYNMotion.tabAnimation(reduceMotion: reduceMotion)) {
            dropTargetSelector = selector
        }
    }
}

private struct DockListStripAppKitDropSurface: NSViewRepresentable {
    let tabFrames: [DockListTabDropFrame]
    @Binding var dropTargetSelector: DockListSelector?
    @Binding var draggedTabID: RecordID?
    let reduceMotion: Bool
    let liveReorderTab: (RecordID, DockListTabReorderTarget) -> Void
    let handleDrop: ([String], DockListSelector) -> Bool
    let runDropConfirmation: (DockListSelector) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> DropView {
        let view = DropView()
        view.coordinator = context.coordinator
        view.registerForDraggedTypes(DockDragPayloadTypes.acceptedPasteboardTypes)
        return view
    }

    func updateNSView(_ nsView: DropView, context: Context) {
        context.coordinator.parent = self
        nsView.coordinator = context.coordinator
        nsView.registerForDraggedTypes(DockDragPayloadTypes.acceptedPasteboardTypes)
    }

    final class Coordinator {
        var parent: DockListStripAppKitDropSurface

        init(_ parent: DockListStripAppKitDropSurface) {
            self.parent = parent
        }

        func updateDropTarget(for sender: NSDraggingInfo, location: CGPoint) -> NSDragOperation {
            guard hasSupportedPayload(sender),
                  let target = resolvedTarget(at: location)
            else {
                clearDropTargetIfNeeded()
                return []
            }

            if let draggedID = parent.draggedTabID,
               let reorderTarget = resolvedReorderTarget(at: location),
               draggedID != reorderTarget.targetID
            {
                parent.liveReorderTab(draggedID, reorderTarget)
                parent.dropTargetSelector = nil
                return .move
            }

            guard parent.draggedTabID == nil else { return .move }
            withAnimation(MAYNMotion.tabAnimation(reduceMotion: parent.reduceMotion)) {
                parent.dropTargetSelector = target
            }
            return .copy
        }

        func performDrop(for sender: NSDraggingInfo, location: CGPoint) -> Bool {
            guard hasSupportedPayload(sender),
                  let target = resolvedTarget(at: location)
            else {
                parent.dropTargetSelector = nil
                parent.draggedTabID = nil
                return false
            }
            if let draggedID = parent.draggedTabID,
               let reorderTarget = resolvedReorderTarget(at: location),
               draggedID != reorderTarget.targetID
            {
                parent.liveReorderTab(draggedID, reorderTarget)
            }

            let strings = pasteboardStrings(from: sender.draggingPasteboard)
            let isTabReorder = strings.contains { DockTabDrag.decode($0) != nil }
            let accepted = parent.handleDrop(strings, target)
            if accepted, !isTabReorder {
                parent.runDropConfirmation(target)
            }
            parent.dropTargetSelector = nil
            if !accepted {
                parent.draggedTabID = nil
            }
            return accepted
        }

        func clearDropTargetIfNeeded() {
            guard parent.draggedTabID == nil else { return }
            withAnimation(MAYNMotion.tabAnimation(reduceMotion: parent.reduceMotion)) {
                parent.dropTargetSelector = nil
            }
        }

        private func hasSupportedPayload(_ sender: NSDraggingInfo) -> Bool {
            sender.draggingPasteboard.availableType(
                from: DockDragPayloadTypes.acceptedPasteboardTypes
            ) != nil
        }

        private func resolvedTarget(at location: CGPoint) -> DockListSelector? {
            if parent.draggedTabID != nil {
                return resolvedReorderTarget(at: location)?.selector
            }
            return DockListTabDropResolver.targetSelector(
                at: location,
                in: parent.tabFrames,
                requiresItemDropTarget: true
            )
        }

        private func resolvedReorderTarget(at location: CGPoint) -> DockListTabReorderTarget? {
            DockListTabDropResolver.reorderTarget(
                at: location,
                in: parent.tabFrames
            )
        }

        private func pasteboardStrings(from pasteboard: NSPasteboard) -> [String] {
            var seen = Set<String>()
            return DockDragPayloadTypes.acceptedPasteboardTypes.compactMap { type in
                pasteboard.string(forType: type)
            }.filter { seen.insert($0).inserted }
        }
    }

    final class DropView: NSView {
        var coordinator: Coordinator?

        override var isFlipped: Bool { true }

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.backgroundColor = NSColor.clear.cgColor
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            nil
        }

        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
            coordinator?.updateDropTarget(for: sender, location: localLocation(for: sender)) ?? []
        }

        override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
            coordinator?.updateDropTarget(for: sender, location: localLocation(for: sender)) ?? []
        }

        override func draggingExited(_ sender: NSDraggingInfo?) {
            _ = sender
            coordinator?.clearDropTargetIfNeeded()
        }

        override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
            coordinator?.updateDropTarget(for: sender, location: localLocation(for: sender)) != []
        }

        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            coordinator?.performDrop(for: sender, location: localLocation(for: sender)) ?? false
        }

        private func localLocation(for sender: NSDraggingInfo) -> CGPoint {
            convert(sender.draggingLocation, from: nil)
        }
    }
}

private extension DockListTabDropFrame {
    var isPinboard: Bool {
        if case .pinboard = selector { return true }
        return false
    }

    var acceptsItemDrop: Bool {
        selector.acceptsItemDrop
    }

    var hitRect: CGRect {
        rect.insetBy(dx: -3, dy: -4)
    }

    func horizontalDistance(to x: CGFloat) -> CGFloat {
        if x < rect.minX { return rect.minX - x }
        if x > rect.maxX { return x - rect.maxX }
        return 0
    }
}

private extension DockListSelector {
    var acceptsItemDrop: Bool {
        switch self {
        case .snippets, .pinboard:
            return true
        case .history:
            return false
        }
    }
}

private extension [DockListTabDropFrame] {
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
