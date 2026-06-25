import Core
import FeatureCore
import Foundation

/// Seeds first-launch feature activation state once per install (guarded by `seededKey`).
///
/// Core productivity features default to enabled; AI File Organizer defaults to disabled.
/// Window Hub replaces Dock Previews and is enabled by default.
enum BootstrapDefaults {
    static let seededKey = "feature.bootstrap.seeded"

    /// Features enabled on a fresh install before the user changes anything.
    static let defaultEnabled: Set<FeatureID> = [
        .clipboard,
        .clipboardSmartText,
        .voice,
        .voiceReminders,
        .downloader,
        .folderPreview,
        .folderHistory,
        .windowLayouts,
        .windowGrab,
        .windowHub,
    ]

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
            let activation: ActivationState = defaultEnabled.contains(descriptor.id)
                ? .enabled
                : .disabled
            try await manager.setState(
                .init(assetState: asset, activationState: activation),
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
