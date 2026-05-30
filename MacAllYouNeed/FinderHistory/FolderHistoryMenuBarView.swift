import Core
import SwiftUI

/// Compact recent-folders list for the Command Center menu-bar popover.
struct FolderHistoryMenuBarView: View {
    let store: FolderHistoryStore
    @State private var rows: [FolderHistoryRow] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if rows.isEmpty {
                Text("No folders visited yet")
                    .foregroundStyle(MAYNTheme.muted)
                    .font(.caption)
                    .padding(.horizontal, MAYNControlMetrics.rowHorizontalPadding)
                    .padding(.vertical, MAYNControlMetrics.rowVerticalPadding)
            } else {
                ForEach(rows.prefix(15)) { row in
                    Button {
                        FolderHistoryActions.open(path: row.path)
                    } label: {
                        HStack(spacing: MAYNControlMetrics.rowControlSpacing) {
                            Image(systemName: "folder").foregroundStyle(MAYNTheme.muted)
                            Text(row.displayName).font(.callout).lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, MAYNControlMetrics.rowHorizontalPadding)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .task { rows = (try? store.list(limit: 15)) ?? [] }
    }
}
