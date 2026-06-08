import Foundation

/// Shared read path for clipboard history surfaces (dock, menu bar, main window).
///
/// Plain-text queries hit the FTS5 `search_index` table (separate `search.sqlite`,
/// same index the daemon maintains) and only hydrate matching row IDs from
/// `clipboard.sqlite` — no full-history load into memory.
///
/// Fuzzy match, smart operators (`/app:`, `/regex:`, …), and missing search DB
/// still scan a capped recent slice and filter in Swift.
public enum ClipboardHistoryQueryLoader {
    public static func load(
        clip: ClipboardStore,
        search: SearchStore?,
        query: String?,
        limit: Int,
        modifiedOnOrAfter: Date?,
        structured: ClipboardHistoryStructuredFilter = ClipboardHistoryStructuredFilter(),
        scanCap: Int = 200
    ) throws -> [ClipboardItemMeta] {
        var filter = structured
        if filter.modifiedOnOrAfter == nil {
            filter.modifiedOnOrAfter = modifiedOnOrAfter
        }

        let trimmed = query?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else {
            let listed = try clip.list(limit: limit, modifiedOnOrAfter: filter.modifiedOnOrAfter)
            return applyStructured(listed, filter: filter)
        }

        if let search {
            let overFetch = max(limit * 3, limit + 30)
            let hits = try search.search(query: trimmed, limit: overFetch, offset: 0)
            let clipboardIDs = hits.filter { $0.kind == .clipboardItem }.map(\.id)
            var metas = try clip.metas(for: clipboardIDs)
            metas = applyStructured(metas, filter: filter)
            return Array(metas.prefix(limit))
        }

        let recent = try clip.list(
            limit: max(scanCap, limit * 3),
            modifiedOnOrAfter: filter.modifiedOnOrAfter
        )
        let lower = trimmed.lowercased()
        let substring = recent.filter { $0.preview.lowercased().contains(lower) }
        let filtered = applyStructured(substring, filter: filter)
        return Array(filtered.prefix(limit))
    }

    /// Loads a capped recent slice and applies structured SQL-friendly filters only
    /// (no FTS). Used for smart-operator queries with empty free text.
    public static func loadRecentStructured(
        clip: ClipboardStore,
        limit: Int,
        modifiedOnOrAfter: Date?,
        structured: ClipboardHistoryStructuredFilter,
        scanCap: Int = 200
    ) throws -> [ClipboardItemMeta] {
        var filter = structured
        if filter.modifiedOnOrAfter == nil {
            filter.modifiedOnOrAfter = modifiedOnOrAfter
        }
        let fetchLimit = max(scanCap, limit * 3)
        let recent = try clip.list(
            limit: fetchLimit,
            modifiedOnOrAfter: filter.modifiedOnOrAfter,
            structured: filter
        )
        guard !filter.typeFilters.isEmpty else { return recent }
        return applyStructured(recent, filter: filter)
    }

    private static func applyStructured(
        _ metas: [ClipboardItemMeta],
        filter: ClipboardHistoryStructuredFilter
    ) -> [ClipboardItemMeta] {
        guard filter.hasStructuredConstraints else { return metas }
        return metas.filter { filter.matches($0) }
    }
}
