import Core
import FeatureCore

extension AppController {
    func showStartupSurface() {
        Task { @MainActor in
            let surface = await resolvedStartupSurface()
            presentStartupSurface(surface)
        }
    }

    @MainActor
    private func resolvedStartupSurface() async -> MainStartupSurface {
        let registryOrder = await runtime.registry.descriptors.map(\.id)
        var enabledIDs = Set<FeatureID>()
        for id in registryOrder {
            let state = await runtime.manager.state(for: id)
            if state.activationState == .enabled {
                enabledIDs.insert(id)
            }
        }
        return MainStartupSurfaceRouter.surface(
            appOnboardingCompleted: onboarding == .completed,
            registryOrder: registryOrder,
            featureEnabled: { enabledIDs.contains($0) }
        )
    }

    @MainActor
    private func presentStartupSurface(_ surface: MainStartupSurface) {
        switch surface {
        case .appOnboarding:
            onboardingWindow.show()
        case .featureOnboarding(let id):
            showFeatureOnboarding(id)
        case .mainWindow:
            showMainWindow()
        }
    }

    func showMainWindow(destination: MainAppDestination? = nil) {
        mainWindow.show(destination: destination)
    }

    func showVoiceModels() {
        let route = VoiceModelsNavigation.route()
        if let tabStorageKey = route.tabStorageKey, let tabRawValue = route.tabRawValue {
            AppGroupSettings.defaults.set(tabRawValue, forKey: tabStorageKey)
        }
        showMainWindow(destination: route.destination)
    }

    func showMainWindowIfReady() {
        Task { @MainActor in
            let surface = await resolvedStartupSurface()
            if surface == .mainWindow {
                showMainWindow()
            } else {
                presentStartupSurface(surface)
            }
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
        DeferredPermissionsStore.reset()
        Task { @MainActor in
            let order = await runtime.registry.descriptors.map(\.id)
            FeatureOnboardingProgressStore.resetAll(registryOrder: order)
        }
        VoiceOnboardingProgressStore.reset()
        setOnboarding(.notStarted)
    }

    func showOnboardingIfNeeded() {
        showStartupSurface()
    }

    func showFeatureOnboarding(_ id: FeatureID) {
        if id == .voice {
            voiceOnboardingWindow.show()
        } else {
            onboardingWindow.showStandaloneWizard(for: id)
        }
    }

    func showFeatureOnboardingIfNeeded(for id: FeatureID) {
        guard onboarding == .completed else { return }
        guard !FeatureOnboardingProgressStore.isCompleted(id) else { return }
        Task { @MainActor in
            let state = await runtime.manager.state(for: id)
            guard state.activationState == .enabled else { return }
            showFeatureOnboarding(id)
        }
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
