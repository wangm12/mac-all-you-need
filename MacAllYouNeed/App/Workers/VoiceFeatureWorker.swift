import FeatureCore
import Foundation

/// Serializes deferred voice I/O (retention sweeps, warmup) behind a single actor boundary.
/// ASR engines remain separate actors owned by `VoiceCoordinator`.
actor VoiceFeatureWorker: FeatureWorker {
    private var isRunning = false

    func start() async {
        guard !isRunning else { return }
        isRunning = true
    }

    func stop() async {
        isRunning = false
    }

    func runRetention(_ block: @Sendable () async -> Void) async {
        guard isRunning else { return }
        await block()
    }
}
