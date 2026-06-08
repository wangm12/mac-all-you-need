import FeatureCore
import Foundation

/// Composition root for the modular feature system.
/// A single instance lives on AppController.
///
/// `FeatureRuntime` owns the registry + manager + the set of currently-active
/// feature IDs. Callers drive it via `activateAllEnabled()` on launch and
/// `applyTransition(_:for:)` for user-initiated enable/disable.
public actor FeatureRuntime {
    public let registry: FeatureRegistry
    public let manager: FeatureManager
    private weak var workerHost: AppFeatureWorkerHost?
    private var active: Set<FeatureID> = []

    init(registry: FeatureRegistry, manager: FeatureManager, workerHost: AppFeatureWorkerHost? = nil) {
        self.registry = registry
        self.manager = manager
        self.workerHost = workerHost
    }

    public func isActive(_ id: FeatureID) -> Bool {
        active.contains(id)
    }

    /// Called once on app launch. Iterates enabled features and calls their activator.
    public func activateAllEnabled() async {
        for descriptor in registry.descriptors {
            let state = await manager.state(for: descriptor.id)
            guard state.activationState == .enabled else { continue }
            do {
                try await descriptor.activator.activate()
                active.insert(descriptor.id)
                await startWorker(for: descriptor.id)
            } catch {
                // On activation failure, demote to disabled but preserve asset state.
                try? await manager.transition(.disable, for: descriptor.id)
                NSLog("[FeatureRuntime] Feature \(descriptor.id) activation failed: \(error)")
            }
        }
    }

    /// Called on app quit. Deactivates all active features.
    public func deactivateAll() async {
        for descriptor in registry.descriptors where active.contains(descriptor.id) {
            await stopWorker(for: descriptor.id)
            try? await descriptor.activator.deactivate()
            active.remove(descriptor.id)
        }
        if let workerHost {
            await workerHost.deactivateAll()
        }
    }

    /// Drives a user-initiated state change. Persists state AND calls activator side-effects.
    public func applyTransition(
        _ transition: FeatureManager.Transition,
        for id: FeatureID
    ) async throws {
        try await manager.transition(transition, for: id)
        guard let descriptor = registry.descriptor(for: id) else { return }
        switch transition {
        case .enable:
            if !active.contains(id) {
                try await descriptor.activator.activate()
                active.insert(id)
                await startWorker(for: id)
            }
        case .disable:
            if active.contains(id) {
                await stopWorker(for: id)
                try await descriptor.activator.deactivate()
                active.remove(id)
            }
        }
        NotificationCenter.default.post(name: .featureRuntimeStateChanged, object: nil)
    }

    private func startWorker(for id: FeatureID) async {
        guard let workerHost else { return }
        await workerHost.startWorker(for: id)
    }

    private func stopWorker(for id: FeatureID) async {
        guard let workerHost else { return }
        await workerHost.stopWorker(for: id)
    }
}
