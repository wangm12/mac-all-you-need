import Core
import FeatureCore
import Foundation

enum FeatureOnboardingProgressStore {
    private static func completedKey(for id: FeatureID) -> String {
        "featureOnboarding.completed.\(id.rawValue)"
    }

    static func isCompleted(_ id: FeatureID, defaults: UserDefaults = AppGroupSettings.defaults) -> Bool {
        if id == .voice {
            return VoiceOnboardingProgressStore.load(from: defaults).isCompleted
        }
        return defaults.bool(forKey: completedKey(for: id))
    }

    static func markCompleted(_ id: FeatureID, defaults: UserDefaults = AppGroupSettings.defaults) {
        if id == .voice {
            VoiceOnboardingProgressStore.markCompleted(to: defaults)
            return
        }
        defaults.set(true, forKey: completedKey(for: id))
    }

    static func reset(_ id: FeatureID, defaults: UserDefaults = AppGroupSettings.defaults) {
        if id == .voice {
            VoiceOnboardingProgressStore.reset(in: defaults)
            return
        }
        defaults.removeObject(forKey: completedKey(for: id))
    }

    static func resetAll(registryOrder: [FeatureID], defaults: UserDefaults = AppGroupSettings.defaults) {
        for id in registryOrder {
            reset(id, defaults: defaults)
        }
    }

    static func firstPending(
        in registryOrder: [FeatureID],
        enabled: (FeatureID) -> Bool,
        defaults: UserDefaults = AppGroupSettings.defaults
    ) -> FeatureID? {
        for id in registryOrder where enabled(id) && !isCompleted(id, defaults: defaults) {
            if id == .clipboardSmartText { continue }
            return id
        }
        return nil
    }
}
