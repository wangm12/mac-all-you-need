import Core
import FeatureCore
import Foundation

/// One-shot activation migration: `dockPreviews` → `windowHub`.
///
/// Does not migrate Dock Hub settings — only feature enablement. If the user never
/// persisted a `windowHub` runtime state, we copy `dockPreviews` activation when
/// present; otherwise Window Hub defaults to enabled (replacement for Dock Previews).
enum WindowHubFeatureStateMigration {
    private static let doneKey = "windowHub.featureStateMigration.v1.done"
    private static let legacyDockPersistKey = "feature.dockPreviews.runtimeState"

    static func migrateIfNeeded(manager: FeatureManager) async throws {
        let defaults = AppGroupSettings.defaults
        guard !defaults.bool(forKey: doneKey) else { return }
        defer { defaults.set(true, forKey: doneKey) }

        let windowHubKey = FeatureManager.persistKey(for: .windowHub)
        guard defaults.data(forKey: windowHubKey) == nil else { return }

        let activation = legacyActivation(from: defaults) ?? .enabled
        try await manager.setState(
            FeatureRuntimeState(assetState: .notRequired, activationState: activation),
            for: .windowHub
        )
        defaults.removeObject(forKey: legacyDockPersistKey)
    }

    private static func legacyActivation(from defaults: UserDefaults) -> ActivationState? {
        guard let data = defaults.data(forKey: legacyDockPersistKey),
              let state = try? JSONDecoder().decode(FeatureRuntimeState.self, from: data)
        else { return nil }
        return state.activationState
    }
}
