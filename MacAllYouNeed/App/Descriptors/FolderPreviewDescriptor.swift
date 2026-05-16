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
            activator: FolderPreviewFeatureActivator(),
            // Phase 05 will replace with FolderPreviewSettingsView(controller: AppController.shared)
            settingsTabFactory: { AnyView(Text("Folder preview settings — wired in Phase 05.").padding()) }
        )
    }
}
