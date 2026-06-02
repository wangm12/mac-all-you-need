import FeatureCore
import Foundation

/// Feature activator is a no-op gate flip; unified hub runtime is driven by
/// `DockHubRuntime.applyEnabled(_:)` from AppController (mirroring Finder Folder History).
struct DockPreviewsFeatureActivator: FeatureActivator {
    func activate() async throws {}
    func deactivate() async throws {}
}
