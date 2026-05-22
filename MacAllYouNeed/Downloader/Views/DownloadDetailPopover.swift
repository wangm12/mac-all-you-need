import Core
import SwiftUI

// MARK: - Folder open target

struct DownloadFolderOpenTarget: Equatable {
    let folderURL: URL

    static func completedRecord(_ record: DownloadRecord) -> DownloadFolderOpenTarget {
        DownloadFolderOpenTarget(
            folderURL: URL(fileURLWithPath: record.destinationPath).deletingLastPathComponent()
        )
    }

    static func defaultDownloadFolder(downloadDir: String) -> DownloadFolderOpenTarget {
        DownloadFolderOpenTarget(
            folderURL: URL(
                fileURLWithPath: DownloadDestinationPresentation.effectivePath(downloadDir: downloadDir),
                isDirectory: true
            )
        )
    }
}

// MARK: - Add URL sheet

struct DownloadAddURLSheet: View {
    @Binding var urlString: String
    let onCancel: () -> Void
    let onDownload: (String) -> Void

    private var trimmedURL: String {
        urlString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Add download URL")
                    .font(.title3.weight(.semibold))
                Text("Paste a video or audio URL. Metadata is fetched before the download starts.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            MAYNTextField(
                placeholder: "https://www.youtube.com/watch?v=...",
                text: $urlString,
                width: MAYNControlMetrics.wideTextFieldWidth,
                autofocus: true
            )

            HStack(spacing: 8) {
                StatusPill(text: "Ready", kind: .neutral)
                Text("Metadata will appear immediately after enqueue.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                MAYNButton("Cancel", action: onCancel)
                MAYNButton("Download", role: .primary) {
                    onDownload(trimmedURL)
                }
                .disabled(trimmedURL.isEmpty)
                .keyboardShortcut(.return)
            }
        }
        .padding(24)
        .frame(width: 430)
        .background(MAYNTheme.window)
    }
}
