import FeatureCore
import Foundation

/// Production conformance to `OnboardingInstalling`. Delegates to the existing
/// `PackInstallController` from Phase 06, which owns the PackDownloader +
/// PackInstaller + FeatureManager state transitions.
///
/// Progress reporting is best-effort: the pack pipeline writes asset state updates
/// through FeatureManager, which the Features tab mirrors. A ProgressView in the
/// onboarding wizard observes `subStep.progress` via `FeatureSetupCoordinator`.
@MainActor
final class OnboardingInstaller: OnboardingInstalling {
    private let packInstallController: PackInstallController

    init(packInstallController: PackInstallController) {
        self.packInstallController = packInstallController
    }

    func install(descriptor: FeatureDescriptor, progress: @escaping (Double) -> Void) async throws {
        guard !descriptor.assetPacks.isEmpty else { return }
        // PackInstallController drives its own FeatureManager state updates.
        // We poll manager state on the coordinator's tick to derive progress.
        // The actual install is fully delegated to avoid duplicating pack pipeline logic.
        try await packInstallController.install(featureID: descriptor.id)
        progress(1.0)
    }
}
