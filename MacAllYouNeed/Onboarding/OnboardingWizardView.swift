import AppKit
import ApplicationServices
import SwiftUI

struct OnboardingWizardView: View {
    let controller: AppController
    @State private var step: OnboardingState
    @State private var accessibilityGranted = AXIsProcessTrusted()

    init(controller: AppController) {
        self.controller = controller
        let loaded = controller.onboarding
        _step = State(initialValue: loaded == .notStarted ? .welcome : loaded)
    }

    var body: some View {
        SetupWizardShell(
            title: "Mac All You Need",
            subtitle: "Initial setup",
            steps: stepDescriptors,
            currentStep: step,
            canGoBack: stepIndex > 0,
            canSkip: step != .ready,
            primaryTitle: primaryTitle,
            canAdvance: canAdvance,
            back: back,
            skip: advance,
            primaryAction: step == .ready ? { setStep(.completed) } : advance
        ) {
            Group {
                switch step {
                case .welcome: WelcomeStep(next: advance)
                case .accessibility: AccessibilityStep(next: advance, permissionChanged: { accessibilityGranted = $0 })
                case .fullDiskAccess: FullDiskAccessStep(next: advance)
                case .notifications: NotificationsStep(next: advance)
                case .sync: SyncSetupStep(controller: controller, next: advance)
                case .ready: ReadyStep(close: { setStep(.completed) })
                default: EmptyView()
                }
            }
        }
        .frame(width: 760, height: 520)
        .onAppear { setStep(step) }
    }

    private var stepOrder: [OnboardingState] {
        [.welcome, .accessibility, .fullDiskAccess, .notifications, .sync, .ready]
    }
    private var stepIndex: Int { stepOrder.firstIndex(of: step) ?? 0 }
    private var canAdvance: Bool {
        step != .accessibility || accessibilityGranted
    }

    private var primaryTitle: String {
        switch step {
        case .welcome:
            "Get Started"
        case .ready:
            "Done"
        case .accessibility, .fullDiskAccess, .notifications, .sync:
            "Continue"
        case .notStarted, .completed:
            "Continue"
        }
    }

    private var stepDescriptors: [SetupStepDescriptor<OnboardingState>] {
        stepOrder.enumerated().map { index, candidate in
            SetupStepDescriptor(
                id: candidate,
                title: candidate.setupTitle,
                subtitle: candidate.setupSubtitle,
                symbol: candidate.setupSymbol,
                isCompleted: index < stepIndex
            )
        }
    }

    private func advance() {
        if let idx = stepOrder.firstIndex(of: step), idx + 1 < stepOrder.count {
            setStep(stepOrder[idx + 1])
        } else {
            setStep(.completed)
        }
    }

    private func back() {
        guard let idx = stepOrder.firstIndex(of: step), idx > 0 else { return }
        setStep(stepOrder[idx - 1])
    }

    private func setStep(_ newValue: OnboardingState) {
        step = newValue
        controller.setOnboarding(newValue)
        if newValue == .completed {
            NSApplication.shared.keyWindow?.close()
        }
    }
}

extension OnboardingState: Identifiable {
    var id: String { rawValue }
}

private extension OnboardingState {
    var setupTitle: String {
        switch self {
        case .welcome, .notStarted:
            "Welcome"
        case .accessibility:
            "Accessibility"
        case .fullDiskAccess:
            "Full Disk Access"
        case .notifications:
            "Notifications"
        case .sync:
            "Sync"
        case .ready, .completed:
            "Ready"
        }
    }

    var setupSubtitle: String {
        switch self {
        case .welcome, .notStarted:
            "What the app does"
        case .accessibility:
            "Paste and snippets"
        case .fullDiskAccess:
            "Browser cookies"
        case .notifications:
            "Download alerts"
        case .sync:
            "Storage choice"
        case .ready, .completed:
            "Start using it"
        }
    }

    var setupSymbol: String {
        switch self {
        case .welcome, .notStarted:
            "sparkles"
        case .accessibility:
            "accessibility"
        case .fullDiskAccess:
            "externaldrive"
        case .notifications:
            "bell"
        case .sync:
            "arrow.triangle.2.circlepath"
        case .ready, .completed:
            "checkmark"
        }
    }
}

struct SetupStepDescriptor<ID: Hashable>: Identifiable {
    let id: ID
    let title: String
    let subtitle: String
    let symbol: String
    let isCompleted: Bool
}

struct SetupWizardShell<StepID: Hashable, Content: View>: View {
    let title: String
    let subtitle: String
    let steps: [SetupStepDescriptor<StepID>]
    let currentStep: StepID
    let canGoBack: Bool
    let canSkip: Bool
    let primaryTitle: String
    let canAdvance: Bool
    let back: () -> Void
    let skip: () -> Void
    let primaryAction: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle()
                .fill(MAYNTheme.divider)
                .frame(width: 1)
            VStack(spacing: 0) {
                ScrollView {
                    content
                        .frame(maxWidth: 460, alignment: .topLeading)
                        .padding(.horizontal, 34)
                        .padding(.vertical, 30)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Rectangle()
                    .fill(MAYNTheme.divider)
                    .frame(height: 1)
                actionBar
            }
        }
        .background(MAYNTheme.window)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(steps) { descriptor in
                    SetupProgressRow(
                        descriptor: descriptor,
                        isCurrent: descriptor.id == currentStep
                    )
                }
            }

            Spacer()
        }
        .frame(width: 220, alignment: .topLeading)
        .padding(22)
        .background(MAYNTheme.panel)
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            MAYNButton("Back", action: back)
                .disabled(!canGoBack)
            if canSkip {
                MAYNButton("Skip", action: skip)
            }
            Spacer()
            MAYNButton(primaryTitle, role: .primary, action: primaryAction)
                .keyboardShortcut(.return)
                .disabled(!canAdvance)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(MAYNTheme.panel)
    }
}

private struct SetupProgressRow<StepID: Hashable>: View {
    let descriptor: SetupStepDescriptor<StepID>
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: descriptor.isCompleted ? "checkmark.circle.fill" : descriptor.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(isCurrent ? Color.primary.opacity(0.12) : Color.primary.opacity(0.06))
                )
                .overlay(Circle().stroke(isCurrent ? MAYNTheme.strongBorder : MAYNTheme.subtleBorder, lineWidth: 1))

            VStack(alignment: .leading, spacing: 2) {
                Text(descriptor.title)
                    .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? .primary : .secondary)
                Text(descriptor.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(isCurrent ? MAYNTheme.selected : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct SetupTaskPage<Content: View>: View {
    let symbol: String
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
                    )
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(size: 26, weight: .semibold))
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            content
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
