import AppKit
import SwiftUI

// MARK: - Main panel view (mirrors DockDoor's BaseHoverContainer + app title pattern)

struct DockPreviewPanelView: View {
    let appIcon: NSImage?
    let appName: String
    let entries: [DockPreviewWindowEntry]
    let mode: DockPreviewPermissionGate.Mode
    let onSelect: (DockPreviewWindowEntry) -> Void

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
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 24, x: 0, y: 8)
    }

    // MARK: - App header (icon + name, à la SharedHoverAppTitle)

    private var appHeader: some View {
        HStack(spacing: 8) {
            if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
            }
            Text(appName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .padding(.bottom, 10)
    }

    // MARK: - Window cards strip

    private var windowStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DockPreviewLayout.itemSpacing) {
                ForEach(entries) { entry in
                    DockPreviewCard(entry: entry, mode: mode)
                        .onTapGesture { onSelect(entry) }
                }
            }
        }
    }

    // MARK: - Glass background

    private var panelBackground: some View {
        ZStack {
            // Dark translucent fill — matches DockDoor's `.hudWindow` blur look
            Color.black.opacity(0.55)
            // Thin material overlay for the glass effect
            Rectangle().fill(.ultraThinMaterial)
        }
    }
}

// MARK: - Single window card (mirrors DockDoor's WindowPreview card)

struct DockPreviewCard: View {
    let entry: DockPreviewWindowEntry
    let mode: DockPreviewPermissionGate.Mode

    @State private var isHovered = false

    private static let thumbW: CGFloat = 240
    private static let thumbH: CGFloat = 150

    var body: some View {
        VStack(alignment: .center, spacing: 6) {
            thumbnailView
            titleView
        }
        .padding(DockPreviewLayout.cardPadding)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DockPreviewLayout.cardRadius, style: .continuous))
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }

    // MARK: Thumbnail

    @ViewBuilder
    private var thumbnailView: some View {
        Group {
            if mode == .fullPreview, let thumb = entry.thumbnail {
                Image(nsImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: Self.thumbW, height: Self.thumbH)
            } else {
                ZStack {
                    Color.white.opacity(0.06)
                    VStack(spacing: 6) {
                        Image(systemName: "macwindow")
                            .font(.system(size: 32))
                            .foregroundStyle(.white.opacity(0.35))
                        if mode != .fullPreview {
                            Text("Enable Screen Recording")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.45))
                        }
                    }
                }
                .frame(width: Self.thumbW, height: Self.thumbH)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(.white.opacity(isHovered ? 0.3 : 0.08), lineWidth: 1)
        )
    }

    // MARK: Title

    private var titleView: some View {
        HStack(spacing: 4) {
            if entry.isMinimized {
                Image(systemName: "minus.square")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
            }
            Text(entry.title.isEmpty ? "Window" : entry.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isHovered ? .white : .white.opacity(0.75))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: Self.thumbW)
        }
    }

    // MARK: Card background

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: DockPreviewLayout.cardRadius, style: .continuous)
            .fill(.white.opacity(isHovered ? 0.15 : 0.0))
    }
}

// MARK: - Layout constants (mirrors DockDoor's HoverContainerPadding + CardRadius)

enum DockPreviewLayout {
    static let outerPadding: CGFloat = 16
    static let itemSpacing: CGFloat = 12
    static let cardPadding: CGFloat = 8
    static let containerRadius: CGFloat = 16
    static let cardRadius: CGFloat = 10
}
