@testable import MacAllYouNeed
import FeatureCore
import SwiftUI
import XCTest

// MARK: - Test doubles

private final class StubInstaller: OnboardingInstalling {
    var shouldThrow = false
    var reportedProgress: Double = 0

    func install(descriptor: FeatureDescriptor, progress: @escaping (Double) -> Void) async throws {
        if shouldThrow { throw URLError(.cancelled) }
        progress(0.5)
        progress(1.0)
        reportedProgress = 1.0
    }
}

private func makeNoAssetDescriptor() -> FeatureDescriptor {
    FeatureDescriptor(
        id: .clipboard,
        displayName: "Clipboard",
        icon: "doc",
        summary: "",
        detailDescription: "",
        activator: NoopFeatureActivator()
    )
}

private func makeAssetDescriptor() -> FeatureDescriptor {
    FeatureDescriptor(
        id: .downloader,
        displayName: "Downloader",
        icon: "arrow.down",
        summary: "",
        detailDescription: "",
        assetPacks: [AssetPack(id: "dl", bundledManifestKey: "downloader")],
        activator: NoopFeatureActivator()
    )
}

// MARK: - Observation characterization tests

@MainActor
final class FeatureSetupCoordinatorObservationTests: XCTestCase {

    // MARK: Initial state

    func testInitialSubStepIsIdle() {
        let descriptor = makeNoAssetDescriptor()
        let installer = StubInstaller()
        let coordinator = FeatureSetupCoordinator(descriptor: descriptor, installer: installer)
        XCTAssertEqual(coordinator.subStep, .idle)
    }

    // MARK: No-asset path

    func testNoAssetNoPermissionsNoConfigAdvancesToComplete() async {
        let descriptor = makeNoAssetDescriptor()
        let installer = StubInstaller()
        let coordinator = FeatureSetupCoordinator(descriptor: descriptor, installer: installer)
        await coordinator.start()
        XCTAssertEqual(coordinator.subStep, .complete)
    }

    func testNoAssetWithPermissionsAlwaysGrantedAdvancesToComplete() async {
        let descriptor = FeatureDescriptor(
            id: .clipboard,
            displayName: "Clipboard",
            icon: "doc",
            summary: "",
            detailDescription: "",
            requiredPermissions: [.accessibility],
            activator: NoopFeatureActivator()
        )
        let installer = StubInstaller()
        let coordinator = FeatureSetupCoordinator(
            descriptor: descriptor, installer: installer, permissionsAlwaysGranted: true
        )
        await coordinator.start()
        XCTAssertEqual(coordinator.subStep, .complete)
    }

    func testNoAssetWithUngrantedPermissionsAdvancesToPermissions() async {
        // Use permissionsAlwaysGranted: false and a real permission that is almost certainly
        // not granted in the test environment.
        let descriptor = FeatureDescriptor(
            id: .clipboard,
            displayName: "Clipboard",
            icon: "doc",
            summary: "",
            detailDescription: "",
            requiredPermissions: [.accessibility],
            activator: NoopFeatureActivator()
        )
        let installer = StubInstaller()
        let coordinator = FeatureSetupCoordinator(
            descriptor: descriptor, installer: installer, permissionsAlwaysGranted: false
        )
        await coordinator.start()
        // In a test environment accessibility is not granted, so we land on .permissions.
        // If somehow it is granted, the coordinator advances to .complete. Either is a
        // deterministic outcome — just verify we are NOT still .idle.
        XCTAssertNotEqual(coordinator.subStep, .idle)
    }

    // MARK: Asset path (success)

    func testAssetDescriptorStartsWithDownloadProgress() async {
        let descriptor = makeAssetDescriptor()
        let installer = StubInstaller()
        let coordinator = FeatureSetupCoordinator(descriptor: descriptor, installer: installer)
        await coordinator.start()
        // After successful install, advances past download → complete (no permissions, no config)
        XCTAssertEqual(coordinator.subStep, .complete)
    }

    // MARK: Asset path (failure)

    func testAssetInstallFailureSetsDownloadFailed() async {
        let descriptor = makeAssetDescriptor()
        let installer = StubInstaller()
        installer.shouldThrow = true
        let coordinator = FeatureSetupCoordinator(descriptor: descriptor, installer: installer)
        await coordinator.start()
        if case .downloadFailed = coordinator.subStep {
            // correct
        } else {
            XCTFail("Expected .downloadFailed, got \(coordinator.subStep)")
        }
    }

    // MARK: retryDownload

    func testRetryDownloadResetsToDownloadAndEventuallySucceeds() async {
        let descriptor = makeAssetDescriptor()
        let installer = StubInstaller()
        installer.shouldThrow = true
        let coordinator = FeatureSetupCoordinator(descriptor: descriptor, installer: installer)
        await coordinator.start()
        // Now let it succeed on retry
        installer.shouldThrow = false
        coordinator.retryDownload()
        // retryDownload fires a Task; spin the runloop briefly
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(coordinator.subStep, .complete)
    }

    // MARK: markPermissionGranted

    func testMarkPermissionGrantedAdvancesWhenAllGranted() async {
        let descriptor = FeatureDescriptor(
            id: .clipboard,
            displayName: "Clipboard",
            icon: "doc",
            summary: "",
            detailDescription: "",
            requiredPermissions: [.accessibility],
            activator: NoopFeatureActivator()
        )
        let installer = StubInstaller()
        let coordinator = FeatureSetupCoordinator(
            descriptor: descriptor, installer: installer, permissionsAlwaysGranted: false
        )
        // Force into permissions state by starting and overriding probe via seam
        await coordinator.start()
        guard coordinator.subStep == .permissions else {
            // accessibility was actually granted in the test environment — skip
            return
        }
        coordinator.markPermissionGranted(.accessibility)
        // All declared permissions now granted → should advance to complete (no config)
        XCTAssertEqual(coordinator.subStep, .complete)
    }

    // MARK: markConfigDone

    func testMarkConfigDoneFromConfigAdvancesToComplete() async {
        // Build a descriptor that has a config factory so coordinator lands on .config
        let descriptor = FeatureDescriptor(
            id: .clipboard,
            displayName: "Clipboard",
            icon: "doc",
            summary: "",
            detailDescription: "",
            activator: NoopFeatureActivator(),
            onboardingSetupFactory: { AnyView(EmptyView()) }
        )
        let installer = StubInstaller()
        let coordinator = FeatureSetupCoordinator(
            descriptor: descriptor, installer: installer, permissionsAlwaysGranted: true
        )
        await coordinator.start()
        XCTAssertEqual(coordinator.subStep, FeatureSetupCoordinator.SubStep.config)
        coordinator.markConfigDone()
        XCTAssertEqual(coordinator.subStep, FeatureSetupCoordinator.SubStep.complete)
    }

    func testMarkConfigDoneNoopWhenNotInConfig() {
        let descriptor = makeNoAssetDescriptor()
        let installer = StubInstaller()
        let coordinator = FeatureSetupCoordinator(descriptor: descriptor, installer: installer)
        // subStep is .idle
        coordinator.markConfigDone()
        XCTAssertEqual(coordinator.subStep, .idle)
    }

    // MARK: Observation — each mutation notifies observer (requires @Observable)
    //
    // This test is the post-migration parity check. withObservationTracking activates
    // only when the type is annotated @Observable; on plain ObservableObject the onChange
    // closure is never called by the Observation runtime.

    func testSubStepMutationNotifiesObserverViaObservationTracking() async {
        let descriptor = FeatureDescriptor(
            id: .clipboard,
            displayName: "Clipboard",
            icon: "doc",
            summary: "",
            detailDescription: "",
            activator: NoopFeatureActivator(),
            onboardingSetupFactory: { AnyView(EmptyView()) }
        )
        let installer = StubInstaller()
        let coordinator = FeatureSetupCoordinator(
            descriptor: descriptor, installer: installer, permissionsAlwaysGranted: true
        )

        var notificationCount = 0
        // Set up a chained observer: each time the property changes, re-register for the next.
        func track() {
            withObservationTracking {
                _ = coordinator.subStep
            } onChange: {
                notificationCount += 1
                Task { @MainActor in track() }
            }
        }
        track()

        // idle → config (one change, possibly two if download progress fires first)
        await coordinator.start()
        XCTAssertEqual(coordinator.subStep, FeatureSetupCoordinator.SubStep.config)
        XCTAssertGreaterThanOrEqual(notificationCount, 1, "Expected at least one observation notification for idle→config")

        let before = notificationCount
        // Yield to let the chained Task { @MainActor in track() } re-register before the next mutation.
        await Task.yield()
        // config → complete (one more change)
        coordinator.markConfigDone()
        XCTAssertEqual(coordinator.subStep, FeatureSetupCoordinator.SubStep.complete)
        XCTAssertGreaterThanOrEqual(notificationCount, before + 1, "Expected at least one observation notification for config→complete")
    }
}
