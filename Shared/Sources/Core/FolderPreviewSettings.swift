import Foundation

public enum FolderPreviewSettings {
    public static let cascadeKey = "folderPreviewCascade"
    public static let defaultCascadeEnabled = true

    public static func cascadeEnabled(defaults: UserDefaults = AppGroupSettings.defaults) -> Bool {
        defaults.object(forKey: cascadeKey) as? Bool ?? defaultCascadeEnabled
    }
}
