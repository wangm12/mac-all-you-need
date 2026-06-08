import FeatureCore
import Foundation

/// No-op activator; runtime is driven by `FolderHistoryRuntime.applyEnabled` in AppController.
struct FinderHistoryFeatureActivator: FeatureActivator {
    func activate() async throws {}
    func deactivate() async throws {}
}
