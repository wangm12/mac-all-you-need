import FeatureCore
import SwiftUI

/// Hosts the active sub-step for one feature. Owns the FeatureSetupCoordinator instance and
/// reports completion upward so the wizard can advance to the next selected feature.
struct FeatureSetupContainerView: View {
    @Bindable var coordinator: FeatureSetupCoordinator
    let showsFeatureHeader: Bool
    var tryItSucceeded: Binding<Bool>?
    let onFeatureCompleted: () -> Void

    init(
        coordinator: FeatureSetupCoordinator,
        showsFeatureHeader: Bool = true,
        tryItSucceeded: Binding<Bool>? = nil,
        onFeatureCompleted: @escaping () -> Void
    ) {
        self.coordinator = coordinator
        self.showsFeatureHeader = showsFeatureHeader
        self.tryItSucceeded = tryItSucceeded
        self.onFeatureCompleted = onFeatureCompleted
    }

    var body: some View {
        Group {
            switch coordinator.subStep {
            case .idle:
                ProgressView().task { await coordinator.start() }
            case .download(let progress):
                FeatureSetupDownloadView(
                    descriptor: coordinator.descriptor,
                    progress: progress,
                    failureReason: nil,
                    onRetry: { coordinator.retryDownload() }
                )
            case .downloadFailed(let reason):
                FeatureSetupDownloadView(
                    descriptor: coordinator.descriptor,
                    progress: 0,
                    failureReason: reason,
                    onRetry: { coordinator.retryDownload() }
                )
            case .config:
                FeatureOnboardingStepView(
                    descriptor: coordinator.descriptor,
                    showsHeader: showsFeatureHeader,
                    tryItSucceeded: tryItSucceeded
                )
            case .complete:
                Color.clear.frame(height: 1)
            }
        }
    }
}
