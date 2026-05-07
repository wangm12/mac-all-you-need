import SwiftUI

struct OnboardingWizardView: View {
    let controller: AppController
    @State private var step: OnboardingState

    init(controller: AppController) {
        self.controller = controller
        let loaded = controller.onboarding
        _step = State(initialValue: loaded == .notStarted ? .welcome : loaded)
    }

    var body: some View {
        VStack {
            ProgressView(value: progressFraction).padding()
            Group {
                switch step {
                case .welcome: WelcomeStep(next: advance)
                case .accessibility: AccessibilityStep(next: advance)
                case .fullDiskAccess: FullDiskAccessStep(next: advance)
                case .notifications: NotificationsStep(next: advance)
                case .sync: SyncSetupStep(controller: controller, next: advance)
                case .ready: ReadyStep(close: { setStep(.completed) })
                default: EmptyView()
                }
            }
            HStack {
                Button("Skip") { advance() }
                Spacer()
                Text("\(stepIndex + 1) / 6").foregroundStyle(.secondary)
            }.padding()
        }
        .frame(width: 540, height: 420)
        .onAppear { setStep(step) }
    }

    private var stepOrder: [OnboardingState] {
        [.welcome, .accessibility, .fullDiskAccess, .notifications, .sync, .ready]
    }
    private var stepIndex: Int { stepOrder.firstIndex(of: step) ?? 0 }
    private var progressFraction: Double { Double(stepIndex + 1) / Double(stepOrder.count) }

    private func advance() {
        if let idx = stepOrder.firstIndex(of: step), idx + 1 < stepOrder.count {
            setStep(stepOrder[idx + 1])
        } else {
            setStep(.completed)
        }
    }

    private func setStep(_ newValue: OnboardingState) {
        step = newValue
        controller.setOnboarding(newValue)
    }
}
