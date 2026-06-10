import FeatureCore
import SwiftUI

/// Post-install wizard for a single feature (e.g. after enabling from Dashboard).
struct StandaloneFeatureOnboardingView: View {
    let controller: AppController
    let featureID: FeatureID
    let onFinished: () -> Void
    @State private var coordinator: FeatureSetupCoordinator?
    @State private var featureTryItSucceeded = false

    var body: some View {
        Group {
            if let coordinator {
                FeatureOnboardingFlowView(
                    coordinator: coordinator,
                    showsFooter: true,
                    tryItSucceeded: $featureTryItSucceeded,
                    onBack: nil,
                    onFinished: finish
                )
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(MAYNTheme.window)
                    .onAppear { coordinator = makeCoordinator() }
            }
        }
        .frame(width: 680, height: 580)
    }

    private func finish() {
        FeatureOnboardingProgressStore.markCompleted(featureID)
        onFinished()
    }

    private func makeCoordinator() -> FeatureSetupCoordinator? {
        guard let descriptor = controller.runtime.registry.descriptor(for: featureID) else { return nil }
        let augmented = FeatureOnboardingWizardRegistry.augmented(descriptor, controller: controller)
        return FeatureSetupCoordinator(
            descriptor: augmented,
            installer: OnboardingInstaller(packInstallController: controller.packInstallController)
        )
    }
}
