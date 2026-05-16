import FeatureCore
import SwiftUI

struct FeatureSetupDownloadView: View {
    let descriptor: FeatureDescriptor
    let progress: Double
    let failureReason: String?
    let onRetry: () -> Void

    var body: some View {
        SetupTaskPage(
            symbol: "arrow.down.circle",
            title: "Installing \(descriptor.displayName)…",
            subtitle: "This downloads the \(descriptor.displayName) binaries the first time you enable the feature."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                if let failureReason {
                    StatusPill(text: failureReason, kind: .danger)
                    MAYNButton("Retry", role: .primary, action: onRetry)
                } else {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 360)
                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Continue is available when the install finishes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
