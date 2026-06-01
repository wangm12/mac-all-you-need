import FeatureCore
import SwiftUI

enum DockPreviewsDescriptor {
    static func descriptor() -> FeatureDescriptor {
        FeatureDescriptor(
            id: .dockPreviews,
            displayName: "Dock",
            icon: "dock.rectangle",
            summary: "Dock hover previews, window switcher, Cmd+Tab, dock lock, and active-app indicator.",
            detailDescription: "Unified Dock enhancements: hover icons for window previews, Option+Tab window "
                + "switcher, optional Cmd+Tab previews, multi-monitor dock lock, and an underline on the "
                + "active Dock icon. Screen Recording improves thumbnails but titles-only mode works without it.",
            requiredPermissions: [.accessibility, .screenRecording],
            activator: DockPreviewsFeatureActivator(),
            settingsTabFactory: { AnyView(DockPreviewSettingsView()) }
        )
    }
}
