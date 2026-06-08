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
                let candidate = ax.enumerated()
                    .filter { !matchedAXIndices.contains($0.offset) }
                    .min(by: {
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
            let onScreen = !isMinimized && scWin.frame.width >= 120 && scWin.frame.height >= 80
            result.append(DockPreviewWindowEntry(
                id: scWin.windowID,
                pid: pid,
                title: title,
                frame: scWin.frame,
                thumbnail: nil,
                isMinimized: isMinimized,
                isOnScreen: onScreen
            ))
        }

        let scIDs = Set(result.map(\.id))
        for (index, axWin) in ax.enumerated() where !matchedAXIndices.contains(index) {
            if let windowID = axWin.windowID, !scIDs.contains(windowID) {
                result.append(DockPreviewWindowEntry(
                    id: windowID,
                    pid: pid,
                    title: axWin.title.isEmpty ? "Window" : axWin.title,
                    frame: axWin.frame,
                    thumbnail: nil,
                    isMinimized: axWin.isMinimized,
                    isOnScreen: !axWin.isMinimized && axWin.frame.width >= 120 && axWin.frame.height >= 80
                ))
                continue
            }
            guard axWin.isMinimized || axWin.windowID == nil else { continue }
            let wid = axWin.windowID ?? syntheticWindowID(pid: pid, index: index)
            guard !scIDs.contains(wid) else { continue }
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
        var seenIDs = Set<CGWindowID>()
        return entries.filter { seenIDs.insert($0.id).inserted }
    }

    private static func preferredTitle(scTitle: String, axTitle: String?) -> String {
        let ax = axTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let sc = scTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !ax.isEmpty, ax != "Window" { return ax }
        if !sc.isEmpty { return sc }
        if !ax.isEmpty { return ax }
        return "Window"
    }

    private static func syntheticWindowID(pid: pid_t, index: Int) -> CGWindowID {
        var hasher = Hasher()
        hasher.combine(pid)
        hasher.combine(index)
        let mixed = UInt32(bitPattern: Int32(truncatingIfNeeded: hasher.finalize()))
        return CGWindowID(max(1, mixed))
    }

    static func centroidDistance(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let dx = a.midX - b.midX
        let dy = a.midY - b.midY
        return sqrt(dx * dx + dy * dy)
    }
}
