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
        guard !defaults.bool(forKey: seededKey) else { return }
        for descriptor in await manager.registry.descriptors {
            let asset: AssetState = descriptor.requiresAsset
                ? .present(version: "legacy") // Phase 06 replaces "legacy" with real pack version
                : .notRequired
            try await manager.setState(
                .init(assetState: asset, activationState: .enabled),
                for: descriptor.id
            )
        }
        defaults.set(true, forKey: seededKey)
    }
}
