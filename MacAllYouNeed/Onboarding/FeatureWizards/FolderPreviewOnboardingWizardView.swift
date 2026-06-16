import SwiftUI

struct FolderPreviewOnboardingWizardView: View {
    let controller: AppController
    @Environment(\.onboardingTryItSucceeded) private var tryItSucceeded
    @State private var statusMessage: String?

    private let examples: [OnboardingExample] = [
        .init(icon: "folder", input: "Project folder in Finder", output: "Space → HTML preview"),
        .init(icon: "doc.zip", input: "Archive.zip", output: "Browse entries in Quick Look"),
    ]

    var body: some View {
        FeatureOnboardingPage(
            bullets: [
                "Press Space on any folder or archive in Finder for a browsable Quick Look preview.",
                "Open Browse Folder for a full-window explorer with Files, Grid, and Analyze modes."
            ],
            previewTitle: "Preview",
            previewSubtitle: "Finder Quick Look and Browse Folder.",
            preview: {
                FolderPreviewOnboardingIllustration()
            },
            examples: examples,
            tryItSubtitle: "Open the bundled sample folder in Browse Folder.",
            tryIt: {
            OnboardingTryItPanel(
                instruction: "Opens Browse Folder with a sample project folder so you can verify the file list appears.",
                statusMessage: statusMessage
            ) {
                HStack(spacing: 10) {
                    MAYNButton("Open sample folder", role: .primary) {
                        openSampleFolder()
                    }
                    ShortcutChip(text: "⌘⇧F", height: HotkeyChipPresentation.compactHeight)
                }
            }
        },
        footnote: "Tune hidden files, cascade folders, and entry limits on the Enhanced Finder page."
        )
    }

    private func openSampleFolder() {
        guard let url = OnboardingSampleResources.folderPreviewSampleURL else {
            statusMessage = "Sample folder is missing from the app bundle."
            return
        }
        controller.folder.show(at: url)
        OnboardingTryItReporter.markSucceeded(tryItSucceeded)
        statusMessage = "Browse Folder opened. Enhanced Finder is ready."
    }
}

private struct FolderPreviewOnboardingIllustration: View {
    var body: some View {
        OnboardingPanel {
            HStack(spacing: 16) {
                VStack(spacing: 8) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("Finder")
                        .font(.caption.weight(.medium))
                }
                Image(systemName: "arrow.right")
                    .foregroundStyle(.tertiary)
                VStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 52, height: 32)
                        .overlay {
                            Text("Space")
                                .font(.caption2.weight(.semibold))
                        }
                    Text("Quick Look")
                        .font(.caption.weight(.medium))
                }
                Image(systemName: "arrow.right")
                    .foregroundStyle(.tertiary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("src/")
                        .font(.caption.monospaced())
                    Text("README.md")
                        .font(.caption.monospaced())
                    Text("assets/")
                        .font(.caption.monospaced())
                }
                .padding(10)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .frame(maxWidth: .infinity)
        }
    }
}

enum OnboardingSampleResources {
    static var folderPreviewSampleURL: URL? {
        bundledDirectory(named: "sample-folder")
    }

    static var organizerSampleURL: URL? {
        bundledDirectory(named: "organizer-sample")
    }

    private static func bundledDirectory(named name: String) -> URL? {
        let candidate = Bundle.main.resourceURL?.appendingPathComponent("Onboarding/\(name)")
        guard let candidate, FileManager.default.fileExists(atPath: candidate.path) else { return nil }
        return candidate
    }
}
