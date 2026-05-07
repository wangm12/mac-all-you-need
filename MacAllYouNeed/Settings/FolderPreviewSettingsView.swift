import Core
import SwiftUI

struct FolderPreviewSettingsView: View {
    let controller: AppController
    @AppStorage("folderPreviewIncludeHidden", store: AppGroupSettings.defaults) private var includeHidden = false
    @AppStorage("folderPreviewMaxEntries", store: AppGroupSettings.defaults) private var maxEntries = 50_000
    var body: some View {
        Form {
            Toggle("Include hidden files", isOn: $includeHidden)
            Stepper("Max entries: \(maxEntries)", value: $maxEntries, in: 1000...500_000, step: 1000)
        }.padding()
    }
}
