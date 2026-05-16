import FeatureCore
import SwiftUI

enum FolderPreviewDescriptor {
    static func descriptor() -> FeatureDescriptor {
        FeatureDescriptor(
            id: .folderPreview,
            displayName: "Folder Preview",
            icon: "folder",
            summary: "Quick Look HTML preview of folders and archives.",
            detailDescription: "Press space on any folder or archive to see a browsable preview without opening Finder.",
            hotkeys: [HotkeyDescriptor(identifier: "folderPreview.browse", displayName: "Browse folder")],
            osExtensionPolicy: .staticBundleExtension(StaticExtensionConfig(
                extensionBundleID: "com.macallyouneed.app.folderpreview",
                runsRegardlessOfFeatureState: true,
                respectsFeatureFlag: true
            )),
            activator: FolderPreviewFeatureActivator()
            // settingsTabFactory is nil: SettingsDetailContent wires FolderPreviewSettingsView directly.
        )
    }
}
