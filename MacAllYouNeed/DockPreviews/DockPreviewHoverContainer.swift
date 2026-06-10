import AppKit
import Carbon.HIToolbox
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
    var onMinimizeAll: (() -> Void)?
    var onCloseAll: (() -> Void)?
    var onQuitApp: (() -> Void)?

    @ObservedObject private var liveCapture = DockPreviewLiveCaptureManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrolledFromStart = false
    @State private var hoveringAppIcon = false
    @State private var edgeScrollDirection: CGFloat = 0
    @State private var edgeScrollTimer: Timer?
    @State private var edgeScrollHoverSize: CGSize = .zero
    @State private var cachedScrollView: NSScrollView?

    private var enableMouseHoverInSwitcher: Bool {
        DockHubSettingsStore.load().switcher.enableMouseHover
    }

    private var mouseHoverAutoScrollSpeed: CGFloat {
        CGFloat(DockHubSettingsStore.load().switcher.mouseHoverAutoScrollSpeed)
    }

    private func handleHoverIndexChange(_ hoveredIndex: Int?) {
        guard enableMouseHoverInSwitcher else { return }
        guard let hoveredIndex else { return }
        guard hoveredIndex != state.selectedIndex else { return }

        if !state.hasMovedSinceOpen {
            let screenLocation = NSEvent.mouseLocation

            if state.initialHoverLocation == nil {
                state.initialHoverLocation = screenLocation
                return
            }

            if let initial = state.initialHoverLocation {
                let distance = hypot(screenLocation.x - initial.x, screenLocation.y - initial.y)
                if distance > 1 {
                    state.hasMovedSinceOpen = true
                } else {
                    return
                }
            }
        }

        state.setIndex(to: hoveredIndex, shouldScroll: false)
    }

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

    private var headerTopOuterPadding: CGFloat {
        guard state.appearance.showAppHeader,
              !state.windows.isEmpty,
              !state.isWindowlessPlaceholder,
              !usesCompactList,
              !state.isWindowSwitcherActive,
              state.appearance.appNameStyle == .popover
        else { return 0 }
        return 30
    }

    private var cmdTabCycleKeyLabel: String {
        let hub = DockHubSettingsStore.load()
        let code = hub.cmdTab.cycleKeyCode == 0 ? UInt16(kVK_Tab) : hub.cmdTab.cycleKeyCode
        switch code {
        case UInt16(kVK_Tab): return "Tab"
        case UInt16(kVK_Space): return "Space"
        default: return "Cycle key"
        }
    }

    private func liveImage(for entry: DockPreviewWindowEntry) -> CGImage? {
        guard state.enableLivePreview else { return nil }
        if state.isWindowSwitcherActive {
            let hub = DockHubSettingsStore.load()
            let ids = DockPreviewLiveCaptureScope.windowIDs(
                windows: state.windows,
                selectedIndex: state.selectedIndex,
                scope: hub.advanced.switcherLivePreviewScope
            )
            guard ids.contains(entry.id) else { return nil }
        }
        return liveCapture.frames[entry.id]
    }

    private var headerTopInnerPadding: CGFloat {
        guard state.appearance.showAppHeader,
              !usesCompactList,
              !state.isWindowSwitcherActive,
              state.appearance.appNameStyle == .default
        else { return 0 }
        // DockDoor reserves 25pt; add a few points so the title row clears the first card.
        return 33
    }

    var body: some View {
        DockPreviewDismissalContainer(
            dockItemElement: state.dismissalAnchorDockItem,
            onMouseInPanel: onMouseInPanel,
            onDismissRequest: onDismissRequest,
            onDismissPreservePendingShow: onDismissPreservePendingShow,
            shouldSkipFadeOut: { state.isWindowSwitcherActive || state.mode == .cmdTab }
        ) {
            DockPreviewBaseHoverContainer(
                screen: screen,
                backgroundOpacity: panelOpacity,
                background: state.appearance.background,
                paddingMultiplier: CGFloat(state.settings.globalPaddingMultiplier),
                uniformCardRadius: state.settings.uniformCardRadius
            ) {
                ZStack {
                    windowGridContent
                    if state.mode == .cmdTab, state.showCmdTabFocusHint {
                        DockCmdTabFocusOverlayView(cycleKeyLabel: cmdTabCycleKeyLabel)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
        .id(state.dockItemToken ?? 0)
        .padding(.top, headerTopOuterPadding)
        .onAppear {
            if state.enableLivePreview {
                DockPreviewLiveCaptureManager.shared.panelOpened()
            }
        }
        .onDisappear {
            stopEdgeScroll()
            if state.enableLivePreview {
                DockPreviewLiveCaptureManager.shared.panelClosed()
            }
        }
        .onChange(of: state.isWindowSwitcherActive) { _, isActive in
            if !isActive {
                state.searchQuery = ""
                stopEdgeScroll()
            }
        }
        .dockPreviewTrackpadGestures(
            swipeThreshold: CGFloat(DockHubSettingsStore.load().gestures.gestureSwipeThreshold),
            onSwipeUp: { handlePreviewSwipe(isUp: true) },
            onSwipeDown: { handlePreviewSwipe(isUp: false) },
            onSwipeLeft: { handlePreviewSwipe(isTowardsDock: true) },
            onSwipeRight: { handlePreviewSwipe(isTowardsDock: false) }
        )
    }

    private func handlePreviewSwipe(isUp: Bool = false, isTowardsDock: Bool = false) {
        let hub = DockHubSettingsStore.load()
        let gestures = hub.gestures
        guard state.selectedIndex >= 0, state.selectedIndex < state.windows.count else {
            if state.isWindowSwitcherActive, gestures.enableSwitcherGestures {
                let action = isUp ? gestures.switcherSwipeUpAction : gestures.switcherSwipeDownAction
                applySwipeToSelected(action)
            }
            return
        }
        if state.isWindowSwitcherActive, gestures.enableSwitcherGestures {
            let action = isUp ? gestures.switcherSwipeUpAction : gestures.switcherSwipeDownAction
            applySwipeToSelected(action)
            return
        }
        guard gestures.enableDockPreviewGestures else { return }
        let towardsDock: Bool
        switch state.dockEdge {
        case .bottom: towardsDock = isTowardsDock
        case .left: towardsDock = !isTowardsDock
        case .right: towardsDock = isTowardsDock
        }
        let action = towardsDock ? gestures.swipeTowardsDockAction : gestures.swipeAwayFromDockAction
        applySwipeToSelected(action)
    }

    private func applySwipeToSelected(_ action: DockWindowSwipeAction) {
        guard state.selectedIndex >= 0, state.selectedIndex < state.windows.count else { return }
        let entry = state.windows[state.selectedIndex]
        DockPreviewWindowActions.applySwipe(action, entry: entry)
    }

    @ViewBuilder
    private var appHeader: some View {
        switch state.appearance.appNameStyle {
        case .default:
            defaultAppHeader
        case .shadowed:
            shadowedAppHeader
        case .popover:
            popoverAppHeader
        }
    }

    private var defaultAppHeader: some View {
        HStack(spacing: 6) {
            appIconView
            Text(state.appName)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
                .lineLimit(1)
            massActionButtons
                .padding(.leading, 4)
        }
        .contentShape(Rectangle())
        .onHover { hoveringAppIcon = $0 }
        .shadow(radius: 2)
        .padding(.top, 12)
        .padding(.leading, 20)
    }

    private var shadowedAppHeader: some View {
        HStack(spacing: 2) {
            HStack(spacing: 6) {
                appIconView
                Text(state.appName)
                    .font(.subheadline).fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .shadow(radius: 2)
                    .background(
                        Color.clear
                            .background(.ultraThinMaterial)
                            .mask(
                                Ellipse()
                                    .fill(
                                        LinearGradient(
                                            colors: [.white.opacity(1.0), .white.opacity(0.35)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                            )
                            .blur(radius: 5)
                    )
            }
            .contentShape(Rectangle())
            massActionButtons
                .padding(.leading, 4)
        }
        .contentShape(Rectangle())
        .onHover { hoveringAppIcon = $0 }
        .padding(EdgeInsets(top: -11.5, leading: 15, bottom: -1.5, trailing: 1.5))
    }

    private var popoverAppHeader: some View {
        HStack {
            Spacer()
            HStack(alignment: .center, spacing: 6) {
                appIconView
                Text(state.appName)
                    .font(.subheadline).fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .dockPreviewDockStyle(
                backgroundOpacity: panelOpacity,
                appearance: state.appearance.background,
                cornerRadius: 10
            )
            Spacer()
        }
        .onHover { hoveringAppIcon = $0 }
        .offset(y: -30)
    }

    @ViewBuilder
    private var appIconView: some View {
        if let icon = state.appIcon {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
        }
    }

    @ViewBuilder
    private var massActionButtons: some View {
        if hoveringAppIcon, state.appearance.showMassActionButtons {
            if let onCloseAll {
                Button("Close All", action: onCloseAll)
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            if let onMinimizeAll {
                Button("Minimize All", action: onMinimizeAll)
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Folder (and other widget-only) previews have no window cards — never route them through compact list.
    private var usesEmbeddedOnlyLayout: Bool {
        state.embeddedContent != .none && state.windows.isEmpty
    }

    @ViewBuilder
    private var windowGridContent: some View {
        if usesEmbeddedOnlyLayout {
            embeddedContent
                .dockPreviewGlobalPadding(
                    DockPreviewHoverPadding.contentInner,
                    multiplier: CGFloat(state.settings.globalPaddingMultiplier)
                )
        } else if showScreenRecordingBanner || state.isWindowlessPlaceholder {
            VStack(alignment: .leading, spacing: 12) {
                if showScreenRecordingBanner {
                    DockPreviewScreenRecordingBanner {
                        DockPreviewPermissionGate.requestScreenRecordingIfNeeded()
                    }
                }
                if state.isWindowlessPlaceholder, let onQuitApp {
                    DockPreviewWindowlessCard(onQuit: onQuitApp)
                }
            }
            .dockPreviewGlobalPadding(
                DockPreviewHoverPadding.contentInner,
                multiplier: CGFloat(state.settings.globalPaddingMultiplier)
            )
        } else if state.isWindowSwitcherActive,
                  DockHubSettingsStore.load().switcher.switcherLayoutStyle == .verticalList {
            DockSwitcherVerticalListView(
                state: state,
                showSearch: DockHubSettingsStore.load().switcher.enableSearch,
                onSelect: onSelect,
                onHoverIndex: handleHoverIndexChange
            )
            .dockPreviewGlobalPadding(
                DockPreviewHoverPadding.contentInner,
                multiplier: CGFloat(state.settings.globalPaddingMultiplier)
            )
        } else if usesCompactList {
            DockPreviewCompactList(
                state: state,
                onSelect: onSelect,
                onHoverIndex: state.isWindowSwitcherActive ? handleHoverIndexChange : nil
            )
                .dockPreviewGlobalPadding(
                    DockPreviewHoverPadding.contentInner,
                    multiplier: CGFloat(state.settings.globalPaddingMultiplier)
                )
        } else {
            flowStackContent
        }
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
            .padding(.top, headerTopInnerPadding)
            .overlay(alignment: state.appearance.appNameStyle == .popover ? .top : .topLeading) {
                if state.appearance.showAppHeader,
                   !usesCompactList,
                   !state.isWindowSwitcherActive,
                   !state.windows.isEmpty,
                   !state.isWindowlessPlaceholder
                {
                    appHeader
                }
            }
            .onChange(of: state.selectedIndex) { _, newIndex in
                guard state.shouldScrollToIndex, newIndex >= 0, newIndex < state.windows.count else { return }
                let entry = state.windows[newIndex]
                withAnimation(MAYNMotion.hoverAnimation(reduceMotion: reduceMotion)) {
                    scrollProxy.scrollTo(entry.id, anchor: .center)
                }
            }
            .onContinuousHover { phase in
                guard enableMouseHoverInSwitcher, state.isWindowSwitcherActive else { return }
                switch phase {
                case let .active(location):
                    handleEdgeScrollHover(at: location, isHorizontal: orientationIsHorizontal)
                case .ended:
                    stopEdgeScroll()
                }
            }
            .background {
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { edgeScrollHoverSize = geometry.size }
                        .onChange(of: geometry.size) { _, newSize in
                            edgeScrollHoverSize = newSize
                        }
                }
            }
        }
        .padding(2)
        .animation(
            state.appearance.showAnimations ? .smooth(duration: 0.1) : nil,
            value: state.windows.count
        )
    }

    private func handleEdgeScrollHover(at location: CGPoint, isHorizontal: Bool) {
        let edgeSize: CGFloat = 50
        let toolbarExclusion: CGFloat = 46
        let topExclusion = state.appearance.controlPosition.showsOnTop ? toolbarExclusion : 0
        let bottomExclusion = state.appearance.controlPosition.showsOnBottom ? toolbarExclusion : 0
        let width = edgeScrollHoverSize.width
        let height = edgeScrollHoverSize.height

        guard width > 0, height > 0 else {
            stopEdgeScroll()
            return
        }

        guard location.y >= topExclusion, location.y <= height - bottomExclusion else {
            stopEdgeScroll()
            return
        }

        if isHorizontal {
            if location.x <= edgeSize {
                startEdgeScroll(direction: -1, isHorizontal: true)
            } else if location.x >= width - edgeSize {
                startEdgeScroll(direction: 1, isHorizontal: true)
            } else {
                stopEdgeScroll()
            }
        } else {
            if location.y <= topExclusion + edgeSize {
                startEdgeScroll(direction: -1, isHorizontal: false)
            } else if location.y >= height - bottomExclusion - edgeSize {
                startEdgeScroll(direction: 1, isHorizontal: false)
            } else {
                stopEdgeScroll()
            }
        }
    }

    private func startEdgeScroll(direction: CGFloat, isHorizontal: Bool) {
        edgeScrollDirection = direction
        guard edgeScrollTimer == nil else { return }

        if cachedScrollView == nil || cachedScrollView?.window == nil {
            if let window = NSApp.windows.first(where: { $0.isVisible && $0.title.isEmpty }) {
                cachedScrollView = findScrollView(in: window.contentView)
            }
        }

        edgeScrollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
            Task { @MainActor in
                smoothScrollBy(direction: edgeScrollDirection, isHorizontal: isHorizontal)
            }
        }
    }

    private func smoothScrollBy(direction: CGFloat, isHorizontal: Bool) {
        guard let scrollView = cachedScrollView,
              let documentView = scrollView.documentView
        else { return }

        let scrollAmount = mouseHoverAutoScrollSpeed * direction
        let clipView = scrollView.contentView
        var newOrigin = clipView.bounds.origin

        if isHorizontal {
            newOrigin.x += scrollAmount
            newOrigin.x = max(0, min(newOrigin.x, documentView.frame.width - clipView.bounds.width))
        } else {
            newOrigin.y += scrollAmount
            newOrigin.y = max(0, min(newOrigin.y, documentView.frame.height - clipView.bounds.height))
        }

        clipView.setBoundsOrigin(newOrigin)
    }

    private func findScrollView(in view: NSView?) -> NSScrollView? {
        guard let view else { return nil }
        if let scrollView = view as? NSScrollView {
            return scrollView
        }
        for subview in view.subviews {
            if let found = findScrollView(in: subview) {
                return found
            }
        }
        return nil
    }

    private func stopEdgeScroll() {
        edgeScrollTimer?.invalidate()
        edgeScrollTimer = nil
        edgeScrollDirection = 0
        cachedScrollView = nil
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
            .dockPreviewGlobalPadding(
                DockPreviewHoverPadding.contentInner,
                multiplier: CGFloat(state.settings.globalPaddingMultiplier)
            )
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
            .dockPreviewGlobalPadding(
                DockPreviewHoverPadding.contentInner,
                multiplier: CGFloat(state.settings.globalPaddingMultiplier)
            )
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
                    liveImage: liveImage(for: entry),
                    isSelected: index == state.selectedIndex,
                    isActiveWindow: entry.id == state.focusedWindowID,
                    reduceMotion: reduceMotion,
                    enableWindowDrag: !state.isWindowSwitcherActive && state.presentationMode == .fullPreview,
                    onSelect: { onSelect(entry) },
                    onClose: { onSelect(entry) },
                    onHoverIndex: { hovering in
                        guard state.isWindowSwitcherActive else { return }
                        handleHoverIndexChange(hovering ? index : nil)
                    },
                    middleClickAction: DockHubSettingsStore.load().gestures.middleClickAction
                )
                .dockPreviewAeroShake(
                    enabled: DockHubSettingsStore.load().gestures.enableDockPreviewGestures,
                    action: DockHubSettingsStore.load().gestures.aeroShakeAction,
                    entries: state.windows,
                    selectedIndex: state.selectedIndex
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
            DockFolderWidgetView(
                title: title,
                url: url,
                showHidden: state.settings.folderShowHiddenFiles,
                onDismissPreview: onDismissRequest
            )
        case .media:
            DockMediaWidgetView(
                compact: false,
                showLyrics: true,
                bundleIdentifier: state.bundleIdentifier
            )
                .dockPreviewPinnable(
                    appName: state.appName,
                    bundleIdentifier: state.bundleIdentifier ?? "",
                    type: .media,
                    enablePinning: DockHubSettingsStore.load().widgets.enablePinning,
                    onPin: onDismissRequest
                )
                .dockPreviewMediaVolumeScroll()
        case .calendar:
            DockCalendarWidgetView()
                .dockPreviewPinnable(
                    appName: state.appName,
                    bundleIdentifier: state.bundleIdentifier ?? "",
                    type: .calendar,
                    enablePinning: DockHubSettingsStore.load().widgets.enablePinning,
                    onPin: onDismissRequest
                )
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
