import Core
import Foundation

/// Drives the hotkey history panel: list data, search filtering, and keyboard selection.
@MainActor
final class FolderHistorySwitcherModel: ObservableObject {
    @Published var rows: [FolderHistoryRow] = []
    @Published var searchText = "" {
        didSet {
            if searchText != oldValue {
                highlighted = 0
            }
        }
    }
    @Published var highlighted = 0

    var displayedRows: [FolderHistoryRow] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return Array(rows.prefix(FolderHistoryDisplayLimits.quickPickCount))
        }
        return FolderHistoryMatcher.ranked(rows: rows, query: searchText)
    }

    func reload(store: FolderHistoryStore) {
        rows = (try? store.list(limit: 100)) ?? []
        highlighted = 0
    }

    func move(by delta: Int) {
        let count = displayedRows.count
        guard count > 0 else { return }
        highlighted = max(0, min(count - 1, highlighted + delta))
    }

    func openHighlighted(onSelect: (FolderHistoryRow) -> Void) {
        let items = displayedRows
        guard !items.isEmpty else { return }
        let index = items.indices.contains(highlighted) ? highlighted : 0
        onSelect(items[index])
    }
}
