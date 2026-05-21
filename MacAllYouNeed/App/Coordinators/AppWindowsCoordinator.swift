import Foundation

/// Protocol seam for `MainWindowController` so AppWindowsCoordinator can
/// hold its dependencies behind a behavior contract rather than the
/// concrete NSWindow-backed type. Lets us unit-test the coordinator
/// without standing up real NSWindows in xctest.
@MainActor
protocol MainWindowDisplaying: AnyObject {
    func show(destination: MainAppDestination?)
}

@MainActor
protocol OnboardingWindowDisplaying: AnyObject {
    func show()
}

@MainActor
protocol VoiceOnboardingWindowDisplaying: AnyObject {
    func show()
    func close()
}

extension MainWindowController: MainWindowDisplaying {}
extension OnboardingWindowController: OnboardingWindowDisplaying {}
extension VoiceOnboardingWindowController: VoiceOnboardingWindowDisplaying {}

/// Owns the three top-level window controllers (main, onboarding, voice
/// onboarding) and routes show / close requests to the right one. AppController
/// used to expose the three controllers as separate properties; consolidating
/// them clears AppController of window plumbing it doesn't need to participate
/// in beyond requesting a surface.
///
/// Holds the controllers via protocol-typed properties so unit tests can
/// substitute lightweight fakes — constructing real NSWindows under xctest
/// is unreliable. AppController preserves its long-standing `mainWindow` /
/// `onboardingWindow` / `voiceOnboardingWindow` properties by downcasting
/// the coordinator's protocol-typed slots back to the concrete types it
/// constructed at launch.
@MainActor
final class AppWindowsCoordinator {
    let main: MainWindowDisplaying
    let onboarding: OnboardingWindowDisplaying
    let voiceOnboarding: VoiceOnboardingWindowDisplaying

    init(
        main: MainWindowDisplaying,
        onboarding: OnboardingWindowDisplaying,
        voiceOnboarding: VoiceOnboardingWindowDisplaying
    ) {
        self.main = main
        self.onboarding = onboarding
        self.voiceOnboarding = voiceOnboarding
    }

    func showMain(destination: MainAppDestination? = nil) {
        main.show(destination: destination)
    }

    func showOnboarding() {
        onboarding.show()
    }

    func showVoiceOnboarding() {
        voiceOnboarding.show()
    }

    func closeVoiceOnboarding() {
        voiceOnboarding.close()
    }
}
