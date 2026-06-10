@testable import MacAllYouNeed
import FeatureCore
import XCTest

final class MainStartupSurfaceRouterTests: XCTestCase {
    private let order: [FeatureID] = [.clipboard, .voice, .downloader]

    override func setUp() {
        super.setUp()
        for id in order {
            FeatureOnboardingProgressStore.reset(id)
        }
    }

    func testAppOnboardingBlocksAllOtherStartupSurfaces() {
        XCTAssertEqual(
            MainStartupSurfaceRouter.surface(
                appOnboardingCompleted: false,
                registryOrder: order,
                featureEnabled: { _ in true }
            ),
            .appOnboarding
        )
    }

    func testPendingFeatureWizardBlocksMainWindow() {
        XCTAssertEqual(
            MainStartupSurfaceRouter.surface(
                appOnboardingCompleted: true,
                registryOrder: order,
                featureEnabled: { $0 == .voice }
            ),
            .featureOnboarding(.voice)
        )
    }

    func testCompletedSetupRoutesToMainWindow() {
        for id in order {
            FeatureOnboardingProgressStore.markCompleted(id)
        }
        XCTAssertEqual(
            MainStartupSurfaceRouter.surface(
                appOnboardingCompleted: true,
                registryOrder: order,
                featureEnabled: { _ in true }
            ),
            .mainWindow
        )
    }

    func testDisabledFeatureDoesNotBlockMainWindow() {
        XCTAssertEqual(
            MainStartupSurfaceRouter.surface(
                appOnboardingCompleted: true,
                registryOrder: [.voice],
                featureEnabled: { _ in false }
            ),
            .mainWindow
        )
    }

    func testClipboardSmartTextDoesNotBlockMainWindow() {
        XCTAssertEqual(
            MainStartupSurfaceRouter.surface(
                appOnboardingCompleted: true,
                registryOrder: [.clipboardSmartText],
                featureEnabled: { _ in true }
            ),
            .mainWindow
        )
    }
}
