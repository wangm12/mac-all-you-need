import Foundation

public enum DownloadBatchRateLimiter {
    private static let douyinAutoBatchThreshold = 50
    private static let douyinAutoSleepSeconds = 0.25

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

    /// Gentle yt-dlp request pacing for large playlist/profile batches.
    public static func gentleSleepRequestsArgs(kind: DownloadCollectionKind, batchCount: Int) -> [String] {
        guard batchCount >= 10 else { return [] }
        switch kind {
        case .playlist, .douyinProfile:
            return ["--sleep-requests", "0.5"]
        case .multiURL:
            return []
        }
    }
}
