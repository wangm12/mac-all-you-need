import AppKit
import SwiftUI

/// Single window tile (DockDoor `WindowPreview` dock-hover layout).
struct DockPreviewWindowCard: View, Equatable {
    let entry: DockPreviewWindowEntry
    let dimensions: DockPreviewWindowDimensions
    let mode: DockPreviewPermissionGate.Mode
    let settings: DockPreviewSettings
    let appearance: DockPreviewAppearanceContext
    let dockEdge: DockPreviewPanelGeometry.DockEdge
    let isWindowSwitcher: Bool
    let liveImage: CGImage?
    let isSelected: Bool
    let isActiveWindow: Bool
    let reduceMotion: Bool
    let enableWindowDrag: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onHoverIndex: (Bool) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.entry.id == rhs.entry.id
            && lhs.isSelected == rhs.isSelected
            && lhs.isActiveWindow == rhs.isActiveWindow
            && lhs.dimensions == rhs.dimensions
            && (lhs.liveImage != nil) == (rhs.liveImage != nil)
    }

    @State private var isHovered = false

    private var isLoadingPlaceholder: Bool { entry.title.isEmpty }
    private var isAwaitingThumbnail: Bool {
        !isLoadingPlaceholder
            && entry.thumbnail == nil
            && liveImage == nil
            && mode == .fullPreview
    }
    private var showAsSelected: Bool {
        isWindowSwitcher ? (isSelected || isHovered) : isHovered
    }
    private var thumbSize: CGSize {
        CGSize(
            width: max(dimensions.size.width, 50),
            height: max(dimensions.size.height, 50)
        )
    }
    private var imageCornerRadius: CGFloat {
        DockPreviewCardRadius.image(
            uniformCardRadius: appearance.uniformCardRadius,
            paddingMultiplier: appearance.globalPaddingMultiplier
        )
    }
    private var cardCornerRadius: CGFloat {
        DockPreviewCardRadius.outer(
            paddingMultiplier: appearance.globalPaddingMultiplier,
            uniformCardRadius: appearance.uniformCardRadius
        )
    }
    private var titleMaxWidth: CGFloat {
        max(thumbSize.width - 24, 80)
    }
    private var toolbarHorizontalPadding: CGFloat {
        appearance.uniformCardRadius
            ? DockPreviewCardRadius.innerPadding * 0.5
            : 0
    }

    var body: some View {
        previewCoreContent
            .dockPreviewWindowInteractions(
                onSelect: onSelect,
                onClose: onClose,
                enableFullSizeOnHover: appearance.allowsFullSizeHoverPreview,
                enableWindowDrag: enableWindowDrag,
                entry: entry,
                liveImage: liveImage,
                reduceMotion: reduceMotion
            )
            .fixedSize()
    }

    private var previewCoreContent: some View {
        let finalSelected = showAsSelected
        return ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 0) {
                if !appearance.useEmbeddedControlsOverlay, appearance.controlPosition.showsOnTop {
                    let slot = appearance.controlPosition.topConfiguration
                    if shouldShowExternalToolbar(slot: slot, selected: finalSelected) {
                        externalToolbar(for: finalSelected, slot: slot)
                            .padding(.horizontal, toolbarHorizontalPadding)
                            .padding(.bottom, 4)
                    }
                }

                windowContent(isSelected: finalSelected)
                    .dockPreviewDynamicFrame(
                        allowDynamicSizing: settings.allowDynamicImageSizing,
                        dimensions: dimensions,
                        dockEdge: dockEdge,
                        isWindowSwitcher: isWindowSwitcher
                    )

                if !appearance.useEmbeddedControlsOverlay, appearance.controlPosition.showsOnBottom {
                    let slot = appearance.controlPosition.bottomConfiguration
                    if shouldShowExternalToolbar(slot: slot, selected: finalSelected) {
                        externalToolbar(for: finalSelected, slot: slot)
                            .padding(.horizontal, toolbarHorizontalPadding)
                            .padding(.top, 4)
                    }
                }
            }
            .frame(maxWidth: dimensions.maxDimensions.width > 0 ? dimensions.maxDimensions.width : nil)
            .background { cardChrome(isSelected: finalSelected) }
            .overlay {
                if appearance.useEmbeddedControlsOverlay {
                    embeddedControlsOverlay(selected: finalSelected)
                        .frame(width: thumbSize.width, height: thumbSize.height)
                }
            }
        }
        .onContinuousHover { phase in
            switch phase {
            case .active:
                if !isHovered {
                    withAnimation(appearance.showAnimations ? .snappy(duration: 0.175) : nil) {
                        isHovered = true
                    }
                    onHoverIndex(true)
                }
            case .ended:
                if isHovered {
                    withAnimation(appearance.showAnimations ? .snappy(duration: 0.175) : nil) {
                        isHovered = false
                    }
                    onHoverIndex(false)
                }
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func windowContent(isSelected: Bool) -> some View {
        let inactive = (entry.isMinimized || entry.isHidden) && appearance.showMinimizedHiddenLabels
        Group {
            if isLoadingPlaceholder {
                ZStack {
                    Color.primary.opacity(0.06)
                    ProgressView().controlSize(.small)
                }
            } else if let liveImage {
                Image(decorative: liveImage, scale: 1)
                    .resizable()
                    .scaledToFit()
            } else if let thumb = entry.thumbnail {
                Image(nsImage: thumb)
                    .resizable()
                    .scaledToFit()
            } else if isAwaitingThumbnail {
                ZStack {
                    Color.primary.opacity(0.06)
                    ProgressView().controlSize(.small)
                }
            } else {
                ZStack {
                    Color.primary.opacity(0.08)
                    Image(systemName: "macwindow")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .dockPreviewMarkHidden(
            isHidden: inactive || (isWindowSwitcher && !isSelected),
            unselectedOpacity: appearance.unselectedOpacity
        )
        .overlay {
            if inactive {
                Image(systemName: "eye.slash")
                    .font(.largeTitle)
                    .foregroundStyle(.primary)
                    .shadow(radius: 2)
                    .transition(.opacity)
            }
        }
        .animation(appearance.showAnimations ? MAYNMotion.hoverAnimation(reduceMotion: reduceMotion) : nil, value: inactive)
        .clipShape(RoundedRectangle(cornerRadius: imageCornerRadius, style: .continuous))
        .opacity(isSelected ? 1 : appearance.unselectedOpacity)
    }

    @ViewBuilder
    private func cardChrome(isSelected: Bool) -> some View {
        if !appearance.hidePreviewCardBackground {
            DockPreviewBlurView(cornerRadius: cardCornerRadius, appearance: appearance.background)
                .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
                .dockPreviewBorderedBackground(
                    Color.primary.opacity(0.1),
                    lineWidth: 1.75,
                    cornerRadius: cardCornerRadius
                )
                .padding(-DockPreviewCardRadius.innerPadding)
                .overlay {
                    if isSelected {
                        let color = appearance.hoverHighlightColor ?? appearance.activeAppIndicatorColor
                        RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                            .fill(color.opacity(appearance.selectionOpacity))
                            .padding(-DockPreviewCardRadius.innerPadding)
                    }
                }
                .overlay {
                    if appearance.showActiveWindowBorder, isActiveWindow {
                        RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                            .strokeBorder(appearance.activeAppIndicatorColor, lineWidth: 2.5)
                            .padding(-DockPreviewCardRadius.innerPadding)
                    }
                }
        }
    }

    private func shouldShowExternalToolbar(
        slot: DockPreviewControlPosition.SlotConfiguration,
        selected: Bool
    ) -> Bool {
        let showTitle = appearance.showWindowTitle
            && slot.showTitle
            && !isLoadingPlaceholder
            && (appearance.windowTitleVisibility == .alwaysVisible || selected)
        let showControls = appearance.showTrafficLights
            && slot.showControls
            && !isLoadingPlaceholder
            && (canShowTrafficLights(selected: selected) || minimizedHiddenLabel != nil)
        return showTitle || showControls
    }

    @ViewBuilder
    private func embeddedControlsOverlay(selected: Bool) -> some View {
        embeddedControlsLayout(selected: selected)
    }

    @ViewBuilder
    private func embeddedControlsLayout(selected: Bool) -> some View {
        let title = entry.title.isEmpty ? "Window" : entry.title
        let showTitle = appearance.showWindowTitle
            && !isLoadingPlaceholder
            && (appearance.windowTitleVisibility == .alwaysVisible || selected)
        let showControls = canShowTrafficLights(selected: selected)
        let showChrome = showControls || minimizedHiddenLabel != nil
        let titleView = titlePill(title)
        let controlsView = chromeControlsContent(selected: selected, showTrafficLights: showControls)

        if appearance.controlPosition.showsOnTop {
            VStack {
                controlsRow(
                    titleView: titleView,
                    controlsView: controlsView,
                    showTitle: showTitle,
                    showControls: showChrome,
                    leadingTitle: leadingTitleInOverlay
                )
                .padding(8)
                Spacer(minLength: 0)
            }
        } else {
            VStack {
                Spacer(minLength: 0)
                controlsRow(
                    titleView: titleView,
                    controlsView: controlsView,
                    showTitle: showTitle,
                    showControls: showChrome,
                    leadingTitle: leadingTitleInOverlay
                )
                .padding(8)
            }
        }
    }

    @ViewBuilder
    private func externalToolbar(
        for selected: Bool,
        slot: DockPreviewControlPosition.SlotConfiguration
    ) -> some View {
        let title = entry.title.isEmpty ? "Window" : entry.title
        let showTitle = appearance.showWindowTitle
            && slot.showTitle
            && !isLoadingPlaceholder
            && (appearance.windowTitleVisibility == .alwaysVisible || selected)
        let showControls = appearance.showTrafficLights
            && slot.showControls
            && !isLoadingPlaceholder
            && canShowTrafficLights(selected: selected)
        let showStateLabel = appearance.showMinimizedHiddenLabels
            && slot.showControls
            && !isLoadingPlaceholder
            && minimizedHiddenLabel != nil

        if showTitle || showControls || showStateLabel {
            HStack(spacing: 4) {
                if slot.isLeadingControls {
                    if showControls || showStateLabel {
                        chromeControlsContent(selected: selected, showTrafficLights: showControls)
                    }
                    Spacer(minLength: 8)
                    if showTitle { titlePill(title) }
                } else {
                    if showTitle { titlePill(title) }
                    Spacer(minLength: 8)
                    if showControls || showStateLabel {
                        chromeControlsContent(selected: selected, showTrafficLights: showControls)
                    }
                }
            }
            .frame(maxWidth: thumbSize.width)
        }
    }

    private var minimizedHiddenLabel: String? {
        guard appearance.showMinimizedHiddenLabels,
              appearance.trafficLightVisibility != .never
        else { return nil }
        if entry.isMinimized { return "Minimized" }
        if entry.isHidden { return "Hidden" }
        return nil
    }

    private func canShowTrafficLights(selected: Bool) -> Bool {
        guard appearance.showTrafficLights,
              appearance.trafficLightVisibility != .never,
              !isLoadingPlaceholder
        else { return false }
        if appearance.showMinimizedHiddenLabels, entry.isMinimized || entry.isHidden {
            return false
        }
        switch appearance.trafficLightVisibility {
        case .never: return false
        case .alwaysVisible: return true
        case .fullOpacityOnPreviewHover, .dimmedOnPreviewHover: return selected
        }
    }

    @ViewBuilder
    private func chromeControlsContent(selected: Bool, showTrafficLights: Bool) -> some View {
        if showTrafficLights {
            trafficLights(selected: selected)
        } else if let label = minimizedHiddenLabel {
            Text(label)
                .font(appearance.windowTitleFont)
                .italic()
                .foregroundStyle(.secondary)
                .padding(4)
                .if(!appearance.disableDockStyleTitles) { view in
                    view.dockPreviewMaterialPill(background: appearance.background)
                        .frame(height: 34)
                }
        }
    }

    private var leadingTitleInOverlay: Bool {
        switch appearance.controlPosition {
        case .topTrailing, .bottomTrailing,
             .parallelTopRightBottomRight, .diagonalTopRightBottomLeft,
             .centeredTitleBottomControlsTop, .embeddedTop:
            return false
        default:
            return true
        }
    }

    @ViewBuilder
    private func controlsRow(
        titleView: some View,
        controlsView: some View,
        showTitle: Bool,
        showControls: Bool,
        leadingTitle: Bool
    ) -> some View {
        HStack(spacing: 4) {
            if leadingTitle {
                if showTitle { titleView }
                Spacer(minLength: 4)
                if showControls { controlsView }
            } else {
                if showControls { controlsView }
                Spacer(minLength: 4)
                if showTitle { titleView }
            }
        }
        .frame(maxWidth: thumbSize.width)
    }

    @ViewBuilder
    private func titlePill(_ title: String) -> some View {
        Text(title)
            .font(appearance.windowTitleFont)
            .lineLimit(1)
            .truncationMode(truncationMode)
            .frame(maxWidth: titleMaxWidth, alignment: .leading)
            .padding(4)
            .if(!appearance.disableDockStyleTitles) { view in
                view.dockPreviewMaterialPill(background: appearance.background)
            }
    }

    @ViewBuilder
    private func trafficLights(selected: Bool) -> some View {
        DockPreviewTrafficLightButtons(
            entry: entry,
            appearance: appearance,
            hoveringOverParentWindow: selected,
            onClose: onClose
        )
    }

    private var truncationMode: Text.TruncationMode {
        switch appearance.titleOverflowStyle {
        case .truncateTail: .tail
        case .truncateMiddle: .middle
        case .truncateHead: .head
        }
    }
}

private extension View {
    @ViewBuilder
    func `if`<Transformed: View>(_ condition: Bool, transform: (Self) -> Transformed) -> some View {
        if condition { transform(self) } else { self }
    }
}
