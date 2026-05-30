import FeatureCore
import Foundation

/// FeatureActivator for Dock Previews. Activation/deactivation of the live
/// runtime is driven by `DockPreviewRuntime.applyEnabled(_:)` from AppController
/// (mirroring Finder Folder History), so this activator is a no-op seam used by
/// the feature registry for enable/disable bookkeeping.
struct DockPreviewsFeatureActivator: FeatureActivator {
    func activate() async throws {}
    func deactivate() async throws {}
}
