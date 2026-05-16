import Core
import FeatureCore
import Foundation

/// Persists the user's picker choices and per-feature completion progress so a crash
/// or quit mid-onboarding resumes at the next pending feature.
@MainActor
final class OnboardingSelectionStore {
    private struct Payload: Codable {
        var selected: [String]
        var completed: [String]
    }

    private let defaults: UserDefaults
    private static let key = "onboarding.featureSelection"

    private(set) var selectedIDs: [FeatureID]
    private(set) var completedIDs: Set<FeatureID>

    init(defaults: UserDefaults = AppGroupSettings.defaults) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let payload = try? JSONDecoder().decode(Payload.self, from: data) {
            self.selectedIDs = payload.selected.compactMap(FeatureID.init(rawValue:))
            self.completedIDs = Set(payload.completed.compactMap(FeatureID.init(rawValue:)))
        } else {
            self.selectedIDs = []
            self.completedIDs = []
        }
    }

    func setSelection(_ ids: [FeatureID]) {
        selectedIDs = ids
        completedIDs.formIntersection(Set(ids))
        persist()
    }

    func markCompleted(_ id: FeatureID) {
        completedIDs.insert(id)
        persist()
    }

    /// Returns the next un-completed feature in registry order. Nil when all are done.
    func nextPendingID(in registryOrder: [FeatureID]) -> FeatureID? {
        let selected = Set(selectedIDs)
        for id in registryOrder where selected.contains(id) && !completedIDs.contains(id) {
            return id
        }
        return nil
    }

    func clear() {
        selectedIDs = []
        completedIDs = []
        defaults.removeObject(forKey: Self.key)
    }

    private func persist() {
        let payload = Payload(
            selected: selectedIDs.map(\.rawValue),
            completed: completedIDs.map(\.rawValue)
        )
        if let data = try? JSONEncoder().encode(payload) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
