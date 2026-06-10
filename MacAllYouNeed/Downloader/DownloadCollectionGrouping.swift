import Core
import Foundation

enum DownloadCollectionGrouping {
    struct Group: Identifiable, Equatable {
        let id: String
        let title: String
        let kind: DownloadCollectionKind?
        let records: [DownloadRecord]

        var completedCount: Int {
            records.filter { $0.state == .completed }.count
        }

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
        for (collectionID, members) in grouped {
            let sorted = members.sorted {
                ($0.collectionIndex ?? Int.max) < ($1.collectionIndex ?? Int.max)
            }
            let title = sorted.first?.collectionTitle?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? "Collection"
            output.append(.group(Group(
                id: collectionID,
                title: title,
                kind: sorted.first?.collectionKind,
                records: sorted
            )))
        }

        output.sort { lhs, rhs in
            latestCreated(lhs) > latestCreated(rhs)
        }

        for record in ungrouped.sorted(by: { $0.created > $1.created }) {
            output.append(.single(record))
        }
        return output
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
            group.records.map(\.created).max() ?? .distantPast
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
