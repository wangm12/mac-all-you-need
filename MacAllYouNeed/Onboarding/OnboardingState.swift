import Core
import FeatureCore
import Foundation

/// Persisted app-install onboarding cursor.
///
/// Choose features → per-feature setup → unified permissions → Done → completed.
/// Per-feature intro/setup runs later via `StandaloneFeatureOnboardingView` when
/// the user enables a feature from the Dashboard (`.featureSetup` is legacy only).
enum OnboardingState: Equatable {
    case notStarted
    case welcome
    case featurePicker
    case unifiedPermissions
    case featureSetup(FeatureID)
    case done
    case completed

    static let key = "onboardingState"

    static func load(defaults: UserDefaults = AppGroupSettings.defaults) -> OnboardingState {
        guard let raw = defaults.string(forKey: key) else { return .notStarted }
        return OnboardingState(rawValue: raw) ?? .notStarted
    }

    func save(defaults: UserDefaults = AppGroupSettings.defaults) {
        defaults.set(rawValue, forKey: Self.key)
    }

    static func reset(defaults: UserDefaults = AppGroupSettings.defaults) {
        defaults.removeObject(forKey: key)
    }

    // MARK: - Raw value coding

    /// Encoded as a single string so we can keep the existing AppGroupSettings layout.
    /// Format: `"featureSetup:voice"` for the parameterised case; bare names for the rest.
    var rawValue: String {
        switch self {
        case .notStarted: return "notStarted"
        case .welcome: return "welcome"
        case .featurePicker: return "featurePicker"
        case .unifiedPermissions: return "unifiedPermissions"
        case .featureSetup(let id): return "featureSetup:\(id.rawValue)"
        case .done: return "done"
        case .completed: return "completed"
        }
    }

    init?(rawValue: String) {
        switch rawValue {
        case "notStarted": self = .notStarted
        case "welcome": self = .welcome
        case "featurePicker": self = .featurePicker
        case "unifiedPermissions": self = .unifiedPermissions
        case "done": self = .done
        case "completed": self = .completed
        default:
            // featureSetup:<id>
            let parts = rawValue.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            if parts.count == 2, parts[0] == "featureSetup", let id = FeatureID(rawValue: String(parts[1])) {
                self = .featureSetup(id)
                return
            }
            // Legacy values ("accessibility", "fullDiskAccess", "notifications", "sync", "ready")
            // are not recognized and coerce to nil → caller uses .notStarted.
            return nil
        }
    }
}

extension OnboardingState: Identifiable {
    var id: String { rawValue }
}
