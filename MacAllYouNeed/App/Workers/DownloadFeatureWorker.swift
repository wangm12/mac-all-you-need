import FeatureCore
import Foundation

/// Registry facade — download orchestration already lives in `DownloadQueue` and `DispatchServer`.
actor DownloadFeatureWorker: FeatureWorker {
    private var isRunning = false

    func start() async {
        guard !isRunning else { return }
        isRunning = true
    }

    func stop() async {
        isRunning = false
    }
}
