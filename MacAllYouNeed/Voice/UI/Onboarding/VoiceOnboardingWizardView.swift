import AppKit
import Core
import Platform
import SwiftUI

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
            steps: stepDescriptors,
            currentStep: step,
            canGoBack: step.previous != nil,
            canSkip: canSkipCurrentStep,
            primaryTitle: primaryTitle,
            canAdvance: canAdvanceCurrentStep,
            back: { move(to: step.previous ?? step) },
            skip: skipCurrentStep,
            primaryAction: step == .done ? finish : advance
        ) {
            currentStepView
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .trailing)))
        }
        .frame(width: 860, height: 640)
        .onAppear { VoiceOnboardingProgressStore.saveStep(step) }
    }

    @ViewBuilder
    private var currentStepView: some View {
        switch step {
        case .welcome:
            VoiceWelcomeStepView()
        case .microphone:
            VoiceMicrophoneStepView(autoAdvance: { move(to: .accessibility) })
        case .accessibility:
            VoiceAccessibilityStepView(autoAdvance: { move(to: .asr) })
        case .asr:
            VoiceASRStepView()
        case .llm:
            VoiceLLMStepView(controller: controller)
        case .hotkey:
            VoiceHotkeyStepView(controller: controller)
        case .languages:
            VoiceLanguagesStepView()
        case .tryIt:
            VoiceTryItStepView(controller: controller) {
                tryItSucceeded = true
            }
        case .done:
            VoiceDoneStepView()
        }
    }

    private var canSkipCurrentStep: Bool {
        step.canSkip
    }

    private var canAdvanceCurrentStep: Bool {
        step != .tryIt || tryItSucceeded
    }

    private var primaryTitle: String {
        switch step {
        case .welcome:
            "Get Started"
        case .done:
            "Done"
        case .microphone, .accessibility, .asr, .llm, .hotkey, .languages, .tryIt:
            "Continue"
        }
    }

    private var stepDescriptors: [SetupStepDescriptor<VoiceOnboardingStep>] {
        let currentIndex = VoiceOnboardingStep.orderedCases.firstIndex(of: step) ?? 0
        return VoiceOnboardingStep.orderedCases.enumerated().map { index, candidate in
            SetupStepDescriptor(
                id: candidate,
                title: candidate.title,
                subtitle: candidate.setupSubtitle,
                symbol: candidate.setupSymbol,
                isCompleted: index < currentIndex
            )
        }
    }

    private func advance() {
        guard let next = step.next else {
            finish()
            return
        }
        move(to: next)
    }

    private func skipCurrentStep() {
        if step == .llm {
            controller.disableVoiceCleanup()
        }
        advance()
    }

    private func move(to newStep: VoiceOnboardingStep) {
        if reduceMotion {
            step = newStep
        } else {
            withAnimation(MAYNMotion.panelAnimation(reduceMotion: reduceMotion)) {
                step = newStep
            }
        }
        VoiceOnboardingProgressStore.saveStep(newStep)
    }

    private func finish() {
        VoiceOnboardingProgressStore.markCompleted()
        controller.closeVoiceOnboarding()
        controller.showMainWindowIfReady()
    }
}

private extension VoiceOnboardingStep {
    var setupSubtitle: String {
        switch self {
        case .welcome:
            "Overview"
        case .microphone:
            "Capture audio"
        case .accessibility:
            "Paste anywhere"
        case .asr:
            "Local engine"
        case .llm:
            "Cleanup"
        case .hotkey:
            "Activation"
        case .languages:
            "Recognition bias"
        case .tryIt:
            "Confirm"
        case .done:
            "Finish"
        }
    }

    var setupSymbol: String {
        switch self {
        case .welcome:
            "mic.badge.plus"
        case .microphone:
            "mic"
        case .accessibility:
            "accessibility"
        case .asr:
            "waveform"
        case .llm:
            "text.bubble"
        case .hotkey:
            "keyboard"
        case .languages:
            "globe"
        case .tryIt:
            "square.and.pencil"
        case .done:
            "checkmark"
        }
    }
}
