import FeatureCore
import Foundation

/// Serializes EventKit reminder writes off the main actor when used.
actor RemindersFeatureWorker: FeatureWorker {
    private var isRunning = false

    func start() async {
        guard !isRunning else { return }
        isRunning = true
    }

    func stop() async {
        isRunning = false
    }

    func performWrite<T: Sendable>(
        _ operation: @Sendable () async throws -> T
    ) async throws -> T {
        guard isRunning else { return try await operation() }
        return try await operation()
    }
}
