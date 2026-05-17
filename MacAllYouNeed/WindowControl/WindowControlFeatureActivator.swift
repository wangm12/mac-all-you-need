import FeatureCore
import Foundation

/// Window Control is owned by AppController because Window Layouts and Window Grab
/// share one coordinator/settings store. The feature activators let the modular
/// feature runtime represent the two toggles while AppController applies the
/// concrete gates to the shared coordinator.
actor WindowControlFeatureActivator: FeatureActivator {
    private(set) var isActive = false

    func activate() async throws {
        isActive = true
    }

    func deactivate() async throws {
        isActive = false
    }
}
