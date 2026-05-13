import Core
import SwiftUI

struct FolderPreviewSettingsView: View {
    let controller: AppController
    @AppStorage("folderPreviewIncludeHidden", store: AppGroupSettings.defaults) private var includeHidden = false
    @AppStorage("folderPreviewMaxEntries", store: AppGroupSettings.defaults) private var maxEntries = 50_000
    var body: some View {
        MAYNSettingsPage(
            title: "Folder Preview",
            subtitle: "Tune how much folder and archive content Quick Look indexes before rendering a preview."
        ) {
            MAYNSection(title: "Enumeration") {
                MAYNSettingsRow(
                    title: "Include hidden files",
                    subtitle: "Show dotfiles and hidden entries in folder previews."
                ) {
                    Toggle("", isOn: $includeHidden)
                        .labelsHidden()
                }
                MAYNDivider()
                MAYNSettingsRow(
                    title: "Maximum entries",
                    subtitle: "Upper bound for very large folders and archives."
                ) {
                    Stepper("\(maxEntries)", value: $maxEntries, in: 1000...500_000, step: 1000)
                        .labelsHidden()
                        .frame(width: 110)
                }
            }
        }
    }
}
