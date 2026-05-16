import FeatureCore
import Foundation

/// Owns the Voice subsystem's lifecycle.
///
/// In production this wraps the same init/start/stop code that AppController
/// has always run. In testMode=true every real system call (microphone,
/// CGEventTap, activation monitor) is skipped so unit tests don't require
/// Microphone or Accessibility permissions.
///
/// Note: VoiceCoordinator requires store dependencies that are still owned
/// by AppController. In testMode the activator tracks state with a Bool flag.
/// Phase 04 will complete dependency injection so production activate() can
/// create and start VoiceCoordinator independently.
public actor VoiceFeatureActivator: FeatureActivator {
    private var _isCoordinatorRunning: Bool = false
    private let testMode: Bool

    /// True while the voice coordinator (or test-mode stub) is running.
    public var isCoordinatorRunning: Bool { _isCoordinatorRunning }

    public init(testMode: Bool = false) {
        self.testMode = testMode
    }

    public func activate() async throws {
        guard !_isCoordinatorRunning else { return }   // idempotent
        _isCoordinatorRunning = true

        if !testMode {
            // VoiceCoordinator is still owned by AppController and started on launch.
            // Phase 04 will thread the coordinator through dependency injection so the
            // activator can own its full lifecycle. Until then, this records the intent.
        }
    }

    public func deactivate() async throws {
        guard _isCoordinatorRunning else { return }   // idempotent
        _isCoordinatorRunning = false

        if !testMode {
            // Phase 04 will add: coordinator?.suspendActivationMonitoring(); coordinator = nil
        }
    }
}
