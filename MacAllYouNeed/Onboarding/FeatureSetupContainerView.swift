import FeatureCore
import SwiftUI

/// Hosts the active sub-step for one feature. Owns the FeatureSetupCoordinator instance and
/// reports completion upward so the wizard can advance to the next selected feature.
struct FeatureSetupContainerView: View {
    @State private var coordinator: FeatureSetupCoordinator
    let onFeatureCompleted: () -> Void

    init(coordinator: FeatureSetupCoordinator, onFeatureCompleted: @escaping () -> Void) {
        _coordinator = State(wrappedValue: coordinator)
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
            case .permissions:
                FeatureSetupPermissionsView(descriptor: coordinator.descriptor) { permission in
                    coordinator.markPermissionGranted(permission)
                }
            case .config:
                FeatureSetupConfigView(descriptor: coordinator.descriptor)
            case .complete:
                Color.clear.onAppear { onFeatureCompleted() }
            }
        }
    }
}
