import Core
import SwiftUI

/// Hotkey history panel: searchable list of visited Finder folders.
struct FolderHistorySwitcherView: View {
    @ObservedObject var model: FolderHistorySwitcherModel
    let context: FolderHistoryPanelContext
    let onSelect: (FolderHistoryRow) -> Void

    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchField
            MAYNDivider()
            if model.rows.isEmpty {
                hintBanner(context.emptyListHint)
                MAYNDivider()
            }
            content
        }
        .frame(width: 520)
        .background(MAYNTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: MAYNControlMetrics.panelRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MAYNControlMetrics.panelRadius, style: .continuous)
                .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
        )
        .onAppear {
            searchFocused = true
        }
    }

    private var searchField: some View {
        HStack(spacing: MAYNControlMetrics.rowControlSpacing) {
            Image(systemName: "magnifyingglass").foregroundStyle(MAYNTheme.muted)
            TextField("Search history…", text: $model.searchText)
                .textFieldStyle(.plain)
                .font(.callout)
                .focused($searchFocused)
                .onSubmit { model.openHighlighted(onSelect: onSelect) }
            if !model.searchText.isEmpty {
                Button { model.searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(MAYNTheme.muted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, MAYNControlMetrics.rowHorizontalPadding)
        .padding(.vertical, MAYNControlMetrics.rowVerticalPadding)
    }

    private func hintBanner(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(MAYNTheme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, MAYNControlMetrics.rowHorizontalPadding)
            .padding(.vertical, MAYNControlMetrics.rowVerticalPadding)
    }

    @ViewBuilder
    private var content: some View {
        let items = model.displayedRows
        if items.isEmpty {
            if !model.rows.isEmpty {
                Text("No matches")
                    .foregroundStyle(MAYNTheme.muted)
                    .font(.callout)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, row in
                        rowView(row, isHighlighted: index == model.highlighted)
                            .onTapGesture { onSelect(row) }
                            .onHover { if $0 { model.highlighted = index } }
                            .contextMenu {
                                Button("Open in Finder") {
                                    FolderHistoryActions.reveal(path: row.path)
                                }
                                Button("Browse in Mac All You Need") {
                                    let url = URL(fileURLWithPath: row.path)
                                    NotificationCenter.default.post(
                                        name: .browseFolderRequested,
                                        object: url
                                    )
                                }
                            }
                    }
                }
            }
            .frame(maxHeight: CGFloat(FolderHistoryDisplayLimits.quickPickCount) * MAYNControlMetrics.rowMinHeight)
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
}
