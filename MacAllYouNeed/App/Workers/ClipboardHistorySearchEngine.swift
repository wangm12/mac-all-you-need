import Core
import Foundation
import Platform

/// Off-main clipboard history load + rank. Used by `ClipboardWorker`.
enum ClipboardHistorySearchEngine {
    struct LoadRequest: Sendable {
        var query: String?
        var limit: Int
        var fuzzyEnabled: Bool
    }

    static func load(
        clip: ClipboardStore,
        search: SearchStore?,
        request: LoadRequest
    ) throws -> [ClipboardXPCMeta] {
        let signpost = PerformanceSignpost.Clipboard.beginHistoryLoad()
        defer { PerformanceSignpost.Clipboard.endHistoryLoad(signpost) }

        let window = ClipboardHistoryWindow.listParameters()
        let fetchLimit = max(request.limit * 3, request.limit + 30)
        let trimmed = request.query?.trimmingCharacters(in: .whitespacesAndNewlines)
        let smart = trimmed.map { SmartSearchQuery($0) }
        let hasSmart = smart?.hasOperators ?? false
        let loadBroadly = request.fuzzyEnabled || hasSmart

        let raw: [ClipboardItemMeta]
        if loadBroadly {
            let structured = structuredFilter(from: smart, fallbackCutoff: window.modifiedOnOrAfter)
            let freeQuery = smart?.freeText.trimmingCharacters(in: .whitespacesAndNewlines)
            let effectiveFree = (freeQuery?.isEmpty ?? true) ? nil : freeQuery
            if hasSmart, effectiveFree == nil, !(smart?.isRegex ?? false) {
                raw = try ClipboardHistoryQueryLoader.loadRecentStructured(
                    clip: clip,
                    limit: fetchLimit,
                    modifiedOnOrAfter: window.modifiedOnOrAfter,
                    structured: structured
                )
            } else {
                raw = try ClipboardHistoryQueryLoader.load(
                    clip: clip,
                    search: search,
                    query: effectiveFree ?? trimmed,
                    limit: fetchLimit,
                    modifiedOnOrAfter: window.modifiedOnOrAfter,
                    structured: structured
                )
            }
        } else {
            raw = try ClipboardHistoryQueryLoader.load(
                clip: clip,
                search: search,
                query: trimmed,
                limit: fetchLimit,
                modifiedOnOrAfter: window.modifiedOnOrAfter
            )
        }

        var metas = dedupSamePaste(raw, limit: request.limit)
        metas = applyTextFilters(metas, smart: smart, trimmed: trimmed, fuzzyEnabled: request.fuzzyEnabled)
        return metas.map { xpcMeta(from: $0) }
    }

    static func loadMetas(
        clip: ClipboardStore,
        search: SearchStore?,
        request: LoadRequest
    ) throws -> [ClipboardItemMeta] {
        let signpost = PerformanceSignpost.Clipboard.beginHistoryLoad()
        defer { PerformanceSignpost.Clipboard.endHistoryLoad(signpost) }

        let window = ClipboardHistoryWindow.listParameters()
        let fetchLimit = max(request.limit * 3, request.limit + 30)
        let trimmed = request.query?.trimmingCharacters(in: .whitespacesAndNewlines)
        let smart = trimmed.map { SmartSearchQuery($0) }
        let hasSmart = smart?.hasOperators ?? false
        let loadBroadly = request.fuzzyEnabled || hasSmart

        let raw: [ClipboardItemMeta]
        if loadBroadly {
            let structured = structuredFilter(from: smart, fallbackCutoff: window.modifiedOnOrAfter)
            let freeQuery = smart?.freeText.trimmingCharacters(in: .whitespacesAndNewlines)
            let effectiveFree = (freeQuery?.isEmpty ?? true) ? nil : freeQuery
            if hasSmart, effectiveFree == nil, !(smart?.isRegex ?? false) {
                raw = try ClipboardHistoryQueryLoader.loadRecentStructured(
                    clip: clip,
                    limit: fetchLimit,
                    modifiedOnOrAfter: window.modifiedOnOrAfter,
                    structured: structured
                )
            } else {
                raw = try ClipboardHistoryQueryLoader.load(
                    clip: clip,
                    search: search,
                    query: effectiveFree ?? trimmed,
                    limit: fetchLimit,
                    modifiedOnOrAfter: window.modifiedOnOrAfter,
                    structured: structured
                )
            }
        } else {
            raw = try ClipboardHistoryQueryLoader.load(
                clip: clip,
                search: search,
                query: trimmed,
                limit: fetchLimit,
                modifiedOnOrAfter: window.modifiedOnOrAfter
            )
        }

        var metas = dedupSamePaste(raw, limit: request.limit)
        return applyTextFilters(metas, smart: smart, trimmed: trimmed, fuzzyEnabled: request.fuzzyEnabled)
    }

    static func loadByIDs(clip: ClipboardStore, ids: [String]) throws -> [ClipboardXPCMeta] {
        let signpost = PerformanceSignpost.Clipboard.beginHistoryLoad()
        defer { PerformanceSignpost.Clipboard.endHistoryLoad(signpost) }
        let recordIDs = ids.compactMap(RecordID.init(rawValue:))
        let metas = try clip.metas(for: recordIDs)
        return metas.map { xpcMeta(from: $0) }
    }

    private static func structuredFilter(
        from smart: SmartSearchQuery?,
        fallbackCutoff: Date?
    ) -> ClipboardHistoryStructuredFilter {
        guard let smart else {
            return ClipboardHistoryStructuredFilter(modifiedOnOrAfter: fallbackCutoff)
        }
        return ClipboardHistoryStructuredFilter(
            appIncludes: smart.appFilters,
            appExcludes: smart.negatedApps,
            typeFilters: smart.typeFilters,
            modifiedOnOrAfter: smart.dateOnOrAfter ?? fallbackCutoff
        )
    }

    private static func applyTextFilters(
        _ metas: [ClipboardItemMeta],
        smart: SmartSearchQuery?,
        trimmed: String?,
        fuzzyEnabled: Bool
    ) -> [ClipboardItemMeta] {
        guard let smart, smart.hasOperators else {
            if fuzzyEnabled, let trimmed, !trimmed.isEmpty {
                return rankFuzzy(metas: metas, query: trimmed)
            }
            return metas
        }
        return metas.filter { meta in
            smart.matchesText(meta.preview, ocrText: meta.ocrText)
        }
    }

    private static func rankFuzzy(metas: [ClipboardItemMeta], query: String) -> [ClipboardItemMeta] {
        let ranked = FuzzyMatcher.rank(candidates: metas.map(\.preview), query: query)
        var orderByPreview: [String: Int] = [:]
        for (rank, preview) in ranked.enumerated() {
            if orderByPreview[preview] == nil { orderByPreview[preview] = rank }
        }
        return metas
            .filter { orderByPreview[$0.preview] != nil }
            .sorted { (orderByPreview[$0.preview] ?? .max) < (orderByPreview[$1.preview] ?? .max) }
    }

    static func dedupSamePaste(_ sortedNewestFirst: [ClipboardItemMeta], limit: Int) -> [ClipboardItemMeta] {
        var result: [ClipboardItemMeta] = []
        for item in sortedNewestFirst {
            if let last = result.last,
               abs(last.modified.timeIntervalSince(item.modified)) < 0.5
            {
                if pastePriority(item.preview) > pastePriority(last.preview) {
                    result[result.count - 1] = item
                }
                continue
            }
            result.append(item)
            if result.count >= limit { break }
        }
        return result
    }

    private static func pastePriority(_ preview: String) -> Int {
        if preview.hasPrefix("(") && preview.contains("file") { return 2 }
        if preview.hasPrefix("(image ") { return 1 }
        return 0
    }

    /// List metadata without decrypting image bodies (lazy load in `ImageBlobLoader`).
    static func xpcMeta(from meta: ClipboardItemMeta) -> ClipboardXPCMeta {
        ClipboardXPCMeta(
            id: meta.id.rawValue,
            modified: meta.modified,
            kind: meta.kind.rawValue,
            preview: meta.preview,
            sourceAppBundleID: meta.sourceAppBundleID,
            imageWidth: 0,
            imageHeight: 0,
            imageBlobID: nil,
            customLabel: meta.customLabel,
            detectedTypeJSON: meta.detectedTypeJSON,
            ocrText: meta.ocrText
        )
    }
}
