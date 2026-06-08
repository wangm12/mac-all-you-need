import FeatureCore
import Foundation

/// Serializes file-organizer scan + manifest I/O off the main actor when used.
actor OrganizerFeatureWorker: FeatureWorker {
    private var isRunning = false

    func start() async {
        guard !isRunning else { return }
        isRunning = true
    }

    func stop() async {
        isRunning = false
    }

    func perform<T: Sendable>(
        _ operation: @Sendable () async -> T
    ) async -> T {
        guard isRunning else { return await operation() }
        return await operation()
    }
}
