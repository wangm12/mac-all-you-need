import Platform
import SwiftUI

struct FolderFilesView: View {
    let inventory: FolderInventory
    let onAction: ((PreviewAction) -> Void)?
    let onOpenFolder: (URL) -> Void

    var body: some View {
        Table(inventory.entries) {
            TableColumn("Name") { entry in
                Button {
                    if entry.isDirectory { onOpenFolder(URL(fileURLWithPath: entry.path)) }
                    else { onAction?(.open(URL(fileURLWithPath: entry.path))) }
                } label: {
                    Label(entry.name, systemImage: entry.isDirectory ? "folder" : "doc")
                }
                .buttonStyle(.plain)
            }
            TableColumn("Size") { entry in
                Text(ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file))
            }
            TableColumn("Modified") { Text($0.modified, style: .date) }
            TableColumn("Kind") { Text($0.kind.rawValue) }
        }
        .contextMenu(forSelectionType: FolderEntry.ID.self) { _ in } primaryAction: { _ in }
    }
}

extension FolderEntry: Identifiable { public var id: String { path } }
