@testable import MacAllYouNeed
import Core
import XCTest

/// Characterization tests for AppWindowsCoordinator.
///
/// The coordinator owns the 3 window controllers (main, onboarding, voice
/// onboarding) and exposes a small dispatch surface. These tests use a
/// protocol seam so we can verify the coordinator's choice of which
/// controller handles each method, without actually constructing NSWindows
/// (which is unreliable under xctest's headless environment).
@MainActor
final class AppWindowsCoordinatorTests: XCTestCase {
    func testShowMainDelegatesToMainWindowControllerWithDestination() {
        let recorder = WindowRecorder()
        let coordinator = AppWindowsCoordinator(
            main: recorder.makeMain(),
            onboarding: recorder.makeOnboarding(),
            voiceOnboarding: recorder.makeVoiceOnboarding()
        )

        coordinator.showMain(destination: .downloads)

        XCTAssertEqual(recorder.events, [.mainShow(.downloads)])
    }

    func testShowMainWithoutDestinationPropagatesNil() {
        let recorder = WindowRecorder()
        let coordinator = AppWindowsCoordinator(
            main: recorder.makeMain(),
            onboarding: recorder.makeOnboarding(),
            voiceOnboarding: recorder.makeVoiceOnboarding()
        )

        coordinator.showMain(destination: nil)

        XCTAssertEqual(recorder.events, [.mainShow(nil)])
    }

    func testShowOnboardingRoutesToOnboardingWindowOnly() {
        let recorder = WindowRecorder()
        let coordinator = AppWindowsCoordinator(
            main: recorder.makeMain(),
            onboarding: recorder.makeOnboarding(),
            voiceOnboarding: recorder.makeVoiceOnboarding()
        )

        coordinator.showOnboarding()

        XCTAssertEqual(recorder.events, [.onboardingShow])
    }

    func testShowVoiceOnboardingRoutesToVoiceOnboardingWindowOnly() {
        let recorder = WindowRecorder()
        let coordinator = AppWindowsCoordinator(
            main: recorder.makeMain(),
            onboarding: recorder.makeOnboarding(),
            voiceOnboarding: recorder.makeVoiceOnboarding()
        )

        coordinator.showVoiceOnboarding()

        XCTAssertEqual(recorder.events, [.voiceOnboardingShow])
    }

    func testCloseVoiceOnboardingRoutesToVoiceOnboardingWindowOnly() {
        let recorder = WindowRecorder()
        let coordinator = AppWindowsCoordinator(
            main: recorder.makeMain(),
            onboarding: recorder.makeOnboarding(),
            voiceOnboarding: recorder.makeVoiceOnboarding()
        )

        coordinator.closeVoiceOnboarding()

        XCTAssertEqual(recorder.events, [.voiceOnboardingClose])
    }

    func testMultipleInvocationsAppendInOrder() {
        let recorder = WindowRecorder()
        let coordinator = AppWindowsCoordinator(
            main: recorder.makeMain(),
            onboarding: recorder.makeOnboarding(),
            voiceOnboarding: recorder.makeVoiceOnboarding()
        )

        coordinator.showOnboarding()
        coordinator.showVoiceOnboarding()
        coordinator.showMain(destination: .voice)
        coordinator.closeVoiceOnboarding()

        XCTAssertEqual(recorder.events, [
            .onboardingShow,
            .voiceOnboardingShow,
            .mainShow(.voice),
            .voiceOnboardingClose
        ])
    }

    // MARK: - Helpers

    @MainActor
    private final class WindowRecorder {
        enum Event: Equatable {
            case mainShow(MainAppDestination?)
            case onboardingShow
            case voiceOnboardingShow
            case voiceOnboardingClose
        }
        var events: [Event] = []

        func makeMain() -> MainWindowDisplaying {
            FakeMainWindow { [weak self] destination in
                self?.events.append(.mainShow(destination))
            }
        }
        func makeOnboarding() -> OnboardingWindowDisplaying {
            FakeOnboardingWindow { [weak self] in
                self?.events.append(.onboardingShow)
            }
        }
        func makeVoiceOnboarding() -> VoiceOnboardingWindowDisplaying {
            FakeVoiceOnboardingWindow(
                onShow: { [weak self] in self?.events.append(.voiceOnboardingShow) },
                onClose: { [weak self] in self?.events.append(.voiceOnboardingClose) }
            )
        }
    }

    @MainActor
    private final class FakeMainWindow: MainWindowDisplaying {
        private let onShow: (MainAppDestination?) -> Void
        init(onShow: @escaping (MainAppDestination?) -> Void) { self.onShow = onShow }
        func show(destination: MainAppDestination?) { onShow(destination) }
    }

    @MainActor
    private final class FakeOnboardingWindow: OnboardingWindowDisplaying {
        private let onShow: () -> Void
        init(onShow: @escaping () -> Void) { self.onShow = onShow }
        func show() { onShow() }
    }

    @MainActor
    private final class FakeVoiceOnboardingWindow: VoiceOnboardingWindowDisplaying {
        private let onShow: () -> Void
        private let onClose: () -> Void
        init(onShow: @escaping () -> Void, onClose: @escaping () -> Void) {
            self.onShow = onShow
            self.onClose = onClose
        }
        func show() { onShow() }
        func close() { onClose() }
    }
}
