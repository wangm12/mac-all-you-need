import Platform
import SwiftUI

struct FolderFilesView: View {
    let inventory: FolderInventory
    let onAction: ((PreviewAction) -> Void)?
    let onOpenFolder: (URL) -> Void

    var body: some View {
        Table(inventory.entries) {
            TableColumn("Name") { entry in
                let url = URL(fileURLWithPath: entry.path)
                Button {
                    if entry.isDirectory {
                        onOpenFolder(url)
                    } else {
                        onAction?(.open(url))
                    }
                } label: {
                    Label(entry.name, systemImage: entry.isDirectory ? "folder" : "doc")
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Open") { onAction?(.open(url)) }
                    Button("Copy") { onAction?(.copy(url)) }
                    Button("Reveal in Finder") { onAction?(.revealInFinder(url)) }
                }
            }
            TableColumn("Size") { entry in
                Text(ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file))
            }
            TableColumn("Modified") { Text($0.modified, style: .date) }
            TableColumn("Kind") { Text($0.kind.rawValue) }
        }
    }
}

extension FolderEntry: Identifiable { public var id: String {
    path
} }
