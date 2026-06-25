import Core
import Foundation

enum DownloadCollectionGrouping {
    struct Group: Identifiable, Equatable {
        let id: String
        let title: String
        let kind: DownloadCollectionKind?
        let records: [DownloadRecord]
        let latestCreated: Date
        let completedCount: Int

        var totalCount: Int { records.count }
    }

    enum ListItem: Identifiable, Equatable {
        case group(Group)
        case single(DownloadRecord)

        var id: String {
            switch self {
            case let .group(group): "group:\(group.id)"
            case let .single(record): "single:\(record.id.rawValue)"
            }
        }
    }

    static func items(from records: [DownloadRecord]) -> [ListItem] {
        var grouped: [String: [DownloadRecord]] = [:]
        var ungrouped: [DownloadRecord] = []

        for record in records {
            if let collectionID = record.collectionID {
                grouped[collectionID, default: []].append(record)
            } else {
                ungrouped.append(record)
            }
        }

        var output: [ListItem] = []
        let groupedKeys = grouped.keys.sorted()
        for collectionID in groupedKeys {
            guard let members = grouped[collectionID] else { continue }
            let sorted = members.sorted {
                let lhs = $0.collectionIndex ?? Int.max
                let rhs = $1.collectionIndex ?? Int.max
                if lhs != rhs { return lhs < rhs }
                return $0.created < $1.created
            }
            let summary = summary(for: sorted)
            let title = sorted.first?.collectionTitle?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? "Collection"
            output.append(.group(Group(
                id: collectionID,
                title: title,
                kind: sorted.first?.collectionKind,
                records: sorted,
                latestCreated: summary.latestCreated,
                completedCount: summary.completed
            )))
        }

        output.sort { lhs, rhs in latestCreated(lhs) > latestCreated(rhs) }

        for record in ungrouped.sorted(by: { $0.created > $1.created }) {
            output.append(.single(record))
        }
        return output
    }

    static func summary(for records: [DownloadRecord]) -> (completed: Int, total: Int, latestCreated: Date) {
        guard let first = records.first else { return (0, 0, .distantPast) }
        var completed = 0
        var latestCreated = first.created
        for record in records {
            if record.state == .completed { completed += 1 }
            if record.created > latestCreated { latestCreated = record.created }
        }
        return (completed, records.count, latestCreated)
    }

    static func aggregateProgress(
        records: [DownloadRecord],
        liveProgress: [String: DownloadProgress]
    ) -> Double {
        guard !records.isEmpty else { return 0 }
        let sum = records.reduce(0.0) { partial, record in
            if record.state == .completed { return partial + 1 }
            if let progress = liveProgress[record.id.rawValue] {
                return partial + min(1, max(0, progress.fraction))
            }
            if let total = record.bytesTotal, total > 0 {
                return partial + min(1, Double(record.bytesDownloaded) / Double(total))
            }
            return partial
        }
        return sum / Double(records.count)
    }

    static func aggregateSpeedBytes(
        records: [DownloadRecord],
        liveProgress: [String: DownloadProgress]
    ) -> Double {
        records.reduce(0) { partial, record in
            guard record.state == .running else { return partial }
            return partial + (liveProgress[record.id.rawValue]?.speedBytesPerSec ?? 0)
        }
    }

    static func groupSubtitle(for group: Group) -> String {
        let countLabel = group.kind == .douyinProfile ? "posts" : "videos"
        let typeLabel = group.kind == .douyinProfile ? "Douyin profile" : "Playlist"
        return "\(typeLabel) · \(group.totalCount) \(countLabel)"
    }

    private static func latestCreated(_ item: ListItem) -> Date {
        switch item {
        case let .group(group):
            group.latestCreated
        case let .single(record):
            record.created
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
