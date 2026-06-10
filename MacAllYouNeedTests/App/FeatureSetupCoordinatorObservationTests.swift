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

    func testInitialSubStepIsIdle() {
        let descriptor = makeNoAssetDescriptor()
        let installer = StubInstaller()
        let coordinator = FeatureSetupCoordinator(descriptor: descriptor, installer: installer)
        XCTAssertEqual(coordinator.subStep, .idle)
    }

    func testNoAssetNoConfigAdvancesToComplete() async {
        let descriptor = makeNoAssetDescriptor()
        let installer = StubInstaller()
        let coordinator = FeatureSetupCoordinator(descriptor: descriptor, installer: installer)
        await coordinator.start()
        XCTAssertEqual(coordinator.subStep, .complete)
    }

    func testAssetDescriptorStartsWithDownloadProgress() async {
        let descriptor = makeAssetDescriptor()
        let installer = StubInstaller()
        let coordinator = FeatureSetupCoordinator(descriptor: descriptor, installer: installer)
        await coordinator.start()
        XCTAssertEqual(coordinator.subStep, .complete)
    }

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

    func testRetryDownloadResetsToDownloadAndEventuallySucceeds() async {
        let descriptor = makeAssetDescriptor()
        let installer = StubInstaller()
        installer.shouldThrow = true
        let coordinator = FeatureSetupCoordinator(descriptor: descriptor, installer: installer)
        await coordinator.start()
        installer.shouldThrow = false
        coordinator.retryDownload()
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(coordinator.subStep, .complete)
    }

    func testMarkConfigDoneFromConfigAdvancesToComplete() async {
        let descriptor = FeatureDescriptor(
            id: .clipboard,
            displayName: "Clipboard",
            icon: "doc",
            summary: "",
            detailDescription: "",
            activator: NoopFeatureActivator(),
            featureOnboardingWizardFactory: { AnyView(EmptyView()) }
        )
        let installer = StubInstaller()
        let coordinator = FeatureSetupCoordinator(descriptor: descriptor, installer: installer)
        await coordinator.start()
        XCTAssertEqual(coordinator.subStep, FeatureSetupCoordinator.SubStep.config)
        coordinator.markConfigDone()
        XCTAssertEqual(coordinator.subStep, FeatureSetupCoordinator.SubStep.complete)
    }

    func testMarkConfigDoneNoopWhenNotInConfig() {
        let descriptor = makeNoAssetDescriptor()
        let installer = StubInstaller()
        let coordinator = FeatureSetupCoordinator(descriptor: descriptor, installer: installer)
        coordinator.markConfigDone()
        XCTAssertEqual(coordinator.subStep, .idle)
    }

    func testSubStepMutationNotifiesObserverViaObservationTracking() async {
        let descriptor = FeatureDescriptor(
            id: .clipboard,
            displayName: "Clipboard",
            icon: "doc",
            summary: "",
            detailDescription: "",
            activator: NoopFeatureActivator(),
            featureOnboardingWizardFactory: { AnyView(EmptyView()) }
        )
        let installer = StubInstaller()
        let coordinator = FeatureSetupCoordinator(descriptor: descriptor, installer: installer)

        var notificationCount = 0
        func track() {
            withObservationTracking {
                _ = coordinator.subStep
            } onChange: {
                notificationCount += 1
                Task { @MainActor in track() }
            }
        }
        track()

        await coordinator.start()
        XCTAssertEqual(coordinator.subStep, FeatureSetupCoordinator.SubStep.config)
        XCTAssertGreaterThanOrEqual(notificationCount, 1)

        let before = notificationCount
        await Task.yield()
        coordinator.markConfigDone()
        XCTAssertEqual(coordinator.subStep, FeatureSetupCoordinator.SubStep.complete)
        XCTAssertGreaterThanOrEqual(notificationCount, before + 1)
    }
}
