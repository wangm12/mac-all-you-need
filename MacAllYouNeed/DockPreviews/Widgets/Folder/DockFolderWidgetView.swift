import AppKit
import SwiftUI

/// Dock folder stack preview (DockDoor `FolderWidgetView` subset).
struct DockFolderWidgetView: View {
    let title: String
    let url: URL
    let showHidden: Bool

    private var entries: [(name: String, isDirectory: Bool)] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isHiddenKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: keys,
            options: showHidden ? [] : [.skipsHiddenFiles]
        ) else { return [] }
        return urls.prefix(24).compactMap { item in
            let values = try? item.resourceValues(forKeys: Set(keys))
            let name = item.lastPathComponent
            return (name, values?.isDirectory == true)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .lineLimit(1)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                        HStack(spacing: 8) {
                            Image(systemName: entry.isDirectory ? "folder" : "doc")
                                .foregroundStyle(.secondary)
                            Text(entry.name)
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .frame(maxHeight: 220)
        }
        .frame(minWidth: 260)
    }
}
