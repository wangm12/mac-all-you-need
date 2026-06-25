import Core
import SwiftUI

// MARK: - Folder open target

struct DownloadFolderOpenTarget: Equatable {
    let selectionURL: URL

    var folderURL: URL { selectionURL }

    static func forRecord(
        _ record: DownloadRecord,
        downloadDir: String,
        resolvedDestinationPath: String? = nil
    ) -> DownloadFolderOpenTarget {
        let path = (resolvedDestinationPath ?? record.destinationPath)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !path.isEmpty, !path.contains("%("), FileManager.default.fileExists(atPath: path) {
            return DownloadFolderOpenTarget(selectionURL: URL(fileURLWithPath: path))
        }
        if let collectionURL = collectionFolderURL(for: record, downloadDir: downloadDir) {
            return DownloadFolderOpenTarget(selectionURL: collectionURL)
        }
        if !path.isEmpty, !path.contains("%(") {
            return DownloadFolderOpenTarget(
                selectionURL: URL(fileURLWithPath: path).deletingLastPathComponent()
            )
        }
        return defaultDownloadFolder(downloadDir: downloadDir)
    }

    static func group(
        _ group: DownloadCollectionGrouping.Group,
        downloadDir: String
    ) -> DownloadFolderOpenTarget {
        DownloadFolderOpenTarget(
            selectionURL: DownloadCollectionPresentation.collectionFolderURL(
                for: group,
                downloadDir: downloadDir
            )
        )
    }

    static func completedRecord(_ record: DownloadRecord) -> DownloadFolderOpenTarget {
        forRecord(record, downloadDir: "")
    }

    static func defaultDownloadFolder(downloadDir: String) -> DownloadFolderOpenTarget {
        DownloadFolderOpenTarget(
            selectionURL: URL(
                fileURLWithPath: DownloadDestinationPresentation.effectivePath(downloadDir: downloadDir),
                isDirectory: true
            )
        )
    }

    private static func collectionFolderURL(
        for record: DownloadRecord,
        downloadDir: String
    ) -> URL? {
        guard record.collectionID != nil else { return nil }
        let useSubfolder = AppGroupSettings.defaults.object(forKey: "downloadCollectionSubfolder") as? Bool ?? true
        guard useSubfolder else { return nil }
        let title = record.collectionTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty else { return nil }
        let base = URL(
            fileURLWithPath: DownloadDestinationPresentation.effectivePath(downloadDir: downloadDir),
            isDirectory: true
        )
        return base.appendingPathComponent(
            DownloadDestinationBuilder.sanitizeFolderName(title),
            isDirectory: true
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
                Text("Paste one or more video URLs. Playlists, channels, and creator profiles open a picker first. Browser Auto cookies work by default; Mac All You Need Companion sync is optional.")
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
