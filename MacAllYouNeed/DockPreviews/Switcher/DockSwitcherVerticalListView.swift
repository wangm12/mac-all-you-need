import AppKit
import SwiftUI

private struct DockSwitcherListItem: Identifiable {
    let index: Int
    let entry: DockPreviewWindowEntry

    var id: CGWindowID { entry.id }
}

/// Tangrid-style vertical searchable switcher list.
struct DockSwitcherVerticalListView: View {
    @Bindable var state: DockPreviewStateCoordinator
    var showSearch: Bool
    let onSelect: (DockPreviewWindowEntry) -> Void
    let onHoverIndex: (Int?) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var filtered: [DockSwitcherListItem] {
        let query = state.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return state.windows.enumerated().compactMap { index, entry in
            guard query.isEmpty || entry.title.localizedCaseInsensitiveContains(query) else { return nil }
            return DockSwitcherListItem(index: index, entry: entry)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showSearch {
                DockPreviewSearchBar(
                    query: Binding(
                        get: { state.searchQuery },
                        set: { state.searchQuery = $0 }
                    ),
                    placeholder: "Search windows…"
                )
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(filtered) { item in
                            listRow(for: item)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onChange(of: state.selectedIndex) { _, newValue in
                    guard state.shouldScrollToIndex else { return }
                    withAnimation(MAYNMotion.controlAnimation(reduceMotion: reduceMotion)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                    state.shouldScrollToIndex = false
                }
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private func listRow(for item: DockSwitcherListItem) -> some View {
        let selected = item.index == state.selectedIndex
        row(item.entry, selected: selected)
            .id(item.index)
            .onTapGesture { onSelect(item.entry) }
            .onHover { hovering in
                if hovering { onHoverIndex(item.index) }
            }
    }

    @ViewBuilder
    private func row(_ entry: DockPreviewWindowEntry, selected: Bool) -> some View {
        HStack(spacing: 10) {
            if let icon = state.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 20, height: 20)
            }
            Text(entry.title)
                .font(.body)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(rowBackground(selected: selected))
        .overlay(rowBorder(selected: selected))
    }

    private func rowBackground(selected: Bool) -> some View {
        RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius, style: .continuous)
            .fill(selected ? MAYNTheme.selected : Color.clear)
    }

    private func rowBorder(selected: Bool) -> some View {
        RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius, style: .continuous)
            .strokeBorder(selected ? MAYNTheme.focusRing : Color.clear, lineWidth: 1)
    }
}
