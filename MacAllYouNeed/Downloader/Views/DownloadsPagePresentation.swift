import Core
import Foundation

enum DownloadsPageViewMode: String, CaseIterable, SegmentedTabDestination {
    case grouped
    case list

    var title: String {
        switch self {
        case .grouped: "Collections"
        case .list: "Items"
        }
    }

    var symbolName: String {
        switch self {
        case .grouped: "rectangle.stack"
        case .list: "list.bullet"
        }
    }
}

enum DownloadsStatusFilter: String, CaseIterable, Identifiable {
    case all
    case completed
    case active
    case paused
    case failed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .completed: "Completed"
        case .active: "Active"
        case .paused: "Paused"
        case .failed: "Failed"
        }
    }

    var dotColor: DownloadsStatusDotColor {
        switch self {
        case .all: .neutral
        case .completed: .success
        case .active: .progress
        case .paused: .warning
        case .failed: .danger
        }
    }

    func includes(_ state: DownloadState) -> Bool {
        switch self {
        case .all:
            true
        case .completed:
            state == .completed
        case .active:
            state == .running || state == .queued
        case .paused:
            state == .paused
        case .failed:
            state == .failed
        }
    }

    func count(in rows: [DownloadRecord]) -> Int {
        rows.filter { includes($0.state) }.count
    }
}

enum DownloadsStatusDotColor {
    case neutral
    case success
    case progress
    case warning
    case danger
}

enum DownloadCollectionItemFilter: String, CaseIterable, Identifiable {
    case all
    case paused
    case failed
    case completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .paused: "Paused"
        case .failed: "Failed"
        case .completed: "Completed"
        }
    }

    func includes(_ state: DownloadState) -> Bool {
        switch self {
        case .all:
            true
        case .paused:
            state == .paused
        case .failed:
            state == .failed
        case .completed:
            state == .completed
        }
    }
}

struct DownloadsPageMetrics: Equatable {
    let totalVideos: Int
    let completed: Int
    let activeCount: Int
    let pausedCount: Int
    let failedCount: Int
}

enum DownloadsPagePresentation {
    static func metrics(rows: [DownloadRecord]) -> DownloadsPageMetrics {
        DownloadsPageMetrics(
            totalVideos: rows.count,
            completed: rows.filter { $0.state == .completed }.count,
            activeCount: rows.filter { $0.state == .running || $0.state == .queued }.count,
            pausedCount: rows.filter { $0.state == .paused }.count,
            failedCount: rows.filter { $0.state == .failed }.count
        )
    }

    static func filterRows(
        _ rows: [DownloadRecord],
        statusFilter: DownloadsStatusFilter,
        query: String
    ) -> [DownloadRecord] {
        let statusFiltered = rows.filter { statusFilter.includes($0.state) }
        return searchRows(statusFiltered, query: query)
    }

    static func searchRows(_ rows: [DownloadRecord], query: String) -> [DownloadRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return rows }
        let needle = trimmed.lowercased()
        return rows.filter { record in
            let haystack = [
                record.videoTitle,
                record.title,
                record.channelName,
                record.url,
                record.pageURL,
                record.collectionTitle,
                record.destinationPath
            ]
            .compactMap { $0?.lowercased() }
            return haystack.contains { $0.contains(needle) }
        }
    }

    static func listItems(
        from rows: [DownloadRecord],
        mode: DownloadsPageViewMode
    ) -> [DownloadCollectionGrouping.ListItem] {
        switch mode {
        case .grouped:
            return DownloadCollectionGrouping.items(from: rows)
        case .list:
            return rows
                .sorted { $0.modified > $1.modified }
                .map { .single($0) }
        }
    }

    static func sectionTitle(mode: DownloadsPageViewMode, hasGroups: Bool) -> String {
        switch mode {
        case .grouped where hasGroups:
            "Collections"
        case .grouped:
            "Downloads"
        case .list:
            "Items"
        }
    }

    static func failedBannerTitle(failedCount: Int) -> String {
        failedCount == 1 ? "1 download failed" : "\(failedCount) downloads failed"
    }
}
