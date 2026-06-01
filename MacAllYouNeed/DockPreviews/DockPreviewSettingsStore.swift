import Core
import Foundation

enum DockPreviewSettingsStore {
    // Load/save implemented in DockHubSettingsStore.swift (unified hub blob).
}

extension Notification.Name {
    static let dockPreviewSettingsDidChange = Notification.Name("dockPreviewSettingsDidChange")
}
