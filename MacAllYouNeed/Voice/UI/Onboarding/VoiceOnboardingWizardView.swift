import AppKit
import Core
import FeatureCore
import Platform
import SwiftUI

/// Standalone Voice setup window (Dashboard enable, Settings restart, post-install wizard).
struct VoiceOnboardingWizardView: View {
    let controller: AppController
    @State private var step: VoiceOnboardingStep
    @State private var tryItSucceeded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(controller: AppController) {
        self.controller = controller
        let progress = VoiceOnboardingProgressStore.load()
        _step = State(initialValue: progress.isCompleted ? .welcome : progress.currentStep)
    }

    var body: some View {
        SetupWizardShell(
            title: "Voice Setup",
            subtitle: "Dictation workflow",
            steps: VoiceOnboardingFlowHelpers.stepDescriptors(current: step),
            currentStep: step,
            canGoBack: step.previous != nil,
            canSkip: step.canSkip,
            primaryTitle: VoiceOnboardingFlowHelpers.primaryTitle(for: step),
            canAdvance: VoiceOnboardingFlowHelpers.canAdvance(step: step, tryItSucceeded: tryItSucceeded),
            back: { _ = VoiceOnboardingFlowHelpers.moveBack(step: &step, tryItSucceeded: &tryItSucceeded) },
            skip: skipCurrentStep,
            primaryAction: step == .done ? finish : advance
        ) {
            VoiceOnboardingStepContent(
                controller: controller,
                step: step,
                tryItSucceeded: $tryItSucceeded
            )
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .trailing)))
        }
        .frame(width: 860, height: 640)
        .onAppear { VoiceOnboardingProgressStore.saveStep(step) }
        .onChange(of: step) { _, newStep in
            VoiceOnboardingProgressStore.saveStep(newStep)
        }
    }

    private func advance() {
        guard let next = step.next else {
            finish()
            return
        }
        if reduceMotion {
            step = next
            tryItSucceeded = false
        } else {
            withAnimation(MAYNMotion.panelAnimation(reduceMotion: reduceMotion)) {
                step = next
                tryItSucceeded = false
            }
        }
        VoiceOnboardingProgressStore.saveStep(next)
    }

    private func skipCurrentStep() {
        VoiceOnboardingFlowHelpers.skipCurrentStep(
            step: &step,
            tryItSucceeded: &tryItSucceeded,
            controller: controller
        )
        if reduceMotion {
            return
        }
        withAnimation(MAYNMotion.panelAnimation(reduceMotion: reduceMotion)) {
            // step already updated
        }
    }

    private func finish() {
        VoiceOnboardingProgressStore.markCompleted()
        FeatureOnboardingProgressStore.markCompleted(.voice)
        controller.closeVoiceOnboarding()
        controller.showMainWindowIfReady()
    }
}
