import ApplicationServices
import Foundation
import Platform

@MainActor
final class DockPreviewRuntime {
    private let coordinator: DockPreviewCoordinator
    private lazy var trustMonitor: WindowControlAccessibilityTrustMonitor = {
        WindowControlAccessibilityTrustMonitor(
            onTrustChanged: { [weak self] trusted in
                self?.handleAccessibilityTrustChanged(trusted)
            },
            shouldPoll: { [weak self] in
                guard let self else { return false }
                return self.featureEnabled && !self.suspendedForHotkeyRecording
            }
        )
    }()

    private var isActive = false
    private var featureEnabled = false
    private var suspendedForHotkeyRecording = false

    init() {
        let engine = SystemAXObserverEngine()
        let axCoordinator = AXObserverCoordinator(engine: engine, healthCheckInterval: 3)
        coordinator = DockPreviewCoordinator(coordinator: axCoordinator)
    }

    func applyEnabled(_ enabled: Bool) {
        featureEnabled = enabled
        reconcileRunningState()
    }

    func reloadSettings() {
        coordinator.reloadSettings()
    }

    func suspendForHotkeyRecording() {
        suspendedForHotkeyRecording = true
        reconcileRunningState()
    }

    func resumeAfterHotkeyRecording() {
        suspendedForHotkeyRecording = false
        reconcileRunningState()
    }

    func refreshPermissions() {
        coordinator.refreshPermissions()
    }

    private func handleAccessibilityTrustChanged(_ trusted: Bool) {
        if trusted {
            reconcileRunningState()
        } else {
            coordinator.stop()
            isActive = false
        }
    }

    private func reconcileRunningState() {
        trustMonitor.start()
        let shouldRun = featureEnabled && !suspendedForHotkeyRecording && AXIsProcessTrusted()
        guard shouldRun != isActive else { return }
        isActive = shouldRun
        if shouldRun {
            coordinator.start()
        } else {
            coordinator.stop()
        }
    }
}
