import FeatureCore
import SwiftUI

enum DockPreviewsDescriptor {
    static func descriptor() -> FeatureDescriptor {
        FeatureDescriptor(
            id: .dockPreviews,
            displayName: "Dock Previews",
            icon: "macwindow.on.rectangle",
            summary: "Hover a Dock icon to preview and raise that app's windows.",
            detailDescription: "When you hover an app's Dock icon, a floating panel shows thumbnails of all "
                + "its open windows; click one to raise that exact window. Window thumbnails need Screen "
                + "Recording permission — without it, the panel degrades gracefully to a titles-only list. "
                + "Disabled by default.",
            requiredPermissions: [.accessibility, .screenRecording],
            activator: DockPreviewsFeatureActivator(),
            settingsTabFactory: { AnyView(DockPreviewSettingsView()) }
        )
    }
}
