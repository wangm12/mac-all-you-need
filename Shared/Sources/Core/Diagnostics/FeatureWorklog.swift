import Foundation
import os

/// Append-only feature worklogs under the App Group for debugging user-visible behavior.
public enum FeatureWorklog {
    public enum Feature: String, CaseIterable, Sendable {
        case dockPreviews = "dock-previews"
        case voice = "voice"
        case clipboard = "clipboard"
        case windowControl = "window-control"
    }

    private static let logger = Logger(subsystem: Logging.subsystem(for: "diagnostics"), category: "worklog")
    private static let queue = DispatchQueue(label: "com.macallyouneed.feature-worklog", qos: .utility)
    private static let maxFileBytes = 2_000_000
    private static let retentionDays = 7
    private static var lastPruneDay: String?

    private static func worklogsRoot() -> URL {
        AppGroup.containerURL().appendingPathComponent("worklogs", isDirectory: true)
    }

    public static func directory(for feature: Feature) -> URL {
        worklogsRoot().appendingPathComponent(feature.rawValue, isDirectory: true)
    }

    private static func logFileURL(for feature: Feature, on date: Date = Date()) -> URL {
        let day = dayFormatter.string(from: date)
        return directory(for: feature).appendingPathComponent("\(day).log")
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"
        return f
    }()

    /// Records one worklog line. Thread-safe; writes asynchronously.
    public static func log(
        _ feature: Feature,
        _ event: String,
        details: String? = nil,
        file: String = #fileID,
        line: Int = #line
    ) {
        let ts = timestampFormatter.string(from: Date())
        var lineText = "[\(ts)] \(event)"
        if let details, !details.isEmpty {
            lineText += " — \(details)"
        }
        lineText += " (\(file):\(line))"

        logger.debug("\(feature.rawValue, privacy: .public): \(lineText, privacy: .public)")

        queue.async {
            writeLine(lineText, feature: feature)
        }
    }

    /// Records a structured event with `key=value` fields (stable for grep).
    public static func log(
        _ feature: Feature,
        _ event: String,
        fields: [String: CustomStringConvertible],
        file: String = #fileID,
        line: Int = #line
    ) {
        let joined = fields
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        log(feature, event, details: joined, file: file, line: line)
    }

    public static func latestLogFile(for feature: Feature) -> URL? {
        queue.sync {
            latestLogFileOnQueue(for: feature)
        }
    }

    public static func lineCount(for feature: Feature) -> Int {
        queue.sync {
            lineCountOnQueue(for: feature)
        }
    }

    public static func clear(_ feature: Feature) {
        queue.async {
            try? FileManager.default.removeItem(at: directory(for: feature))
        }
    }

    public static func pruneOldLogs() {
        queue.async {
            pruneOldLogsOnQueue()
        }
    }

    // MARK: - Private (must run on `queue` — never call `queue.sync` from here)

    private static func latestLogFileOnQueue(for feature: Feature) -> URL? {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory(for: feature),
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        return files
            .filter { $0.pathExtension == "log" }
            .max { lhs, rhs in
                let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return l < r
            }
    }

    private static func lineCountOnQueue(for feature: Feature) -> Int {
        guard let url = latestLogFileOnQueue(for: feature),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return 0 }
        return text.split(separator: "\n", omittingEmptySubsequences: true).count
    }

    private static func pruneOldLogsOnQueue() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) ?? Date()
        for feature in Feature.allCases {
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: directory(for: feature),
                includingPropertiesForKeys: nil
            ) else { continue }
            for file in files where file.pathExtension == "log" {
                let name = file.deletingPathExtension().lastPathComponent
                guard let day = dayFormatter.date(from: name), day < cutoff else { continue }
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    private static func writeLine(_ line: String, feature: Feature) {
        let day = dayFormatter.string(from: Date())
        if lastPruneDay != day {
            lastPruneDay = day
            pruneOldLogsOnQueue()
        }
        let dir = directory(for: feature)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let url = logFileURL(for: feature)
        guard let data = (line + "\n").data(using: .utf8) else { return }

        if FileManager.default.fileExists(atPath: url.path) {
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            }
            trimIfNeeded(url)
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func trimIfNeeded(_ url: URL) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int,
              size > maxFileBytes,
              let handle = try? FileHandle(forReadingFrom: url)
        else { return }

        let keep = maxFileBytes / 2
        handle.seek(toFileOffset: UInt64(size - keep))
        let tail = handle.readDataToEndOfFile()
        try? handle.close()
        try? tail.write(to: url, options: .atomic)
    }
}
