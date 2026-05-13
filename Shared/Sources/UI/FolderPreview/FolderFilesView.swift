import Platform
import SwiftUI

struct FolderFilesView: View {
    let entries: [FolderEntry]
    let onAction: ((PreviewAction) -> Void)?
    let onOpenFolder: (URL) -> Void

    var body: some View {
        Group {
            if entries.isEmpty {
                FolderPreviewStateView(
                    symbol: "doc.text.magnifyingglass",
                    title: "No files to show",
                    message: nil
                )
            } else {
                Table(entries) {
                    TableColumn("Name") { entry in
                        let url = URL(fileURLWithPath: entry.path)
                        Button {
                            if entry.isDirectory {
                                onOpenFolder(url)
                            } else {
                                onAction?(.open(url))
                            }
                        } label: {
                            Label {
                                Text(entry.name)
                                    .font(.system(size: 12))
                                    .lineLimit(1)
                            } icon: {
                                Image(systemName: iconName(for: entry))
                                    .foregroundStyle(FolderPreviewUI.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Open") { onAction?(.open(url)) }
                            Button("Copy") { onAction?(.copy(url)) }
                            Button("Reveal in Finder") { onAction?(.revealInFinder(url)) }
                        }
                    }
                    TableColumn("Size") { entry in
                        Text(entry.isDirectory ? "-" : ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(FolderPreviewUI.secondary)
                    }
                    TableColumn("Modified") {
                        Text($0.modified, style: .date)
                            .font(.system(size: 12))
                            .foregroundStyle(FolderPreviewUI.secondary)
                    }
                    TableColumn("Kind") {
                        Text(FolderPreviewDisplay.displayKind(for: $0))
                            .font(.system(size: 12))
                            .foregroundStyle(FolderPreviewUI.secondary)
                    }
                }
                .scrollContentBackground(.hidden)
                .background(FolderPreviewUI.background)
            }
        }
    }

    private func iconName(for entry: FolderEntry) -> String {
        if entry.isDirectory { return "folder" }
        switch entry.kind {
        case .images: return "photo"
        case .videos: return "film"
        case .audio: return "waveform"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .documents: return "doc.text"
        case .archives: return "archivebox"
        case .other, .folder: return "doc"
        }
    }
}

extension FolderEntry: Identifiable { public var id: String {
    path
} }
