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
///   → permissions (if requiredPermissions non-empty and not all already granted)
///   → config (if onboardingSetupFactory non-nil)
///   → complete
///
/// Persisting the cursor position within the sub-flow is intentionally NOT done — a relaunch
/// resumes at the same feature (via OnboardingSelectionStore) and re-runs its sub-steps.
/// All sub-steps are idempotent (download already-present is a no-op via pack pipeline,
/// permissions already-granted auto-skip, config closure is pure UI), so re-running is cheap.
@Observable @MainActor
final class FeatureSetupCoordinator {
    enum SubStep: Equatable {
        case idle
        case download(progress: Double)
        case downloadFailed(reason: String)
        case permissions
        case config
        case complete
    }

    private(set) var subStep: SubStep = .idle

    let descriptor: FeatureDescriptor
    private let installer: OnboardingInstalling
    private let permissionsAlwaysGranted: Bool   // test seam; production uses PermissionGateProbe
    private var grantedPermissions: Set<Permission> = []

    init(
        descriptor: FeatureDescriptor,
        installer: OnboardingInstalling,
        permissionsAlwaysGranted: Bool = false
    ) {
        self.descriptor = descriptor
        self.installer = installer
        self.permissionsAlwaysGranted = permissionsAlwaysGranted
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

    func markPermissionGranted(_ permission: Permission) {
        grantedPermissions.insert(permission)
        if allDeclaredPermissionsGranted {
            advanceFromPermissions()
        }
    }

    func markConfigDone() {
        if subStep == .config { subStep = .complete }
    }

    // MARK: - Internal advance helpers

    private func advanceFromDownload() {
        if descriptor.requiredPermissions.isEmpty || initiallyAllGranted() {
            advanceFromPermissions()
        } else {
            subStep = .permissions
        }
    }

    private func advanceFromPermissions() {
        if descriptor.onboardingSetupFactory != nil {
            subStep = .config
        } else {
            subStep = .complete
        }
    }

    private func initiallyAllGranted() -> Bool {
        if permissionsAlwaysGranted { return true }
        for p in descriptor.requiredPermissions where !PermissionGateProbe.isGranted(p) {
            return false
        }
        return true
    }

    private var allDeclaredPermissionsGranted: Bool {
        Set(descriptor.requiredPermissions).isSubset(of: grantedPermissions)
    }
}
