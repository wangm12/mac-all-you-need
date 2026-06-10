import FeatureCore
import Foundation
import Observation

/// Abstracts the "install one feature's pack" call so tests can drive it deterministically.
@MainActor
protocol OnboardingInstalling: AnyObject {
    func install(descriptor: FeatureDescriptor, progress: @escaping (Double) -> Void) async throws
}

/// Drives one feature through the per-feature setup sub-flow:
///   download (if assetPacks non-empty)
///   → config (if onboardingSetupFactory or featureOnboardingWizardFactory non-nil)
///   → complete
///
/// TCC permissions are handled in the unified onboarding permissions step, not here.
@Observable @MainActor
final class FeatureSetupCoordinator {
    enum SubStep: Equatable {
        case idle
        case download(progress: Double)
        case downloadFailed(reason: String)
        case config
        case complete
    }

    private(set) var subStep: SubStep = .idle

    let descriptor: FeatureDescriptor
    private let installer: OnboardingInstalling

    init(
        descriptor: FeatureDescriptor,
        installer: OnboardingInstalling
    ) {
        self.descriptor = descriptor
        self.installer = installer
    }

    func start() async {
        if !descriptor.assetPacks.isEmpty {
            subStep = .download(progress: 0)
            do {
                try await installer.install(descriptor: descriptor) { [weak self] progress in
                    Task { @MainActor in
                        guard let self else { return }
                        if case .download = self.subStep {
                            self.subStep = .download(progress: progress)
                        }
                    }
                }
                advanceFromDownload()
            } catch {
                subStep = .downloadFailed(reason: error.localizedDescription)
            }
        } else {
            advanceFromDownload()
        }
    }

    func retryDownload() {
        subStep = .download(progress: 0)
        Task { await start() }
    }

    func markConfigDone() {
        if subStep == .config { subStep = .complete }
    }

    /// Skips pack download and lands on the config step when revisiting a completed feature.
    func prepareForRevisit() {
        if hasConfigStep {
            subStep = .config
        } else {
            subStep = .config
        }
    }

    var hasConfigStep: Bool {
        descriptor.onboardingSetupFactory != nil || descriptor.featureOnboardingWizardFactory != nil
    }

    // MARK: - Internal advance helpers

    private func advanceFromDownload() {
        if hasConfigStep {
            subStep = .config
        } else {
            subStep = .complete
        }
    }
}
