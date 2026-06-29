import Foundation

enum WindowHubMasonryPacker {
    static let columnBreakpoint: CGFloat = 760
    static let columnGap: CGFloat = 12
    static let cardGap: CGFloat = 10
    static let contentPadding: CGFloat = 12

    private static let headerHeight = 36
    private static let rowHeight = 29
    private static let groupHeaderHeight = 26
    private static let showAllRowHeight = 28
    private static let cardPadding = 18

    static func columnCount(for width: CGFloat, maxColumns: Int = 2) -> Int {
        guard width >= columnBreakpoint else { return 1 }
        return min(maxColumns, 2)
    }

    static func prioritySorted(
        _ sections: [WindowHubAppSection],
        frontPID: pid_t?,
        currentTargetID: WindowHubTargetID?,
        recentTargetIDs: [WindowHubTargetID]
    ) -> [WindowHubAppSection] {
        sections.sorted { lhs, rhs in
            let lhsScore = priorityScore(
                section: lhs,
                frontPID: frontPID,
                currentTargetID: currentTargetID,
                recentTargetIDs: recentTargetIDs
            )
            let rhsScore = priorityScore(
                section: rhs,
                frontPID: frontPID,
                currentTargetID: currentTargetID,
                recentTargetIDs: recentTargetIDs
            )
            if lhsScore != rhsScore { return lhsScore > rhsScore }
            return lhs.appName.localizedCaseInsensitiveCompare(rhs.appName) == .orderedAscending
        }
    }

    static func pack(
        sections: [WindowHubAppSection],
        columnCount: Int,
        expandedGroupIDs: Set<String>,
        isBrowser: (WindowHubAppSection) -> Bool
    ) -> [[WindowHubAppSection]] {
        guard columnCount > 0 else { return [sections] }
        var columns = Array(repeating: [WindowHubAppSection](), count: columnCount)
        var heights = Array(repeating: 0, count: columnCount)

        for section in sections {
            let index = heights.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0
            columns[index].append(section)
            heights[index] += estimatedHeight(
                of: section,
                expandedGroupIDs: expandedGroupIDs,
                isBrowser: isBrowser(section)
            ) + Int(cardGap)
        }
        return columns
    }

    static func flatTargets(
        in columns: [[WindowHubAppSection]],
        expandedGroupIDs: Set<String>,
        isBrowser: (WindowHubAppSection) -> Bool
    ) -> [WindowHubTarget] {
        columns.flatMap { column in
            column.flatMap { section in
                visibleTargets(
                    in: section,
                    expandedGroupIDs: expandedGroupIDs,
                    isBrowser: isBrowser(section)
                )
            }
        }
    }

    static func visibleTargets(
        in section: WindowHubAppSection,
        expandedGroupIDs: Set<String>,
        isBrowser: Bool
    ) -> [WindowHubTarget] {
        let showGroupHeaders = isBrowser && section.windowGroups.count > 1
        return section.windowGroups.flatMap { group in
            presentationRows(
                group: group,
                showGroupHeader: showGroupHeaders,
                isExpanded: expandedGroupIDs.contains(group.id),
                isBrowser: isBrowser
            ).compactMap(\.target)
        }
    }

    static func presentationRows(
        group: WindowHubWindowGroup,
        showGroupHeader: Bool,
        isExpanded: Bool,
        isBrowser: Bool
    ) -> [WindowHubPresentationRow] {
        var rows: [WindowHubPresentationRow] = []
        if showGroupHeader {
            rows.append(.groupHeader)
        }

        let tabTargets = group.visibleTargets.filter { $0.kind == .tab }
        let isTabbed = !tabTargets.isEmpty
        let orderedTargets: [WindowHubTarget]
        if isTabbed {
            let active = tabTargets.filter(\.isActive)
            let rest = tabTargets.filter { !$0.isActive }
            orderedTargets = active + rest
        } else {
            orderedTargets = group.visibleTargets
        }

        let totalTabs = tabTargets.count + group.hiddenTabCount
        let shownTargets: [WindowHubTarget]

        if isExpanded || totalTabs <= 12 {
            shownTargets = orderedTargets
        } else if totalTabs <= 50 {
            shownTargets = collapsedTargets(from: orderedTargets, recentCap: 8)
        } else {
            shownTargets = collapsedTargets(from: orderedTargets, recentCap: 6)
        }

        let displayedTabCount = shownTargets.filter { $0.kind == .tab }.count
        let includesShowAll = isTabbed && (isExpanded || totalTabs > max(12, displayedTabCount))

        rows.append(contentsOf: shownTargets.map { .target($0) })
        if includesShowAll, isTabbed {
            rows.append(.showAll(totalTabs))
        }
        return rows
    }

    private static func collapsedTargets(from ordered: [WindowHubTarget], recentCap: Int) -> [WindowHubTarget] {
        let tabs = ordered.filter { $0.kind == .tab }
        let windows = ordered.filter { $0.kind != .tab }
        let active = tabs.filter(\.isActive)
        let inactive = tabs.filter { !$0.isActive }
        let recent = Array(inactive.prefix(recentCap))
        var seen = Set<WindowHubTargetID>()
        return (windows + active + recent).filter { seen.insert($0.id).inserted }
    }

    private static func priorityScore(
        section: WindowHubAppSection,
        frontPID: pid_t?,
        currentTargetID: WindowHubTargetID?,
        recentTargetIDs: [WindowHubTargetID]
    ) -> Int {
        var score = 0
        if let frontPID, section.pid == frontPID { score += 10_000 }
        if let currentTargetID,
           section.windowGroups.contains(where: { group in
               group.visibleTargets.contains(where: { $0.id == currentTargetID })
           })
        {
            score += 5_000
        }
        if let recentIndex = recentTargetIDs.firstIndex(where: { id in
            section.windowGroups.contains { group in
                group.visibleTargets.contains { $0.id == id }
            }
        }) {
            score += max(0, 1_000 - recentIndex * 100)
        }
        let tabCount = WindowHubSectionMetrics.tabCount(in: section)
        if tabCount > 0 { score += min(tabCount, 500) }
        if !section.windowGroups.isEmpty { score += 100 }
        return score
    }

    static func estimatedHeight(
        of section: WindowHubAppSection,
        expandedGroupIDs: Set<String>,
        isBrowser: Bool
    ) -> Int {
        let showGroupHeaders = isBrowser && section.windowGroups.count > 1
        var units = headerHeight + cardPadding
        for group in section.windowGroups {
            let rows = presentationRows(
                group: group,
                showGroupHeader: showGroupHeaders,
                isExpanded: expandedGroupIDs.contains(group.id),
                isBrowser: isBrowser
            )
            for row in rows {
                switch row {
                case .groupHeader:
                    units += groupHeaderHeight
                case .target:
                    units += rowHeight
                case .showAll:
                    units += showAllRowHeight
                }
            }
        }
        return units
    }
}

enum WindowHubPresentationRow: Equatable {
    case groupHeader
    case target(WindowHubTarget)
    case showAll(Int)

    var target: WindowHubTarget? {
        if case .target(let target) = self { return target }
        return nil
    }
}
