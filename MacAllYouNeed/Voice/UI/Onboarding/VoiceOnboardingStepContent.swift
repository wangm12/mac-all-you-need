import SwiftUI

/// Shared step body for embedded and standalone Voice onboarding.
struct VoiceOnboardingStepContent: View {
    let controller: AppController
    let step: VoiceOnboardingStep
    @Binding var tryItSucceeded: Bool

    var body: some View {
        switch step {
        case .welcome:
            VoiceWelcomeStepView()
        case .asr:
            VoiceASRStepView(controller: controller)
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
}

struct VoiceOnboardingStepHeader: View {
    let step: VoiceOnboardingStep

    private var stepIndex: Int {
        VoiceOnboardingStep.orderedCases.firstIndex(of: step) ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Step \(stepIndex + 1) of \(VoiceOnboardingStep.orderedCases.count) · \(step.title)")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            ProgressView(
                value: Double(stepIndex + 1),
                total: Double(VoiceOnboardingStep.orderedCases.count)
            )
            .progressViewStyle(.linear)
        }
    }
}

@MainActor
enum VoiceOnboardingFlowHelpers {
    static func primaryTitle(for step: VoiceOnboardingStep) -> String {
        switch step {
        case .welcome:
            "Get Started"
        case .done:
            "Done"
        case .asr, .llm, .hotkey, .languages, .tryIt:
            "Continue"
        }
    }

    static func canAdvance(step: VoiceOnboardingStep, tryItSucceeded: Bool) -> Bool {
        step != .tryIt || tryItSucceeded
    }

    static func advance(
        step: inout VoiceOnboardingStep,
        tryItSucceeded: inout Bool
    ) {
        guard let next = step.next else { return }
        step = next
        tryItSucceeded = false
        VoiceOnboardingProgressStore.saveStep(next)
    }

    static func moveBack(step: inout VoiceOnboardingStep, tryItSucceeded: inout Bool) -> Bool {
        guard let previous = step.previous else { return false }
        step = previous
        tryItSucceeded = false
        VoiceOnboardingProgressStore.saveStep(previous)
        return true
    }

    static func skipCurrentStep(
        step: inout VoiceOnboardingStep,
        tryItSucceeded: inout Bool,
        controller: AppController
    ) {
        if step == .llm {
            controller.disableVoiceCleanup()
        }
        advance(step: &step, tryItSucceeded: &tryItSucceeded)
    }

    static func stepDescriptors(
        current: VoiceOnboardingStep
    ) -> [SetupStepDescriptor<VoiceOnboardingStep>] {
        let currentIndex = VoiceOnboardingStep.orderedCases.firstIndex(of: current) ?? 0
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
}

private extension VoiceOnboardingStep {
    var setupSubtitle: String {
        switch self {
        case .welcome:
            "Overview"
        case .asr:
            "Recognition engine"
        case .llm:
            "Cleanup"
        case .hotkey:
            "Activation"
        case .languages:
            "Recognition bias"
        case .tryIt:
            "Try"
        case .done:
            "Finish"
        }
    }

    var setupSymbol: String {
        switch self {
        case .welcome:
            "mic.badge.plus"
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
