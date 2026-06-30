import Core
import Foundation
import SwiftUI

enum DownloadCollectionPresentation {
    enum CollectionStatus: Equatable {
        case done
        case downloading
        case paused
        case failed
        case mixed

        var label: String {
            switch self {
            case .done: "Done"
            case .downloading: "Downloading"
            case .paused: "Paused"
            case .failed: "Failed"
            case .mixed: "In progress"
            }
        }

        var pillKind: StatusPill.Kind {
            switch self {
            case .done: .success
            case .downloading: .progress
            case .paused: .warning
            case .failed: .danger
            case .mixed: .neutral
            }
        }
    }

    static func status(
        for group: DownloadCollectionGrouping.Group,
        hasActive: Bool,
        progress: Double
    ) -> CollectionStatus {
        if group.completedCount == group.totalCount, progress >= 1 {
            return .done
        }
        if hasActive {
            return .downloading
        }
        if group.records.contains(where: { $0.state == .failed }) {
            return .failed
        }
        if group.records.contains(where: { $0.state == .paused }) {
            return .paused
        }
        return .mixed
    }

    static func deleteSheetStatus(
        for group: DownloadCollectionGrouping.Group,
        hasActive: Bool,
        progress: Double
    ) -> String {
        switch status(for: group, hasActive: hasActive, progress: progress) {
        case .done: "Completed"
        case .downloading: "Downloading"
        case .paused: "Paused"
        case .failed: "Failed"
        case .mixed: "In progress"
        }
    }

    static func deleteSheetItemLabel(count: Int, kind: DownloadCollectionKind?) -> String {
        let noun = kind == .douyinProfile ? "post" : "video"
        return "\(count) \(noun)\(count == 1 ? "" : "s")"
    }

    static func locationLabel(
        for group: DownloadCollectionGrouping.Group,
        downloadDir: String
    ) -> String {
        humanReadablePath(collectionFolderURL(for: group, downloadDir: downloadDir))
    }

    static func collectionFolderURL(
        for group: DownloadCollectionGrouping.Group,
        downloadDir: String
    ) -> URL {
        folderURL(for: group, downloadDir: downloadDir)
    }

    static func expandedSubtitle(
        for group: DownloadCollectionGrouping.Group,
        location: String
    ) -> String {
        let countLabel = group.kind == .douyinProfile ? "posts" : "videos"
        let typeLabel = group.kind == .douyinProfile ? "Douyin profile" : "Playlist"
        return "\(typeLabel) · \(group.totalCount) \(countLabel) · Saved to \(location)"
    }

    static func headerSubtitle(
        for group: DownloadCollectionGrouping.Group,
        location: String,
        hasActive: Bool
    ) -> String {
        let countLabel = group.kind == .douyinProfile ? "posts" : "videos"
        let typeLabel = group.kind == .douyinProfile ? "Douyin profile" : "Playlist"
        if hasActive {
            let remaining = max(0, group.totalCount - group.completedCount)
            return "\(typeLabel) · \(group.completedCount) of \(group.totalCount) \(countLabel) · \(remaining) remaining"
        }
        return expandedSubtitle(for: group, location: location)
    }

    static func expandedHint(
        for group: DownloadCollectionGrouping.Group,
        hasActive: Bool,
        progress: Double
    ) -> String {
        "Manage individual downloads in this collection."
    }

    static func progressFillWidth(totalWidth: CGFloat, progress: Double) -> CGFloat {
        guard progress > 0 else { return 0 }
        return max(1, totalWidth * min(1, max(0, progress)))
    }

    static func progressBarColor(for status: CollectionStatus) -> Color {
        switch status {
        case .done:
            MAYNTheme.success
        case .downloading:
            MAYNTheme.progress
        case .paused:
            Color.secondary.opacity(0.45)
        case .failed:
            Color.secondary.opacity(0.35)
        case .mixed:
            MAYNTheme.progress.opacity(0.65)
        }
    }

    static func primaryActionTitle(
        status: CollectionStatus,
        showsPauseAll: Bool,
        showsResumeAll: Bool
    ) -> String? {
        if showsPauseAll { return "Pause" }
        if status == .failed { return "Retry" }
        if showsResumeAll { return "Resume" }
        return nil
    }

    static func sourceURL(for group: DownloadCollectionGrouping.Group) -> String? {
        guard let first = group.records.first else { return nil }
        let candidate = first.pageURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !candidate.isEmpty { return candidate }
        let url = first.url.trimmingCharacters(in: .whitespacesAndNewlines)
        return url.isEmpty ? nil : url
    }

    // MARK: - Private

    private static func folderURL(
        for group: DownloadCollectionGrouping.Group,
        downloadDir: String
    ) -> URL {
        if let first = group.records.first {
            let path = first.destinationPath
            if !path.contains("%(") {
                return URL(fileURLWithPath: path).deletingLastPathComponent()
            }
        }

        let useSubfolder = AppGroupSettings.defaults.object(forKey: "downloadCollectionSubfolder") as? Bool ?? true
        let basePath = DownloadDestinationPresentation.effectivePath(downloadDir: downloadDir)
        let baseURL = URL(fileURLWithPath: basePath, isDirectory: true)
        if useSubfolder {
            let folderName = DownloadDestinationBuilder.sanitizeFolderName(group.title)
            return baseURL.appendingPathComponent(folderName, isDirectory: true)
        }
        return baseURL
    }

    private static func humanReadablePath(_ url: URL) -> String {
        let path = url.path
        if let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path,
           path.hasPrefix(downloads)
        {
            let suffix = String(path.dropFirst(downloads.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if suffix.isEmpty { return "Downloads" }
            return "Downloads / \(suffix)"
        }

        let components = url.pathComponents.filter { $0 != "/" }
        if components.count >= 2 {
            return components.suffix(2).joined(separator: " / ")
        }
        if components.count == 1 {
            return components[0]
        }
        return components.last ?? path
    }

    static func compactMetaLine(
        for group: DownloadCollectionGrouping.Group,
        location: String
    ) -> String {
        let countLabel = group.kind == .douyinProfile ? "posts" : "videos"
        let typeLabel = group.kind == .douyinProfile ? "Douyin profile" : "Playlist"
        return "\(typeLabel) · \(group.totalCount) \(countLabel) · \(location)"
    }

    static func singleLocationLabel(for record: DownloadRecord, downloadDir: String) -> String {
        let path = record.destinationPath
        if !path.contains("%(") {
            return humanReadablePath(URL(fileURLWithPath: path).deletingLastPathComponent())
        }
        let basePath = DownloadDestinationPresentation.effectivePath(downloadDir: downloadDir)
        return humanReadablePath(URL(fileURLWithPath: basePath, isDirectory: true))
    }

    static func singleCompactMetaLine(for record: DownloadRecord, location: String) -> String {
        if let channel = record.channelName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            return "Video · \(channel) · \(location)"
        }
        return "Video · 1 video · \(location)"
    }

    static func singleStatus(for record: DownloadRecord) -> (label: String, pillKind: StatusPill.Kind) {
        switch record.state {
        case .completed:
            ("Done", .success)
        case .running:
            ("Downloading", .progress)
        case .paused:
            ("Paused", .warning)
        case .failed:
            ("Failed", .danger)
        case .queued:
            ("Queued", .neutral)
        }
    }

    static func singlePrimaryActionTitle(
        for record: DownloadRecord,
        showsPause: Bool,
        showsResume: Bool
    ) -> String? {
        if showsPause { return "Pause" }
        if record.state == .failed { return "Retry" }
        if showsResume { return "Resume" }
        return nil
    }
}
