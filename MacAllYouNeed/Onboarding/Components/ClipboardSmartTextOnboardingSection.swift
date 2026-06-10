import FeatureCore
import SwiftUI

private struct SmartTextOnboardingExample: Identifiable {
    let id = UUID()
    let icon: String
    let input: String
    let output: String
}

/// Smart Text opt-in body (header provided by parent section).
struct ClipboardSmartTextOnboardingSection: View {
    let controller: AppController
    @State private var isEnabled = false
    @State private var statePublisher: FeatureStatePublisher

    private let examples: [SmartTextOnboardingExample] = [
        .init(icon: "function", input: "2 + 2", output: "= 4"),
        .init(icon: "link", input: "…?utm_source=newsletter", output: "Clean link copied"),
        .init(icon: "text.viewfinder", input: "Screenshot image", output: "Text recognized"),
    ]

    init(controller: AppController) {
        self.controller = controller
        _statePublisher = State(initialValue: controller.featureStatePublisher)
    }

    var body: some View {
        OnboardingPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    Text("Enable Smart Text")
                        .font(.callout.weight(.medium))
                    Spacer(minLength: 0)
                    Toggle("", isOn: $isEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .maynSwitchToggleStyle()
                        .onChange(of: isEnabled) { _, enabled in
                            Task {
                                let transition: FeatureManager.Transition = enabled ? .enable : .disable
                                try? await controller.runtime.applyTransition(transition, for: .clipboardSmartText)
                                await statePublisher.refresh()
                            }
                        }
                }

                VStack(spacing: 6) {
                    ForEach(examples) { example in
                        SmartTextExampleRow(example: example, dimmed: !isEnabled)
                    }
                }

                Text("Tune detection rules anytime in Clipboard settings.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .opacity(isEnabled ? 1 : 0.78)
        }
        .onAppear {
            isEnabled = statePublisher.state(for: .clipboardSmartText).activationState == .enabled
        }
        .onChange(of: statePublisher.states) { _, _ in
            isEnabled = statePublisher.state(for: .clipboardSmartText).activationState == .enabled
        }
    }
}

private struct SmartTextExampleRow: View {
    let example: SmartTextOnboardingExample
    let dimmed: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: example.icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5, style: .continuous))

            Text(example.input)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "arrow.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)

            Text(example.output)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(MAYNTheme.elevated.opacity(dimmed ? 0.45 : 1), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
