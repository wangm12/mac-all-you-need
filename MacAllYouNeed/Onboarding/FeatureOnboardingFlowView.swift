import FeatureCore
import SwiftUI

/// Shared download + config flow for main onboarding and standalone feature windows.
struct FeatureOnboardingFlowView: View {
    @Bindable var coordinator: FeatureSetupCoordinator
    let showsFooter: Bool
    var tryItSucceeded: Binding<Bool>? = nil
    var onBack: (() -> Void)? = nil
    let onFinished: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                flowBody
                    .frame(maxWidth: 500, alignment: .topLeading)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showsFooter {
                Rectangle()
                    .fill(MAYNTheme.divider)
                    .frame(height: 1)
                footer
            }
        }
        .background(MAYNTheme.window)
    }

    @ViewBuilder
    private var flowBody: some View {
        switch coordinator.subStep {
        case .idle:
            ProgressView("Preparing…")
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
                .task { await coordinator.start() }
        case .download(let progress):
            FeatureSetupDownloadView(
                descriptor: coordinator.descriptor,
                progress: progress,
                failureReason: nil,
                onRetry: { coordinator.retryDownload() }
            )
        case .downloadFailed(let reason):
            FeatureSetupDownloadView(
                descriptor: coordinator.descriptor,
                progress: 0,
                failureReason: reason,
                onRetry: { coordinator.retryDownload() }
            )
        case .config:
            FeatureOnboardingStepView(
                descriptor: coordinator.descriptor,
                tryItSucceeded: tryItSucceeded
            )
        case .complete:
            Color.clear.frame(height: 1)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let onBack {
                MAYNButton("Back", action: onBack)
            }
            Spacer()
            MAYNButton(footerTitle, role: .primary, action: handlePrimary)
                .keyboardShortcut(.return)
                .disabled(!canAdvance)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(MAYNTheme.panel)
    }

    private var footerTitle: String {
        switch coordinator.subStep {
        case .download, .downloadFailed:
            return "Continue"
        default:
            return "Done"
        }
    }

    private var canAdvance: Bool {
        switch coordinator.subStep {
        case .config:
            return true
        case .complete:
            return true
        case .download:
            return true
        case .downloadFailed:
            return false
        case .idle:
            return true
        }
    }

    private func handlePrimary() {
        switch coordinator.subStep {
        case .config, .complete:
            coordinator.markConfigDone()
            onFinished()
        default:
            break
        }
    }
}
