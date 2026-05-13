extension AppController {
    func showStartupSurface() {
        let surface = MainStartupSurfaceRouter.surface(
            appOnboardingCompleted: onboarding == .completed,
            voiceOnboardingCompleted: VoiceOnboardingProgressStore.load().isCompleted
        )
        switch surface {
        case .appOnboarding:
            onboardingWindow.show()
        case .voiceOnboarding:
            voiceOnboardingWindow.show()
        case .mainWindow:
            showMainWindow()
        }
    }

    func showMainWindow(destination: MainAppDestination? = nil) {
        mainWindow.show(destination: destination)
    }

    func showMainWindowIfReady() {
        let surface = MainStartupSurfaceRouter.surface(
            appOnboardingCompleted: onboarding == .completed,
            voiceOnboardingCompleted: VoiceOnboardingProgressStore.load().isCompleted
        )
        if surface == .mainWindow {
            showMainWindow()
        } else {
            showStartupSurface()
        }
    }

    func setOnboarding(_ state: OnboardingState) {
        onboarding = state
        state.save()
        if state == .completed {
            Task { @MainActor in
                await Task.yield()
                self.showStartupSurface()
            }
        }
    }

    func resetOnboarding() {
        setOnboarding(.notStarted)
    }

    func showOnboardingIfNeeded() {
        showStartupSurface()
    }

    func showVoiceOnboardingIfNeeded() {
        guard onboarding == .completed else { return }
        guard !VoiceOnboardingProgressStore.load().isCompleted else { return }
        voiceOnboardingWindow.show()
    }

    func showVoiceOnboarding() {
        voiceOnboardingWindow.show()
    }

    func restartVoiceOnboarding() {
        VoiceOnboardingProgressStore.reset()
        voiceOnboardingWindow.show()
    }

    func closeVoiceOnboarding() {
        voiceOnboardingWindow.close()
    }
}
