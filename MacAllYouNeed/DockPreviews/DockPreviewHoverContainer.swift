import AppKit
import SwiftUI

enum DockPreviewFlowItem: Hashable, Identifiable {
    case embedded
    case window(Int)

    var id: String {
        switch self {
        case .embedded: "embedded"
        case let .window(index): "window-\(index)"
        }
    }
}

/// Dock hover preview surface (DockDoor `WindowPreviewHoverContainer`).
struct DockPreviewHoverContainer: View {
    @Bindable var state: DockPreviewStateCoordinator
    let onSelect: (DockPreviewWindowEntry) -> Void
    let onMouseInPanel: (Bool) -> Void
    let onDismissRequest: () -> Void
    let onDismissPreservePendingShow: () -> Void
    let shouldKeepOpen: () -> Bool
    var dockItemToken: UInt?
    var onMinimizeAll: (() -> Void)?
    var onQuitApp: (() -> Void)?

    @ObservedObject private var liveCapture = DockPreviewLiveCaptureManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrolledFromStart = false
    @State private var hoveringAppIcon = false
    @State private var edgeScrollDirection: CGFloat = 0
    @State private var edgeScrollTimer: Timer?

    private var screen: NSScreen {
        NSScreen.screens.first { $0.frame.contains(state.anchorRect.origin) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    /// DockDoor: without Screen Recording, always use compact list (not broken grid cards).
    private var usesCompactList: Bool {
        if state.presentationMode != .fullPreview { return true }
        if !DockPreviewPermissionGate.screenRecordingGranted() { return true }
        if state.settings.compactModeThreshold > 0,
           state.windows.count >= state.settings.compactModeThreshold
        {
            return true
        }
        return false
    }

    private var showScreenRecordingBanner: Bool {
        usesCompactList
            && !DockPreviewPermissionGate.screenRecordingGranted()
            && !state.isWindowSwitcherActive
    }

    private var orientationIsHorizontal: Bool {
        if state.isWindowSwitcherActive { return true }
        return state.dockEdge == .bottom || state.mode == .cmdTab
    }

    private var panelOpacity: Double {
        state.settings.hideHoverContainerBackground ? 0 : state.settings.panelBackgroundOpacity
    }

    var body: some View {
        DockPreviewDismissalContainer(
            dockItemToken: dockItemToken,
            anchorRect: state.anchorRect,
            onMouseInPanel: onMouseInPanel,
            onDismissRequest: onDismissRequest,
            onDismissPreservePendingShow: onDismissPreservePendingShow,
            shouldKeepOpen: shouldKeepOpen,
            shouldSkipFadeOut: { state.isWindowSwitcherActive || state.mode == .cmdTab }
        ) {
            DockPreviewBaseHoverContainer(
                screen: screen,
                backgroundOpacity: panelOpacity,
                background: state.appearance.background,
                paddingMultiplier: CGFloat(state.settings.globalPaddingMultiplier),
                uniformCardRadius: state.settings.uniformCardRadius
            ) {
                ZStack(alignment: .topLeading) {
                    windowGridContent
                    if state.appearance.showAppHeader, !usesCompactList, !state.isWindowSwitcherActive {
                        appHeader
                            .padding(.top, 12)
                            .padding(.leading, 20)
                    }
                }
                .padding(DockPreviewHoverPadding.contentInner)
            }
            .dockPreviewTrackpadSwipe { delta in
                if delta > 12 { state.selectNext(delta: 1) }
                else if delta < -12 { state.selectNext(delta: -1) }
            }
        }
        .onAppear {
            if state.enableLivePreview {
                DockPreviewLiveCaptureManager.shared.panelOpened()
            }
        }
        .onDisappear {
            edgeScrollTimer?.invalidate()
            if state.enableLivePreview {
                DockPreviewLiveCaptureManager.shared.panelClosed()
            }
        }
    }

    private var appHeader: some View {
        HStack(spacing: 6) {
            if let icon = state.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
            }
            Text(state.appName)
                .font(.system(size: 14, weight: .semibold))
                .shadow(radius: 2)
            Spacer()
            if hoveringAppIcon, let onMinimizeAll {
                Button("Minimize All", action: onMinimizeAll)
                    .font(.caption)
                    .buttonStyle(.plain)
            }
        }
        .onHover { hoveringAppIcon = $0 }
    }

    @ViewBuilder
    private var windowGridContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showScreenRecordingBanner {
                DockPreviewScreenRecordingBanner {
                    DockPreviewPermissionGate.requestScreenRecordingIfNeeded()
                }
            }
            if state.isWindowSwitcherActive, !state.settings.detachedSwitcherSearch {
                DockPreviewSearchBar(query: $state.searchQuery)
                    .onChange(of: state.searchQuery) { _, _ in
                        state.clampSelectionToFilteredSearch()
                    }
            }
            if state.isWindowlessPlaceholder, let onQuitApp {
                DockPreviewWindowlessCard(onQuit: onQuitApp)
            }
            if usesCompactList {
                DockPreviewCompactList(state: state, onSelect: onSelect)
            } else {
                flowStackContent
            }
        }
        .padding(.top, state.appearance.showAppHeader && !usesCompactList && !state.isWindowSwitcherActive ? 28 : 0)
    }

    @ViewBuilder
    private var flowStackContent: some View {
        let axis: Axis = orientationIsHorizontal ? .horizontal : .vertical
        let scrollAxis: Axis.Set = orientationIsHorizontal ? .horizontal : .vertical
        ScrollViewReader { scrollProxy in
            ScrollView(scrollAxis, showsIndicators: false) {
                buildFlowStack
                    .background {
                        GeometryReader { geometry in
                            let offset = orientationIsHorizontal
                                ? geometry.frame(in: .named("dockPreviewScroll")).minX
                                : geometry.frame(in: .named("dockPreviewScroll")).minY
                            Color.clear.preference(key: DockPreviewScrollOffsetKey.self, value: offset)
                        }
                    }
            }
            .coordinateSpace(name: "dockPreviewScroll")
            .onPreferenceChange(DockPreviewScrollOffsetKey.self) { offset in
                scrolledFromStart = offset < -4
            }
            .dockPreviewScrollFade(
                axis: axis,
                fadeLength: 20,
                disableLeading: scrolledFromStart
            )
            .onChange(of: state.selectedIndex) { _, newIndex in
                guard state.shouldScrollToIndex, newIndex >= 0, newIndex < state.windows.count else { return }
                let entry = state.windows[newIndex]
                withAnimation(MAYNMotion.hoverAnimation(reduceMotion: reduceMotion)) {
                    scrollProxy.scrollTo(entry.id, anchor: .center)
                }
            }
            .onContinuousHover { phase in
                guard state.isWindowSwitcherActive else { return }
                if case let .active(location) = phase {
                    updateEdgeScroll(at: location, scrollProxy: scrollProxy)
                } else {
                    stopEdgeScroll()
                }
            }
        }
        .animation(
            MAYNMotion.hoverAnimation(reduceMotion: reduceMotion),
            value: state.windows.count
        )
    }

    private func updateEdgeScroll(at location: CGPoint, scrollProxy: ScrollViewProxy) {
        let threshold: CGFloat = 28
        let direction: CGFloat
        if orientationIsHorizontal {
            direction = location.x < threshold ? -1 : (location.x > 200 - threshold ? 1 : 0)
        } else {
            direction = location.y < threshold ? -1 : (location.y > 200 - threshold ? 1 : 0)
        }
        guard direction != 0 else {
            stopEdgeScroll()
            return
        }
        edgeScrollDirection = direction
        edgeScrollTimer?.invalidate()
        edgeScrollTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            Task { @MainActor in
                let delta = Int(edgeScrollDirection)
                state.selectNext(delta: delta)
                guard state.selectedIndex < state.windows.count else { return }
                scrollProxy.scrollTo(state.windows[state.selectedIndex].id, anchor: .center)
            }
        }
    }

    private func stopEdgeScroll() {
        edgeScrollTimer?.invalidate()
        edgeScrollTimer = nil
        edgeScrollDirection = 0
    }

    @ViewBuilder
    private var buildFlowStack: some View {
        let items = flowItems()
        let horizontal = orientationIsHorizontal
        let chunks = DockPreviewDimensionEngine.chunkArray(
            items: items,
            isHorizontal: horizontal,
            maxColumns: state.dimensionState.gridColumns,
            maxRows: state.dimensionState.gridRows,
            reverse: !state.isWindowSwitcherActive && (state.dockEdge == .bottom || state.dockEdge == .right)
        )
        if horizontal {
            VStack(alignment: .leading, spacing: DockPreviewHoverPadding.itemSpacing) {
                ForEach(Array(chunks.enumerated()), id: \.offset) { _, chunk in
                    HStack(spacing: DockPreviewHoverPadding.itemSpacing) {
                        ForEach(chunk, id: \.self) { item in
                            flowItemView(item)
                        }
                    }
                }
            }
        } else {
            HStack(alignment: .top, spacing: DockPreviewHoverPadding.itemSpacing) {
                ForEach(Array(chunks.enumerated()), id: \.offset) { _, chunk in
                    VStack(spacing: DockPreviewHoverPadding.itemSpacing) {
                        ForEach(chunk, id: \.self) { item in
                            flowItemView(item)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func flowItemView(_ item: DockPreviewFlowItem) -> some View {
        switch item {
        case .embedded:
            embeddedContent
        case let .window(index):
            if index < state.windows.count {
                let entry = state.windows[index]
                let dimensions = state.dimensionState.perWindow[index]
                    ?? DockPreviewWindowDimensions(
                        size: CGSize(
                            width: CGFloat(state.settings.previewCardWidth),
                            height: CGFloat(state.settings.previewCardHeight)
                        ),
                        maxDimensions: CGSize(
                            width: CGFloat(state.settings.previewCardWidth),
                            height: CGFloat(state.settings.previewCardHeight)
                        )
                    )
                DockPreviewWindowCard(
                    entry: entry,
                    dimensions: dimensions,
                    mode: state.presentationMode,
                    settings: state.settings,
                    appearance: state.appearance,
                    dockEdge: state.dockEdge,
                    isWindowSwitcher: state.isWindowSwitcherActive,
                    liveImage: state.enableLivePreview ? liveCapture.frames[entry.id] : nil,
                    isSelected: index == state.selectedIndex,
                    isActiveWindow: entry.id == state.focusedWindowID,
                    reduceMotion: reduceMotion,
                    onSelect: { onSelect(entry) },
                    onClose: { onSelect(entry) },
                    onHoverIndex: { hovering in
                        guard state.isWindowSwitcherActive, hovering else { return }
                        state.setIndex(to: index, shouldScroll: false)
                    }
                )
                .id(entry.id)
            }
        }
    }

    @ViewBuilder
    private var embeddedContent: some View {
        switch state.embeddedContent {
        case .none:
            EmptyView()
        case let .folder(title, url):
            DockFolderWidgetView(title: title, url: url, showHidden: state.settings.folderShowHiddenFiles)
        case .media:
            DockMediaWidgetView()
        case .calendar:
            DockCalendarWidgetView()
        }
    }

    private func flowItems() -> [DockPreviewFlowItem] {
        var items: [DockPreviewFlowItem] = []
        if state.embeddedContent != .none {
            items.append(.embedded)
        }
        for index in displayableWindowIndices() {
            items.append(.window(index))
        }
        return items
    }

    private func displayableWindowIndices() -> [Int] {
        let filtered = state.filteredWindowIndices()
        let hasRealWindows = state.windows.contains { !$0.title.isEmpty && $0.title != "No open windows" }
        guard hasRealWindows else { return filtered }
        return filtered.filter { state.windows[$0].title.isEmpty == false }
    }
}

private struct DockPreviewScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
