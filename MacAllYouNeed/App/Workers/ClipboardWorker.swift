import Core
import FeatureCore
import Foundation
import Platform

/// Background worker for clipboard history search and metadata hydration.
actor ClipboardWorker: FeatureWorker {
    private let clip: ClipboardStore
    private let search: SearchStore
    private var isRunning = false
    private var inFlightLoad: Task<[ClipboardXPCMeta], Never>?

    init(clip: ClipboardStore, search: SearchStore) {
        self.clip = clip
        self.search = search
    }

    func start() async {
        guard !isRunning else { return }
        isRunning = true
    }

    func stop() async {
        isRunning = false
        inFlightLoad?.cancel()
        inFlightLoad = nil
    }

    /// Coalesces overlapping history loads — latest call wins.
    func loadHistory(
        query: String?,
        limit: Int,
        fuzzyEnabled: Bool
    ) async -> [ClipboardXPCMeta] {
        inFlightLoad?.cancel()
        let task = Task { [clip, search] in
            (try? ClipboardHistorySearchEngine.load(
                clip: clip,
                search: search,
                request: ClipboardHistorySearchEngine.LoadRequest(
                    query: query,
                    limit: limit,
                    fuzzyEnabled: fuzzyEnabled
                )
            )) ?? []
        }
        inFlightLoad = task
        return await task.value
    }

    func loadByIDs(_ ids: [String]) async -> [ClipboardXPCMeta] {
        (try? ClipboardHistorySearchEngine.loadByIDs(clip: clip, ids: ids)) ?? []
    }

    func loadHistoryMetas(
        query: String?,
        limit: Int,
        fuzzyEnabled: Bool
    ) async -> [ClipboardItemMeta] {
        (try? ClipboardHistorySearchEngine.loadMetas(
            clip: clip,
            search: search,
            request: ClipboardHistorySearchEngine.LoadRequest(
                query: query,
                limit: limit,
                fuzzyEnabled: fuzzyEnabled
            )
        )) ?? []
    }

    func loadForReader(query: String) async -> [ClipboardItemMeta] {
        let signpost = PerformanceSignpost.Clipboard.beginHistoryLoad()
        defer { PerformanceSignpost.Clipboard.endHistoryLoad(signpost) }

        let window = ClipboardHistoryWindow.listParameters()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            let listed = (try? clip.list(limit: 200, modifiedOnOrAfter: window.modifiedOnOrAfter)) ?? []
            return ClipboardHistorySearchEngine.dedupSamePaste(listed, limit: 30)
        }

        let smart = SmartSearchQuery(trimmed)
        let raw: [ClipboardItemMeta]
        if smart.hasOperators {
            if smart.freeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !smart.isRegex {
                raw = (try? ClipboardHistoryQueryLoader.loadRecentStructured(
                    clip: clip,
                    limit: 90,
                    modifiedOnOrAfter: window.modifiedOnOrAfter,
                    structured: readerStructuredFilter(smart, cutoff: window.modifiedOnOrAfter)
                )) ?? []
            } else {
                raw = (try? ClipboardHistoryQueryLoader.load(
                    clip: clip,
                    search: search,
                    query: smart.isRegex ? trimmed : smart.freeText,
                    limit: 90,
                    modifiedOnOrAfter: window.modifiedOnOrAfter,
                    structured: readerStructuredFilter(smart, cutoff: window.modifiedOnOrAfter)
                )) ?? []
            }
            let filtered = raw.filter { smart.matchesText($0.preview, ocrText: $0.ocrText) }
            return ClipboardHistorySearchEngine.dedupSamePaste(filtered, limit: 30)
        }

        raw = (try? ClipboardHistoryQueryLoader.load(
            clip: clip,
            search: search,
            query: trimmed,
            limit: 90,
            modifiedOnOrAfter: window.modifiedOnOrAfter
        )) ?? []
        return ClipboardHistorySearchEngine.dedupSamePaste(raw, limit: 30)
    }

    private func readerStructuredFilter(
        _ smart: SmartSearchQuery,
        cutoff: Date?
    ) -> ClipboardHistoryStructuredFilter {
        ClipboardHistoryStructuredFilter(
            appIncludes: smart.appFilters,
            appExcludes: smart.negatedApps,
            typeFilters: smart.typeFilters,
            modifiedOnOrAfter: smart.dateOnOrAfter ?? cutoff
        )
    }
}
