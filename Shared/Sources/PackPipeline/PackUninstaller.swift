import Foundation

public enum PackUninstaller {
    public static func uninstall(featureLiveBaseDir: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: featureLiveBaseDir.path) else { return }
        try fm.removeItem(at: featureLiveBaseDir)
    }
}
