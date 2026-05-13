@testable import MacAllYouNeed
import XCTest

final class MainStartupSurfaceRouterTests: XCTestCase {
    func testAppOnboardingBlocksAllOtherStartupSurfaces() {
        XCTAssertEqual(
            MainStartupSurfaceRouter.surface(
                appOnboardingCompleted: false,
                voiceOnboardingCompleted: true
            ),
            .appOnboarding
        )
    }

    func testVoiceOnboardingBlocksMainWindowAfterAppOnboarding() {
        XCTAssertEqual(
            MainStartupSurfaceRouter.surface(
                appOnboardingCompleted: true,
                voiceOnboardingCompleted: false
            ),
            .voiceOnboarding
        )
    }

    func testCompletedSetupRoutesToMainWindow() {
        XCTAssertEqual(
            MainStartupSurfaceRouter.surface(
                appOnboardingCompleted: true,
                voiceOnboardingCompleted: true
            ),
            .mainWindow
        )
    }
}
