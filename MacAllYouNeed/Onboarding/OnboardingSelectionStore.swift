import Core
import FeatureCore
import Foundation

/// Persists the user's picker choices and per-feature setup progress across quits.
/// Continue from the feature picker restarts setup from the first selected feature.
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
            var selected = payload.selected.compactMap(FeatureID.init(rawValue:))
            selected.removeAll { $0 == .clipboardSmartText }
            self.selectedIDs = selected
            self.completedIDs = Set(payload.completed.compactMap(FeatureID.init(rawValue:)))
        } else {
            self.selectedIDs = []
            self.completedIDs = []
        }
    }

    func setSelection(_ ids: [FeatureID]) {
        selectedIDs = ids.filter { $0 != .clipboardSmartText }
        completedIDs.formIntersection(Set(selectedIDs))
        persist()
    }

    func markCompleted(_ id: FeatureID) {
        completedIDs.insert(id)
        persist()
    }

    func resetCompletedProgress() {
        completedIDs = []
        persist()
    }

    /// First selected feature in `order`, regardless of setup progress.
    func firstSelectedID(in order: [FeatureID]) -> FeatureID? {
        let selected = Set(selectedIDs)
        return order.first { selected.contains($0) }
    }

    /// Returns the next un-completed feature in `order`. Nil when all are done.
    func nextPendingID(in order: [FeatureID]) -> FeatureID? {
        let selected = Set(selectedIDs)
        for id in order where selected.contains(id) && !completedIDs.contains(id) {
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
