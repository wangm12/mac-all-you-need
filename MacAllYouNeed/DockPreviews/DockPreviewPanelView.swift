import AppKit
import SwiftUI

struct DockPreviewPanelView: View {
    let appIcon: NSImage?
    let appName: String
    let entries: [DockPreviewWindowEntry]
    let mode: DockPreviewPermissionGate.Mode
    let enableLivePreview: Bool
    let onSelect: (DockPreviewWindowEntry) -> Void

    @ObservedObject private var liveCapture = DockPreviewLiveCaptureManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            appHeader
            windowStrip
        }
        .padding(DockPreviewLayout.outerPadding)
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: DockPreviewLayout.containerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DockPreviewLayout.containerRadius, style: .continuous)
                .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 20, x: 0, y: 8)
    }

    private var appHeader: some View {
        HStack(spacing: DockPreviewLayout.headerSpacing) {
            if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(
                        width: DockPreviewLayout.headerIconSize,
                        height: DockPreviewLayout.headerIconSize
                    )
            }
            Text(appName)
                .font(.headline)
                .foregroundStyle(.primary)
        }
        .padding(.bottom, DockPreviewLayout.headerBottomPadding)
    }

    private var windowStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DockPreviewLayout.itemSpacing) {
                ForEach(entries) { entry in
                    DockPreviewCard(
                        entry: entry,
                        mode: mode,
                        liveImage: enableLivePreview ? liveCapture.frames[entry.id] : nil,
                        reduceMotion: reduceMotion
                    )
                    .onTapGesture { onSelect(entry) }
                }
            }
        }
    }

    private var panelBackground: some View {
        ZStack {
            MAYNTheme.elevated.opacity(0.92)
            Rectangle().fill(.ultraThinMaterial)
        }
    }
}

struct DockPreviewCard: View {
    let entry: DockPreviewWindowEntry
    let mode: DockPreviewPermissionGate.Mode
    let liveImage: CGImage?
    let reduceMotion: Bool

    @State private var isHovered = false

    private static var thumbW: CGFloat { DockPreviewLayout.thumbnailWidth }
    private static var thumbH: CGFloat { DockPreviewLayout.thumbnailHeight }

    var body: some View {
        VStack(alignment: .center, spacing: DockPreviewLayout.cardInnerSpacing) {
            thumbnailView
            titleView
        }
        .padding(DockPreviewLayout.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: DockPreviewLayout.cardRadius, style: .continuous)
                .fill(MAYNTheme.elevated.opacity(isHovered ? 0.5 : 0.2))
        )
        .clipShape(RoundedRectangle(cornerRadius: DockPreviewLayout.cardRadius, style: .continuous))
        .onHover { isHovered = $0 }
        .animation(MAYNMotion.hoverAnimation(reduceMotion: reduceMotion), value: isHovered)
    }

    @ViewBuilder
    private var thumbnailView: some View {
        Group {
            if let liveImage {
                Image(decorative: liveImage, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: Self.thumbW, height: Self.thumbH)
            } else if mode == .fullPreview, let thumb = entry.thumbnail {
                Image(nsImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: Self.thumbW, height: Self.thumbH)
            } else {
                ZStack {
                    MAYNTheme.elevated.opacity(0.4)
                    VStack(spacing: 6) {
                        Image(systemName: "macwindow")
                            .font(.title)
                            .foregroundStyle(.secondary)
                        if mode != .fullPreview {
                            Text("Enable Screen Recording")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(width: Self.thumbW, height: Self.thumbH)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DockPreviewLayout.thumbnailCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DockPreviewLayout.thumbnailCornerRadius, style: .continuous)
                .stroke(MAYNTheme.subtleBorder.opacity(isHovered ? 0.8 : 0.35), lineWidth: 1)
        )
    }

    private var titleView: some View {
        HStack(spacing: 4) {
            if entry.isMinimized {
                Image(systemName: "minus.square")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(entry.title.isEmpty ? "Window" : entry.title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(isHovered ? Color.primary : Color.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: Self.thumbW)
        }
    }
}

enum DockPreviewLayout {
    /// Thumbnail capture size (larger preview image).
    static let thumbnailScale: CGFloat = 1.72
    /// Outer chrome / margins (tighter than thumbnail scale).
    static let paddingScale: CGFloat = 0.55

    private static let baseOuterPadding: CGFloat = 16
    private static let baseItemSpacing: CGFloat = 12
    private static let baseCardPadding: CGFloat = 8
    private static let baseContainerRadius: CGFloat = 16
    private static let baseCardRadius: CGFloat = 10
    private static let baseThumbnailWidth: CGFloat = 240
    private static let baseThumbnailHeight: CGFloat = 150
    private static let baseCardInnerSpacing: CGFloat = 6
    private static let baseThumbnailCornerRadius: CGFloat = 6
    private static let baseFolderPanelWidth: CGFloat = 320
    private static let baseFolderPanelHeight: CGFloat = 280

    static let outerPadding = baseOuterPadding * paddingScale
    static let itemSpacing = baseItemSpacing * paddingScale
    static let cardPadding = baseCardPadding * paddingScale
    static let containerRadius = baseContainerRadius * paddingScale + 6
    static let cardRadius = baseCardRadius * paddingScale + 2
    static let thumbnailWidth = baseThumbnailWidth * thumbnailScale
    static let thumbnailHeight = baseThumbnailHeight * thumbnailScale
    static let cardInnerSpacing = baseCardInnerSpacing * paddingScale
    static let thumbnailCornerRadius = baseThumbnailCornerRadius * paddingScale + 1

    static let headerIconSize: CGFloat = 18
    static let headerSpacing: CGFloat = 6
    static let headerBottomPadding: CGFloat = 6
    static let titleRowHeight: CGFloat = 16

    static var cardContentHeight: CGFloat {
        thumbnailHeight + cardInnerSpacing + titleRowHeight
    }

    static var cardHeight: CGFloat {
        cardContentHeight + cardPadding * 2
    }

    static var headerHeight: CGFloat {
        headerIconSize + headerBottomPadding
    }

    static var panelHeight: CGFloat {
        outerPadding * 2 + headerHeight + cardHeight
    }

    static let folderPanelSize = CGSize(
        width: baseFolderPanelWidth * thumbnailScale,
        height: baseFolderPanelHeight * thumbnailScale
    )

    static var cardWidth: CGFloat { thumbnailWidth + cardPadding * 2 }
}
