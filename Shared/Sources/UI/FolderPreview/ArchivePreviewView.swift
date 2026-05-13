import Platform
import SwiftUI

public struct ArchivePreviewView: View {
    public let archiveURL: URL
    @State private var entries: [ArchiveEntry] = []
    @State private var error: String?
    @State private var isLoading = false

    public init(archiveURL: URL) {
        self.archiveURL = archiveURL
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "archivebox")
                    .foregroundStyle(FolderPreviewUI.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(archiveURL.lastPathComponent)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Text("\(entries.count) entries")
                        .font(.system(size: 11))
                        .foregroundStyle(FolderPreviewUI.secondary)
                }
                Spacer()
                if !entries.isEmpty {
                    FolderPreviewStatusBadge(text: "Archive", kind: .neutral)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(FolderPreviewUI.header)
            Divider()
            if isLoading {
                FolderPreviewStateView(
                    symbol: "archivebox",
                    title: "Reading archive",
                    message: archiveURL.path,
                    isLoading: true
                )
            } else if let error {
                FolderPreviewStateView(
                    symbol: "exclamationmark.triangle",
                    title: "Could not read archive",
                    message: error,
                    kind: .error
                )
            } else if entries.isEmpty {
                FolderPreviewStateView(
                    symbol: "archivebox",
                    title: "Archive is empty",
                    message: archiveURL.path
                )
            } else {
                List(entries, id: \.path) { entry in
                    HStack(spacing: 10) {
                        Image(systemName: entry.isDirectory ? "folder" : "doc")
                            .foregroundStyle(FolderPreviewUI.secondary)
                            .frame(width: 18)
                        Text(entry.path)
                            .font(.system(size: 12))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(entry.isDirectory ? "-" : ByteCountFormatter.string(fromByteCount: entry.uncompressedSize, countStyle: .file))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(FolderPreviewUI.secondary)
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(FolderPreviewUI.background)
            }
        }
        .background(FolderPreviewUI.background)
        .task(id: archiveURL) {
            isLoading = true
            error = nil
            entries = []
            do {
                entries = try LibArchiveBackend().list(archiveURL: archiveURL, limits: .default)
            } catch {
                self.error = "Could not read archive: \(error.localizedDescription)"
            }
            isLoading = false
        }
    }
}
