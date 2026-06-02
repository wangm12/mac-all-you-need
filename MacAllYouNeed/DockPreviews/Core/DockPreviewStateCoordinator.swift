import AppKit
import CoreGraphics
import Foundation
import Observation

enum DockPreviewPresentationMode: Equatable {
    case dockHover
    case windowSwitcher
    case cmdTab
}

enum DockEmbeddedContent: Equatable {
    case none
    case folder(title: String, url: URL)
    case media
    case calendar
}

/// Shared window list + selection for hover panel and switcher (DockDoor `PreviewStateCoordinator` subset).
@MainActor
@Observable
final class DockPreviewStateCoordinator {
    var windows: [DockPreviewWindowEntry] = []
    var selectedIndex: Int = -1
    var mode: DockPreviewPresentationMode = .dockHover
    var appName: String = ""
    var appIcon: NSImage?
    var anchorRect: CGRect = .zero
    var dockEdge: DockPreviewPanelGeometry.DockEdge = .bottom
    var dimensionState = DockPreviewDimensionEngine.DimensionState()
    var settings: DockPreviewSettings = .default
    var presentationMode: DockPreviewPermissionGate.Mode = .titlesOnly
    var enableLivePreview: Bool = false
    var embeddedContent: DockEmbeddedContent = .none
    var expectedContentSize: CGSize = .zero
    var focusedWindowID: CGWindowID?
    var hasMovedSinceOpen = false
    var initialHoverLocation: CGPoint?
    var shouldScrollToIndex = true
    var searchQuery: String = ""
    var appearance = DockPreviewAppearanceContext.dockHover()
    /// Pinned at panel open for inactivity dismiss — not updated on icon switch (DockDoor `MouseTrackingNSView`).
    var dismissalAnchorDockItem: AXUIElement?
    var dockItemToken: UInt?
    var bundleIdentifier: String?
    var showCmdTabFocusHint: Bool = false

    var onFrameRefreshNeeded: (() -> Void)?

    var isWindowSwitcherActive: Bool { mode == .windowSwitcher }

    func recomputeAndPublishDimensions(panelSize: CGSize? = nil, screen: NSScreen? = nil) {
        let screen = screen ?? NSScreen.screens.first { $0.frame.contains(anchorRect.origin) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
        let referenceSize = panelSize ?? CGSize(
            width: CGFloat(settings.previewCardWidth),
            height: CGFloat(settings.previewCardHeight)
        )
        dimensionState = DockPreviewDimensionEngine.recompute(
            entries: windows,
            dockEdge: dockEdge,
            screen: screen,
            settings: settings,
            panelSize: referenceSize,
            isWindowSwitcher: isWindowSwitcherActive
        )
        refreshFocusedWindowID()
        updateExpectedContentSize()
    }

    func refreshFocusedWindowID() {
        guard let front = NSWorkspace.shared.frontmostApplication else {
            focusedWindowID = nil
            return
        }
        let pid = front.processIdentifier
        let appWindows = windows.filter { $0.pid == pid }
        guard !appWindows.isEmpty else {
            focusedWindowID = nil
            return
        }
        focusedWindowID = DockAXHelpers.focusedWindowID(
            for: pid,
            among: appWindows.map(\.id)
        )
    }

    private func updateExpectedContentSize() {
        let compact = settings.compactModeThreshold > 0 && windows.count >= settings.compactModeThreshold
        guard settings.allowDynamicImageSizing, !compact, presentationMode == .fullPreview else {
            expectedContentSize = .zero
            return
        }
        let minimumItemWidth: CGFloat = if isWindowSwitcherActive {
            min(
                dimensionState.overallMax.x,
                DockPreviewDimensionEngine.dynamicSwitcherMinimumCardWidth
            )
        } else {
            0
        }
        expectedContentSize = DockPreviewDimensionEngine.computeExpectedContentSize(
            dimensionState: dimensionState,
            windowCount: windows.count,
            dockEdge: dockEdge,
            hasEmbedded: embeddedContent != .none,
            isWindowSwitcher: isWindowSwitcherActive,
            globalPaddingMultiplier: CGFloat(settings.globalPaddingMultiplier),
            fillToLimit: isWindowSwitcherActive && settings.appearanceOptions.switcherScrollVertical,
            minimumItemWidth: minimumItemWidth
        )
    }

    @discardableResult
    func setWindows(_ entries: [DockPreviewWindowEntry], preserveSelection: Bool = true) -> Bool {
        let oldIDs = windows.map(\.id)
        let newIDs = entries.map(\.id)
        guard oldIDs != newIDs || windows != entries else { return false }
        let previousID = windows.indices.contains(selectedIndex) ? windows[selectedIndex].id : nil
        let previousThumbs = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0.thumbnail) })
        windows = entries.map { entry in
            var merged = entry
            if merged.thumbnail == nil, let thumb = previousThumbs[entry.id] {
                merged.thumbnail = thumb
            }
            return merged
        }
        if preserveSelection, let previousID, let idx = entries.firstIndex(where: { $0.id == previousID }) {
            selectedIndex = idx
        } else {
            if mode == .dockHover {
                selectedIndex = -1
            } else {
                selectedIndex = entries.isEmpty ? 0 : min(selectedIndex, entries.count - 1)
            }
        }
        recomputeAndPublishDimensions()
        onFrameRefreshNeeded?()
        return true
    }

    @discardableResult
    func mergeWindows(_ entries: [DockPreviewWindowEntry]) -> Bool {
        guard !windows.isEmpty else {
            return setWindows(entries, preserveSelection: false)
        }
        let freshByID = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let freshIDs = Set(freshByID.keys)
        let existingIDs = Set(windows.map(\.id))
        var changed = false
        let previousCount = windows.count

        for index in windows.indices {
            let windowID = windows[index].id
            guard let fresh = freshByID[windowID] else { continue }
            let merged = fresh.mergingThumbnail(from: windows[index])
            if windows[index] != merged {
                windows[index] = merged
                changed = true
            }
        }
        for entry in entries where !existingIDs.contains(entry.id) {
            let merged = entry.mergingThumbnail(from: nil)
            windows.append(merged)
            changed = true
        }
        let stale = existingIDs.subtracting(freshIDs)
        if !stale.isEmpty {
            windows.removeAll { stale.contains($0.id) }
            changed = true
        }
        let hasReal = entries.contains { !$0.title.isEmpty }
        if hasReal {
            let before = windows.count
            windows.removeAll { $0.title.isEmpty }
            if windows.count != before { changed = true }
        }
        if selectedIndex >= windows.count {
            selectedIndex = max(0, windows.count - 1)
        }
        if changed {
            recomputeAndPublishDimensions()
            if windows.count != previousCount {
                onFrameRefreshNeeded?()
            }
        }
        return changed
    }

    func mergeWindowsIfNeeded(_ entries: [DockPreviewWindowEntry]) -> Bool {
        mergeWindows(entries)
    }

    func setIndex(to index: Int, shouldScroll: Bool = true) {
        shouldScrollToIndex = shouldScroll
        guard index >= 0, index < windows.count else {
            if index == -1, isWindowSwitcherActive {
                selectedIndex = -1
            }
            return
        }
        selectedIndex = index
    }

    func selectNext(delta: Int) {
        guard !windows.isEmpty else { return }
        if isWindowSwitcherActive, !searchQuery.isEmpty {
            selectNextInFiltered(delta: delta)
            return
        }
        let base = selectedIndex < 0 ? 0 : selectedIndex
        selectedIndex = (base + delta + windows.count) % windows.count
        shouldScrollToIndex = true
    }

    func selectNextInFiltered(delta: Int) {
        let indices = filteredWindowIndices()
        guard !indices.isEmpty else { return }
        let position = indices.firstIndex(of: selectedIndex) ?? 0
        let next = (position + delta + indices.count) % indices.count
        selectedIndex = indices[next]
        shouldScrollToIndex = true
    }

    func clampSelectionToFilteredSearch() {
        let indices = filteredWindowIndices()
        guard !indices.isEmpty else { return }
        if !indices.contains(selectedIndex) {
            selectedIndex = indices[0]
        }
    }

    func filteredWindowIndices() -> [Int] {
        guard !searchQuery.isEmpty else {
            return Array(windows.indices)
        }
        let q = searchQuery.lowercased()
        return windows.indices.filter { windows[$0].title.lowercased().contains(q) }
    }

    var isWindowlessPlaceholder: Bool {
        windows.count == 1 && windows[0].title == "No open windows"
    }
}
