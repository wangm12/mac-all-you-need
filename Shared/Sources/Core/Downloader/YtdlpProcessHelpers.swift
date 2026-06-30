import Foundation

public enum YtdlpProcessHelpers {
    /// Finds Node.js for yt-dlp's JavaScript extraction (required in yt-dlp 2026+).
    public static func findNode() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let nvmNode = "\(home)/.nvm/versions/node"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvmNode),
           let latest = versions.sorted().last
        {
            let path = "\(nvmNode)/\(latest)/bin/node"
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return ["/usr/local/bin/node", "/opt/homebrew/bin/node", "/usr/bin/node"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
