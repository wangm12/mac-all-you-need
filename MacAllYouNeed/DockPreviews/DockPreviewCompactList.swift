import SwiftUI

/// Title-only list when over compact threshold (DockDoor `WindowPreviewCompact` subset).
struct DockPreviewCompactList: View {
    let state: DockPreviewStateCoordinator
    let onSelect: (DockPreviewWindowEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if state.appearance.showAppHeader {
                HStack(spacing: 6) {
                    if let icon = state.appIcon {
                        Image(nsImage: icon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                    }
                    Text(state.appName)
                        .font(.system(size: 13, weight: .semibold))
                }
                .padding(.bottom, 4)
            }
            ForEach(listEntries) { item in
                let entry = item.entry
                Button {
                    onSelect(entry)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: entry.isMinimized ? "minus.square" : "macwindow")
                            .foregroundStyle(.secondary)
                        Text(entry.title.isEmpty ? "Window" : entry.title)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: CGFloat(state.settings.previewCardWidth) + 40)
    }

    private var listEntries: [CompactRow] {
        state.filteredWindowIndices().map { index in
            CompactRow(entry: state.windows[index])
        }
    }

    private struct CompactRow: Identifiable {
        let entry: DockPreviewWindowEntry
        var id: CGWindowID { entry.id }
    }
}
