import FeatureCore
import Foundation

/// Pure navigation helpers for the app-install onboarding wizard (unit-testable).
enum OnboardingNavigationPlanner {
    static func previousFeatureID(
        before id: FeatureID,
        selectedIDs: [FeatureID],
        pickerOrder: [FeatureID]
    ) -> FeatureID? {
        let order = pickerOrder.filter { selectedIDs.contains($0) }
        guard let idx = order.firstIndex(of: id), idx > 0 else { return nil }
        return order[idx - 1]
    }

    static func isRevisit(
        featureID: FeatureID,
        completedIDs: Set<FeatureID>
    ) -> Bool {
        completedIDs.contains(featureID)
    }

    static func backTitle(
        from step: OnboardingState,
        selectedIDs: [FeatureID],
        pickerOrder: [FeatureID],
        registry: FeatureRegistry
    ) -> String {
        switch step {
        case .featureSetup(let id):
            if let previous = previousFeatureID(before: id, selectedIDs: selectedIDs, pickerOrder: pickerOrder) {
                let name = registry.descriptor(for: previous)?.displayName ?? previous.rawValue
                return "Back to \(name)"
            }
            return "Back to features"
        case .unifiedPermissions:
            return "Back"
        case .done:
            return "Back"
        default:
            return "Back"
        }
    }
}
