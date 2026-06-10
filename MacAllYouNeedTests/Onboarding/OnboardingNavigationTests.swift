@testable import MacAllYouNeed
import FeatureCore
import SwiftUI
import XCTest

final class OnboardingNavigationTests: XCTestCase {
    private let pickerOrder = OnboardingFeaturePickerOrdering.featureIDs

    func testPreviousFeatureIDInPickerOrder() {
        let selected: [FeatureID] = [.clipboard, .voice, .voiceReminders, .downloader]
        XCTAssertEqual(
            OnboardingNavigationPlanner.previousFeatureID(
                before: .voiceReminders,
                selectedIDs: selected,
                pickerOrder: pickerOrder
            ),
            .voice
        )
        XCTAssertEqual(
            OnboardingNavigationPlanner.previousFeatureID(
                before: .voice,
                selectedIDs: selected,
                pickerOrder: pickerOrder
            ),
            .clipboard
        )
        XCTAssertNil(
            OnboardingNavigationPlanner.previousFeatureID(
                before: .clipboard,
                selectedIDs: selected,
                pickerOrder: pickerOrder
            )
        )
    }

    func testPreviousFeatureIDSkipsUnselectedFeatures() {
        let selected: [FeatureID] = [.clipboard, .downloader]
        XCTAssertEqual(
            OnboardingNavigationPlanner.previousFeatureID(
                before: .downloader,
                selectedIDs: selected,
                pickerOrder: pickerOrder
            ),
            .clipboard
        )
    }

    func testIsRevisitUsesCompletedSet() {
        XCTAssertTrue(
            OnboardingNavigationPlanner.isRevisit(
                featureID: .voice,
                completedIDs: [.clipboard, .voice]
            )
        )
        XCTAssertFalse(
            OnboardingNavigationPlanner.isRevisit(
                featureID: .downloader,
                completedIDs: [.clipboard, .voice]
            )
        )
    }

    @MainActor
    func testPrepareForRevisitLandsOnConfig() {
        let descriptor = FeatureDescriptor(
            id: .downloader,
            displayName: "Downloader",
            icon: "arrow.down",
            summary: "",
            detailDescription: "",
            assetPacks: [AssetPack(id: "dl", bundledManifestKey: "downloader")],
            activator: NoopFeatureActivator(),
            featureOnboardingWizardFactory: { AnyView(EmptyView()) }
        )
        let coordinator = FeatureSetupCoordinator(descriptor: descriptor, installer: StubOnboardingInstaller())
        coordinator.prepareForRevisit()
        XCTAssertEqual(coordinator.subStep, FeatureSetupCoordinator.SubStep.config)
    }

    @MainActor
    func testSidebarHidesFeatureStepsBeforeSetupStarts() {
        let registry = FeatureRegistry(descriptors: [
            FeatureDescriptor(
                id: .clipboard,
                displayName: "Clipboard",
                icon: "doc.on.doc",
                summary: "",
                detailDescription: "",
                activator: NoopFeatureActivator()
            ),
            FeatureDescriptor(
                id: .voice,
                displayName: "Voice",
                icon: "mic",
                summary: "",
                detailDescription: "",
                activator: NoopFeatureActivator()
            ),
        ])
        let selected: [FeatureID] = [.clipboard, .voice]
        let descriptors = OnboardingSidebarBuilder.descriptors(
            step: .welcome,
            selectedIDs: selected,
            pickerOrder: [.clipboard, .voice],
            completedFeatureIDs: [],
            permissionCount: 0,
            registry: registry,
            voiceStep: .welcome,
            coordinator: nil,
            showFeatureStepsInSidebar: false
        )
        XCTAssertFalse(descriptors.contains { item in
            if case .feature = item.id { return true }
            return false
        })
        XCTAssertTrue(descriptors.contains { $0.id == .setupOverview })
    }

    @MainActor
    func testSidebarKeepsFeatureStepsAfterReturningToWelcome() {
        let registry = FeatureRegistry(descriptors: [
            FeatureDescriptor(
                id: .clipboard,
                displayName: "Clipboard",
                icon: "doc.on.doc",
                summary: "",
                detailDescription: "",
                activator: NoopFeatureActivator()
            ),
            FeatureDescriptor(
                id: .voice,
                displayName: "Voice",
                icon: "mic",
                summary: "",
                detailDescription: "",
                activator: NoopFeatureActivator()
            ),
        ])
        let selected: [FeatureID] = [.clipboard, .voice]
        let descriptors = OnboardingSidebarBuilder.descriptors(
            step: .welcome,
            selectedIDs: selected,
            pickerOrder: [.clipboard, .voice],
            completedFeatureIDs: [.clipboard],
            permissionCount: 0,
            registry: registry,
            voiceStep: .welcome,
            coordinator: nil,
            showFeatureStepsInSidebar: true
        )
        let featureSteps = descriptors.filter { item in
            if case .feature = item.id { return true }
            return false
        }
        XCTAssertEqual(featureSteps.count, 2)
        XCTAssertFalse(descriptors.contains { $0.id == .setupOverview })
        XCTAssertTrue(featureSteps.first?.isCompleted == true)
    }

    @MainActor
    func testCoordinatorWithoutConfigStillShowsConfigOnRevisit() {
        let descriptor = FeatureDescriptor(
            id: .clipboard,
            displayName: "Clipboard",
            icon: "doc",
            summary: "",
            detailDescription: "",
            activator: NoopFeatureActivator()
        )
        let coordinator = FeatureSetupCoordinator(descriptor: descriptor, installer: StubOnboardingInstaller())
        coordinator.prepareForRevisit()
        XCTAssertEqual(coordinator.subStep, FeatureSetupCoordinator.SubStep.config)
    }
}

@MainActor
private final class StubOnboardingInstaller: OnboardingInstalling {
    func install(descriptor: FeatureDescriptor, progress: @escaping (Double) -> Void) async throws {
        progress(1)
    }
}
