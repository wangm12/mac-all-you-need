import SwiftUI

/// Voice setup content embedded in the main app-install onboarding shell.
struct VoiceOnboardingEmbeddedView: View {
    let controller: AppController
    @Binding var step: VoiceOnboardingStep
    @Binding var tryItSucceeded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VoiceOnboardingStepContent(
            controller: controller,
            step: step,
            tryItSucceeded: $tryItSucceeded
        )
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .trailing)))
        .animation(MAYNMotion.panelAnimation(reduceMotion: reduceMotion), value: step)
        .onAppear {
            VoiceOnboardingProgressStore.saveStep(step)
        }
        .onChange(of: step) { _, newStep in
            VoiceOnboardingProgressStore.saveStep(newStep)
        }
    }
}
