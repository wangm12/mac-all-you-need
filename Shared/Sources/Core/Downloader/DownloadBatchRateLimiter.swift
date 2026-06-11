import Foundation

public enum DownloadBatchRateLimiter {
    private static let douyinAutoBatchThreshold = 50
    private static let douyinAutoSleepSeconds = 1.0

    /// User-configured delay between starting jobs in a bulk enqueue (seconds).
    public static func configuredSleepSeconds() -> Double {
        let stored = AppGroupSettings.defaults.double(forKey: "downloadBatchSleepSeconds")
        return max(0, stored)
    }

    /// Effective stagger delay between bulk job starts.
    public static func effectiveSleepSeconds(kind: DownloadCollectionKind, count: Int) -> Double {
        let configured = configuredSleepSeconds()
        if configured > 0 { return configured }
        if kind == .douyinProfile, count >= douyinAutoBatchThreshold {
            return douyinAutoSleepSeconds
        }
        return 0
    }

    /// Gentle yt-dlp request pacing for playlist batches.
    /// Douyin sleep-requests are now injected directly by YtDlpArgumentBuilder for all Douyin URLs.
    public static func gentleSleepRequestsArgs(kind: DownloadCollectionKind, batchCount: Int) -> [String] {
        switch kind {
        case .playlist:
            return batchCount >= 3 ? ["--sleep-requests", "0.5"] : []
        case .douyinProfile, .multiURL:
            return []
        }
    }
}
