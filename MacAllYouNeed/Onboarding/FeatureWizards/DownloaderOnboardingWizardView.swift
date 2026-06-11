import SwiftUI

struct DownloaderOnboardingWizardView: View {
    let controller: AppController
    @Environment(\.onboardingTryItSucceeded) private var tryItSucceeded
    @State private var statusMessage: String?
    @State private var statusKind: StatusPill.Kind = .neutral
    @State private var isEnqueueing = false

    private static let sampleURL = "https://www.youtube.com/watch?v=jNQXAC9IVRw"

    private let examples: [OnboardingExample] = [
        .init(icon: "link", input: "YouTube watch URL", output: "Queued download"),
        .init(icon: "key", input: "Signed-in site", output: "Import cookies in settings"),
    ]

    var body: some View {
        FeatureOnboardingPage(
            bullets: [
                "Paste a video link on the Downloads page or send it from the optional Mac All You Need Companion.",
                "Browser Auto cookies work by default. Only use Mac All You Need Companion sync if you need exact Chrome session cookies."
            ],
            previewTitle: "Preview",
            previewSubtitle: "Queue and completed items live on the Downloads page.",
            preview: {
                DownloaderOnboardingQueuePreview()
            },
            examples: examples,
            tryItSubtitle: "Enqueue a sample URL to confirm the downloader is ready.",
            tryIt: {
            OnboardingTryItPanel(
                instruction: "Adds a short public sample clip to your queue. You can remove it later from Downloads.",
                statusMessage: statusMessage,
                statusKind: statusKind,
                showsConfirm: false
            ) {
                MAYNButton(isEnqueueing ? "Enqueueing…" : "Enqueue sample URL", role: .primary) {
                    Task { await enqueueSample() }
                }
                .disabled(isEnqueueing)
            }
        },
        footnote: "Downloads settings includes Browser Auto (recommended) and an optional guided Mac All You Need Companion setup."
        )
    }

    private func enqueueSample() async {
        isEnqueueing = true
        defer { isEnqueueing = false }
        let before = Set(controller.downloaderVM.rows.map(\.id))
        await controller.downloaderVM.coordinator.enqueue(url: Self.sampleURL, title: "MAYN setup sample", formatArgs: [])
        await controller.downloaderVM.refresh()
        let added = controller.downloaderVM.rows.first { !before.contains($0.id) }
        if added != nil {
            statusMessage = "Sample URL queued. Open Downloads to watch progress."
            statusKind = .success
            OnboardingTryItReporter.markSucceeded(tryItSucceeded)
        } else if controller.downloaderVM.rows.contains(where: { $0.url == Self.sampleURL }) {
            statusMessage = "Sample URL is already in your queue."
            statusKind = .neutral
            OnboardingTryItReporter.markSucceeded(tryItSucceeded)
        } else {
            statusMessage = "Could not enqueue the sample. Check downloader binaries in settings."
            statusKind = .warning
        }
    }
}

private struct DownloaderOnboardingQueuePreview: View {
    var body: some View {
        OnboardingPanel {
            VStack(alignment: .leading, spacing: 10) {
                previewRow(title: "MAYN setup sample", state: "Queued", symbol: "arrow.down.circle")
                previewRow(title: "Conference talk.mp4", state: "Completed", symbol: "checkmark.circle.fill")
            }
        }
    }

    private func previewRow(title: String, state: String, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(state)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}
