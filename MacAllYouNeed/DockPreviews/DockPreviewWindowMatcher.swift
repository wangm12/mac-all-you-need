import CoreGraphics
import Foundation

enum DockPreviewWindowMatcher {
    struct AXWindowInfo {
        let title: String
        let isMinimized: Bool
        let frame: CGRect
        let windowID: CGWindowID?
    }

    struct SCWindowInfo {
        let windowID: CGWindowID
        let frame: CGRect
        let pid: pid_t
        let title: String
    }

    private static let maxMatchDistance: CGFloat = 80

    static func merge(ax: [AXWindowInfo], sc: [SCWindowInfo], pid: pid_t) -> [DockPreviewWindowEntry] {
        var result: [DockPreviewWindowEntry] = []
        var matchedAXIndices = Set<Int>()

        for scWin in sc {
            var matchedIndex: Int?
            if let idIndex = ax.firstIndex(where: { $0.windowID == scWin.windowID }) {
                matchedIndex = idIndex
            } else {
                let candidate = ax.enumerated().min(by: {
                    centroidDistance($0.element.frame, scWin.frame) < centroidDistance($1.element.frame, scWin.frame)
                })
                if let candidate, centroidDistance(candidate.element.frame, scWin.frame) <= maxMatchDistance {
                    matchedIndex = candidate.offset
                }
            }

            let bestAX = matchedIndex.map { ax[$0] }
            if let matchedIndex { matchedAXIndices.insert(matchedIndex) }

            let title = preferredTitle(
                scTitle: scWin.title,
                axTitle: bestAX?.title
            )
            let isMinimized = bestAX?.isMinimized ?? false
            result.append(DockPreviewWindowEntry(
                id: scWin.windowID,
                pid: pid,
                title: title,
                frame: scWin.frame,
                thumbnail: nil,
                isMinimized: isMinimized,
                isOnScreen: true
            ))
        }

        for (index, axWin) in ax.enumerated() where !matchedAXIndices.contains(index) {
            guard axWin.isMinimized || axWin.windowID == nil else { continue }
            let wid = axWin.windowID ?? syntheticWindowID(pid: pid, index: index)
            result.append(DockPreviewWindowEntry(
                id: wid,
                pid: pid,
                title: axWin.title.isEmpty ? "Window" : axWin.title,
                frame: axWin.frame,
                thumbnail: nil,
                isMinimized: axWin.isMinimized,
                isOnScreen: false
            ))
        }
        return deduplicate(result)
    }

    static func deduplicate(_ entries: [DockPreviewWindowEntry]) -> [DockPreviewWindowEntry] {
        var kept: [DockPreviewWindowEntry] = []
        for entry in entries {
            if let index = kept.firstIndex(where: { isDuplicate($0, entry) }) {
                kept[index] = preferredEntry(kept[index], entry)
            } else {
                kept.append(entry)
            }
        }
        return kept
    }

    private static func preferredTitle(scTitle: String, axTitle: String?) -> String {
        let ax = axTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let sc = scTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !ax.isEmpty, ax != "Window" { return ax }
        if !sc.isEmpty { return sc }
        if !ax.isEmpty { return ax }
        return "Window"
    }

    private static func isDuplicate(_ lhs: DockPreviewWindowEntry, _ rhs: DockPreviewWindowEntry) -> Bool {
        if lhs.id == rhs.id { return true }
        return framesOverlapSignificantly(lhs.frame, rhs.frame)
    }

    static func framesOverlapSignificantly(_ a: CGRect, _ b: CGRect) -> Bool {
        let intersection = a.intersection(b)
        guard !intersection.isNull else { return false }
        let minArea = min(a.width * a.height, b.width * b.height)
        guard minArea > 100 else { return false }
        return (intersection.width * intersection.height) / minArea > 0.72
    }

    private static func preferredEntry(
        _ lhs: DockPreviewWindowEntry,
        _ rhs: DockPreviewWindowEntry
    ) -> DockPreviewWindowEntry {
        let lhsScore = titleQuality(lhs.title)
        let rhsScore = titleQuality(rhs.title)
        if rhsScore > lhsScore { return rhs }
        if lhsScore > rhsScore { return lhs }
        return lhs.frame.width * lhs.frame.height >= rhs.frame.width * rhs.frame.height ? lhs : rhs
    }

    private static func titleQuality(_ title: String) -> Int {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "Window" { return 0 }
        return trimmed.count
    }

    private static func syntheticWindowID(pid: pid_t, index: Int) -> CGWindowID {
        CGWindowID((Int(pid) % 10_000) * 10_000 + index + 1)
    }

    static func centroidDistance(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let dx = a.midX - b.midX
        let dy = a.midY - b.midY
        return sqrt(dx * dx + dy * dy)
    }
}
