import Foundation
import Platform

/// Owns the Dock-hover preview runtime: the AX hover observer and the floating
/// preview panel. AppController drives it via `applyEnabled(_:)` whenever the
/// feature's activation state changes. Off by default.
@MainActor
final class DockPreviewRuntime {
    private let coordinator: DockPreviewCoordinator
    private var isActive = false

    init() {
        let engine = SystemAXObserverEngine()
        let axCoordinator = AXObserverCoordinator(engine: engine)
        coordinator = DockPreviewCoordinator(coordinator: axCoordinator)
    }

    /// Starts (or stops) the Dock hover observer to match the feature's enabled
    /// state. Idempotent.
    func applyEnabled(_ enabled: Bool) {
        guard enabled != isActive else { return }
        isActive = enabled
        if enabled {
            coordinator.start()
        } else {
            coordinator.stop()
        }
    }
}
