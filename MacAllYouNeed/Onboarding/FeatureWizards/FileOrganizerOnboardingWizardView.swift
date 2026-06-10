import SwiftUI

struct FileOrganizerOnboardingWizardView: View {
    let controller: AppController
    @Environment(\.onboardingTryItSucceeded) private var tryItSucceeded
    @State private var statusMessage: String?
    @State private var statusKind: StatusPill.Kind = .neutral
    @State private var proposalCount = 0
    @State private var isScanning = false

    private let examples: [OnboardingExample] = [
        .init(icon: "photo", input: "IMG_0042.jpg", output: "2024-06-beach.jpg"),
        .init(icon: "doc", input: "scan001.pdf", output: "Invoices/2024-03-utilities.pdf"),
    ]

    var body: some View {
        FeatureOnboardingPage(
            bullets: [
                "Scan a folder, extract on-device text from images and PDFs, then propose cleaner names and subfolders.",
                "Review every change before applying — manifests make operations reversible."
            ],
            examples: examples,
            tryItSubtitle: "Scan the bundled sample folder (no Full Disk Access required).",
            tryIt: {
            OnboardingTryItPanel(
                instruction: "Runs a real scan on sample files in the app bundle. Requires an AI cleanup provider configured in Voice settings.",
                statusMessage: statusMessage,
                statusKind: statusKind
            ) {
                MAYNButton(isScanning ? "Scanning…" : "Scan sample folder", role: .primary) {
                    Task { await runSampleScan() }
                }
                .disabled(isScanning)
            }
        },
        footnote: "Full Disk Access unlocks Downloads and other folders. Configure the LLM provider under Voice → AI cleanup."
        )
    }

    private func runSampleScan() async {
        guard let url = OnboardingSampleResources.organizerSampleURL else {
            statusMessage = "Sample folder is missing from the app bundle."
            statusKind = .warning
            return
        }
        guard let coordinator = controller.fileOrganizerCoordinator else {
            statusMessage = "Organizer is not available. Enable AI File Organizer and configure an LLM provider."
            statusKind = .warning
            return
        }
        isScanning = true
        defer { isScanning = false }
        if let proposal = await coordinator.scan(url: url) {
            proposalCount = proposal.operations.count
            if proposalCount > 0 {
                statusMessage = "Found \(proposalCount) proposed rename\(proposalCount == 1 ? "" : "s"). AI File Organizer is ready."
                statusKind = .success
                OnboardingTryItReporter.markSucceeded(tryItSucceeded)
            } else {
                statusMessage = "Scan finished but no proposals were generated. Check your LLM provider settings."
                statusKind = .warning
            }
        } else {
            statusMessage = "Scan failed. Configure an AI provider in Voice settings, then try again."
            statusKind = .warning
        }
    }
}
