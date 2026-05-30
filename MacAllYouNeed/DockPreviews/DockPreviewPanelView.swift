import AppKit
import SwiftUI

struct DockPreviewPanelView: View {
    let entries: [DockPreviewWindowEntry]
    let mode: DockPreviewPermissionGate.Mode
    let onSelect: (DockPreviewWindowEntry) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(entries) { entry in
                    DockPreviewCard(entry: entry, mode: mode)
                        .onTapGesture { onSelect(entry) }
                }
            }
            .padding(12)
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: MAYNControlMetrics.panelRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MAYNControlMetrics.panelRadius, style: .continuous)
                .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
        )
    }
}

struct DockPreviewCard: View {
    let entry: DockPreviewWindowEntry
    let mode: DockPreviewPermissionGate.Mode

    private static let cardWidth: CGFloat = 160
    private static let thumbnailHeight: CGFloat = 100

    var body: some View {
        VStack(spacing: 6) {
            thumbnail
            Text(entry.title.isEmpty ? "Window" : entry.title)
                .font(.caption)
                .lineLimit(1)
                .frame(width: Self.cardWidth)
            if entry.isMinimized {
                Text("Minimized")
                    .font(.caption2)
                    .foregroundStyle(MAYNTheme.muted)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: MAYNControlMetrics.cardRadius, style: .continuous)
                .fill(MAYNTheme.hover)
        )
    }

    @ViewBuilder
    private var thumbnail: some View {
        if mode == .fullPreview, let thumb = entry.thumbnail {
            Image(nsImage: thumb)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: Self.cardWidth, height: Self.thumbnailHeight)
                .clipShape(RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius, style: .continuous)
                .fill(MAYNTheme.selected)
                .frame(width: Self.cardWidth, height: Self.thumbnailHeight)
                .overlay(
                    Image(systemName: "macwindow")
                        .foregroundStyle(MAYNTheme.muted)
                )
        }
    }
}
