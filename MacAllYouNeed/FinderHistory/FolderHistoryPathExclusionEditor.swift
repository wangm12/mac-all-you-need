import AppKit
import SwiftUI

/// Lets the user exclude folder paths from Finder history capture.
struct FolderHistoryPathExclusionEditor: View {
    @Binding var paths: [String]
    let save: ([String]) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(paths, id: \.self) { path in
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "folder")
                        .foregroundStyle(MAYNTheme.muted)
                    Text(path)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    MAYNButton("Remove", role: .destructive, height: HotkeyChipPresentation.compactHeight) {
                        paths.removeAll { $0 == path }
                        persist()
                    }
                }
                .padding(.vertical, 4)
                MAYNDivider()
            }

            MAYNSettingsRow(
                title: "Add folder",
                subtitle: "Folders you exclude are never recorded in history."
            ) {
                MAYNButton(role: .secondary, height: MAYNControlMetrics.controlHeight, action: chooseFolder) {
                    Label("Choose Folder…", systemImage: "folder.badge.plus")
                }
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Exclude Folder from History"
        panel.prompt = "Exclude"
        panel.message = "Choose a folder to exclude from Finder Folder History."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false

        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            let path = url.path
            if !paths.contains(path) {
                paths.append(path)
            }
        }
        persist()
    }

    private func persist() {
        paths.sort()
        save(paths)
    }
}
