import SwiftUI

/// Guided try-it block with optional status feedback.
struct OnboardingTryItPanel<Actions: View>: View {
    let instruction: String
    var statusMessage: String?
    var statusKind: StatusPill.Kind = .neutral
    var showsConfirm: Bool = false
    var confirmTitle: String = "Continue"
    var isConfirmEnabled: Bool = true
    var onConfirm: () -> Void = {}
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        OnboardingPanel {
            VStack(alignment: .leading, spacing: 12) {
                Text(instruction)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                actions()

                if showsConfirm {
                    MAYNButton(confirmTitle, role: .primary, action: onConfirm)
                        .disabled(!isConfirmEnabled)
                }

                if let statusMessage, !statusMessage.isEmpty {
                    StatusPill(text: statusMessage, kind: statusKind)
                }
            }
        }
    }
}
