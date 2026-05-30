import Core
import SwiftUI

/// Quick-switcher list of recent Finder folders. Supports type-to-filter and
/// up/down keyboard navigation with Return to open the highlighted folder.
struct FolderHistorySwitcherView: View {
    let store: FolderHistoryStore
    let onSelect: (FolderHistoryRow) -> Void
    let onDismiss: () -> Void

    @State private var rows: [FolderHistoryRow] = []
    @State private var searchText = ""
    @State private var highlighted = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var filtered: [FolderHistoryRow] {
        guard !searchText.isEmpty else { return rows }
        return rows.filter {
            $0.path.localizedCaseInsensitiveContains(searchText)
                || $0.displayName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            MAYNDivider()
            content
            MAYNDivider()
            footer
        }
        .frame(width: 480)
        .background(MAYNTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: MAYNControlMetrics.panelRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MAYNControlMetrics.panelRadius, style: .continuous)
                .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
        )
        .task { reload() }
    }

    private var searchField: some View {
        HStack(spacing: MAYNControlMetrics.rowControlSpacing) {
            Image(systemName: "magnifyingglass").foregroundStyle(MAYNTheme.muted)
            // Search-chrome exception: raw TextField inside MAYN-styled chrome.
            TextField("Search folders…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.callout)
                .onChange(of: searchText) { highlighted = 0 }
                .onSubmit { activateHighlighted() }
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(MAYNTheme.muted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, MAYNControlMetrics.rowHorizontalPadding)
        .padding(.vertical, MAYNControlMetrics.rowVerticalPadding)
    }

    @ViewBuilder
    private var content: some View {
        if filtered.isEmpty {
            Text(rows.isEmpty ? "No folders in history" : "No matches")
                .foregroundStyle(MAYNTheme.muted)
                .font(.callout)
                .frame(maxWidth: .infinity)
                .padding()
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { index, row in
                        rowView(row, isHighlighted: index == highlighted)
                            .onTapGesture { onSelect(row) }
                            .onHover { if $0 { highlighted = index } }
                    }
                }
            }
            .frame(maxHeight: 300)
        }
    }

    private func rowView(_ row: FolderHistoryRow, isHighlighted: Bool) -> some View {
        HStack(spacing: MAYNControlMetrics.rowControlSpacing) {
            Image(systemName: "folder").foregroundStyle(MAYNTheme.muted)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.displayName).font(.callout).fontWeight(.medium)
                Text(row.path).font(.caption).foregroundStyle(MAYNTheme.muted).lineLimit(1).truncationMode(.head)
            }
            Spacer()
            if row.isPinned {
                Image(systemName: "pin.fill").foregroundStyle(MAYNTheme.muted).font(.caption)
            }
        }
        .padding(.horizontal, MAYNControlMetrics.rowHorizontalPadding)
        .padding(.vertical, MAYNControlMetrics.rowVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isHighlighted ? MAYNTheme.selected : Color.clear)
        .contentShape(Rectangle())
    }

    private var footer: some View {
        HStack {
            Text("↑↓ navigate · ↵ open · esc dismiss")
                .font(.caption)
                .foregroundStyle(MAYNTheme.muted)
            Spacer()
            MAYNButton("Done", action: onDismiss)
        }
        .padding(.horizontal, MAYNControlMetrics.rowHorizontalPadding)
        .padding(.vertical, MAYNControlMetrics.rowVerticalPadding)
    }

    private func reload() {
        rows = (try? store.list(limit: 100)) ?? []
        highlighted = 0
    }

    private func activateHighlighted() {
        let items = filtered
        guard items.indices.contains(highlighted) else {
            if let first = items.first { onSelect(first) }
            return
        }
        onSelect(items[highlighted])
    }

    /// Drives keyboard navigation from the hosting panel's key handler.
    func move(by delta: Int) {
        let count = filtered.count
        guard count > 0 else { return }
        highlighted = max(0, min(count - 1, highlighted + delta))
    }

    func openHighlighted() {
        activateHighlighted()
    }
}
