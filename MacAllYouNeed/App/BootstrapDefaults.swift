import Core
import FeatureCore
import Foundation

/// Seeds first-launch feature state so the app behaves identically to the
/// pre-modular release: all features default to `.enabled`.
///
/// This runs once per install (guarded by `seededKey`). After Phase 11 the
/// onboarding flow will set the seeded flag itself so new installs bypass this.
enum BootstrapDefaults {
    static let seededKey = "feature.bootstrap.seeded"

    static func seedIfNeeded(manager: FeatureManager, defaults: UserDefaults) async throws {
        // Phase 11: if migration already ran, mark seeded and exit — migration owns state.
        if MigrationSentinel.hasMigrated(defaults: defaults) {
            defaults.set(true, forKey: seededKey)
            return
        }
        guard !defaults.bool(forKey: seededKey) else { return }
        for descriptor in await manager.registry.descriptors {
            let asset: AssetState = descriptor.requiresAsset
                ? .present(version: "legacy") // Phase 06 replaces "legacy" with real pack version
                : .notRequired
            try await manager.setState(
                .init(assetState: asset, activationState: .disabled),
                for: descriptor.id
            )
        }
        defaults.set(true, forKey: seededKey)
    }

    /// Clears the "seeded" sentinel. Used by the Debug-only migration reset in Advanced settings.
    static func clearSeeded(defaults: UserDefaults = AppGroupSettings.defaults) {
        defaults.removeObject(forKey: seededKey)
    }
}
