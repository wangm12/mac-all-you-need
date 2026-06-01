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
    private var showAsSelected: Bool { isSelected || isHovered }
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

    var body: some View {
        previewCoreContent
            .dockPreviewWindowInteractions(
                onSelect: onSelect,
                onClose: onClose,
                enableFullSizeOnHover: appearance.allowsFullSizeHoverPreview,
                entry: entry,
                liveImage: liveImage,
                reduceMotion: reduceMotion
            )
            .fixedSize()
    }

    private var previewCoreContent: some View {
        let finalSelected = showAsSelected
        return ZStack(alignment: .topLeading) {
            thumbnailStack(isSelected: finalSelected)

            if appearance.useEmbeddedControlsOverlay {
                embeddedControlsOverlay(selected: finalSelected)
                    .frame(width: thumbSize.width, height: thumbSize.height)
            } else {
                externalChrome(selected: finalSelected)
            }
        }
        .frame(maxWidth: dimensions.maxDimensions.width > 0 ? dimensions.maxDimensions.width : nil)
        .onContinuousHover { phase in
            switch phase {
            case .active:
                if !isHovered {
                    withAnimation(MAYNMotion.hoverAnimation(reduceMotion: reduceMotion)) {
                        isHovered = true
                    }
                    onHoverIndex(true)
                }
            case .ended:
                if isHovered {
                    withAnimation(MAYNMotion.hoverAnimation(reduceMotion: reduceMotion)) {
                        isHovered = false
                    }
                    onHoverIndex(false)
                }
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func thumbnailStack(isSelected: Bool) -> some View {
        windowContent(isSelected: isSelected)
            .frame(width: thumbSize.width, height: thumbSize.height)
            .background { cardChrome(isSelected: isSelected) }
            .clipShape(RoundedRectangle(cornerRadius: imageCornerRadius, style: .continuous))
    }

    @ViewBuilder
    private func externalChrome(selected: Bool) -> some View {
        VStack(spacing: 0) {
            if appearance.controlPosition.showsOnTop {
                externalToolbar(for: selected, slot: appearance.controlPosition.topConfiguration)
                    .frame(width: thumbSize.width)
                    .padding(.bottom, 4)
            }
            Spacer(minLength: 0)
            if appearance.controlPosition.showsOnBottom {
                externalToolbar(for: selected, slot: appearance.controlPosition.bottomConfiguration)
                    .frame(width: thumbSize.width)
                    .padding(.top, 4)
            }
        }
        .frame(width: thumbSize.width, height: thumbSize.height)
    }

    @ViewBuilder
    private func windowContent(isSelected: Bool) -> some View {
        let inactive = (entry.isMinimized || !entry.isOnScreen) && appearance.showMinimizedHiddenLabels
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
        .overlay {
            if inactive {
                Image(systemName: "eye.slash")
                    .font(.largeTitle)
                    .foregroundStyle(.primary)
                    .shadow(radius: 2)
            }
        }
        .opacity(isSelected ? 1 : appearance.unselectedOpacity)
    }

    @ViewBuilder
    private func cardChrome(isSelected: Bool) -> some View {
        if !appearance.hidePreviewCardBackground {
            DockPreviewBlurView(cornerRadius: cardCornerRadius, appearance: appearance.background)
                .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1.75)
                }
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
        let showControls = appearance.showTrafficLights
            && !isLoadingPlaceholder
            && trafficLightsVisible(selected: selected)
        let titleView = titlePill(title)
        let controlsView = trafficLights(selected: selected)

        if appearance.controlPosition.showsOnTop {
            VStack {
                controlsRow(
                    titleView: titleView,
                    controlsView: controlsView,
                    showTitle: showTitle,
                    showControls: showControls,
                    leadingTitle: true
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
                    showControls: showControls,
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
            && trafficLightsVisible(selected: selected)

        if showTitle || showControls {
            HStack(spacing: 4) {
                if slot.isLeadingControls {
                    if showControls { trafficLights(selected: selected) }
                    Spacer(minLength: 4)
                    if showTitle { titlePill(title) }
                } else {
                    if showTitle { titlePill(title) }
                    Spacer(minLength: 4)
                    if showControls { trafficLights(selected: selected) }
                }
            }
        }
    }

    private var leadingTitleInOverlay: Bool {
        switch appearance.controlPosition {
        case .parallelTopRightBottomRight, .diagonalTopRightBottomLeft,
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
    }

    private func trafficLightsVisible(selected: Bool) -> Bool {
        switch appearance.trafficLightVisibility {
        case .never: false
        case .always: true
        case .onHover: selected
        }
    }

    @ViewBuilder
    private func titlePill(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
            .truncationMode(truncationMode)
            .frame(maxWidth: titleMaxWidth, alignment: .leading)
            .if(!appearance.disableDockStyleTitles) { view in
                view.dockPreviewMaterialPill(background: appearance.background)
            }
            .if(appearance.disableDockStyleTitles) { view in
                view.padding(4)
            }
    }

    @ViewBuilder
    private func trafficLights(selected: Bool) -> some View {
        DockPreviewTrafficLightButtons(
            entry: entry,
            appearance: appearance,
            hovering: selected,
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
