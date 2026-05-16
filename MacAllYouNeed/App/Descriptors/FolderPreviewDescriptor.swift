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
            activator: NoopFeatureActivator()
        )
    }
}
