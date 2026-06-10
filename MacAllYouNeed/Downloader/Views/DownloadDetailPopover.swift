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
                Text("Paste one or more video URLs. Playlists, channels, and creator profiles open a picker first.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TextEditor(text: $urlString)
                .font(.body)
                .frame(width: MAYNControlMetrics.wideTextFieldWidth, height: 120)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(MAYNTheme.elevated, in: RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius)
                        .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
                )

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
        .frame(width: 480)
        .background(MAYNTheme.window)
    }
}
