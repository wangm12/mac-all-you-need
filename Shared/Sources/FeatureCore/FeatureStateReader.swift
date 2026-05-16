import Foundation

/// Synchronous, extension-safe reader for a single feature's persisted FeatureRuntimeState.
///
/// FeatureManager is an `actor` and brings non-trivial setup (registry, descriptors, posting
/// Darwin notifications). App extensions like Folder Preview cannot reasonably wait on async
/// actor hops on every preview request and don't need write capability. This helper reads
/// directly from the App Group `UserDefaults` using the SAME key format that
/// `FeatureManager.persistKey(for:)` writes to, so writes from the main app and reads from
/// any extension stay in lockstep.
public enum FeatureStateReader {
    /// Reads `FeatureRuntimeState` for `id` from `defaults`. If the key is missing or its
    /// value cannot be decoded, returns `FeatureRuntimeState.initialDefault(assetRequired:)`.
    /// `assetRequired` defaults to `false` because the only current consumer (Folder Preview)
    /// has no asset pack; pass `true` for asset-pack features.
    public static func read(
        for id: FeatureID,
        defaults: UserDefaults,
        assetRequired: Bool = false
    ) -> FeatureRuntimeState {
        let key = FeatureManager.persistKey(for: id)
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(FeatureRuntimeState.self, from: data)
        else {
            return .initialDefault(assetRequired: assetRequired)
        }
        return decoded
    }
}
