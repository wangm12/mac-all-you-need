import Foundation

/// Resolves a filesystem folder URL for dock stack items (Downloads, Applications, etc.).
enum DockDockFolderItemResolver {
    /// Returns a directory URL when the dock item represents a pinned folder stack.
    static func resolveFolderURL(axURL: URL?, title: String?) -> URL? {
        if let axURL {
            if axURL.pathExtension == "app" {
                return wellKnownUserFolderURL(matchingTitle: title)
            }
            if isExistingDirectory(axURL) {
                return axURL.standardizedFileURL
            }
        }
        return wellKnownUserFolderURL(matchingTitle: title)
    }

    private static func isExistingDirectory(_ url: URL) -> Bool {
        if let values = try? url.resourceValues(forKeys: [.isDirectoryKey]), values.isDirectory == true {
            return true
        }
        var isDirectory: ObjCBool = false
        let path = url.resolvingSymlinksInPath().path
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    /// Maps dock titles to real paths when AX exposes `Finder.app` or no URL (common on recent macOS).
    static func wellKnownUserFolderURL(matchingTitle title: String?) -> URL? {
        guard let title else { return nil }
        let key = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }

        let fileManager = FileManager.default
        let known: [(String, () -> URL?)] = [
            ("Downloads", { fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first }),
            ("Desktop", { fileManager.urls(for: .desktopDirectory, in: .userDomainMask).first }),
            ("Documents", { fileManager.urls(for: .documentDirectory, in: .userDomainMask).first }),
            ("Applications", { URL(fileURLWithPath: "/Applications", isDirectory: true) }),
            ("Home", { fileManager.homeDirectoryForCurrentUser }),
        ]

        if let match = known.first(where: { $0.0.caseInsensitiveCompare(key) == .orderedSame })?.1() {
            return match
        }

        for candidate in known {
            guard let url = candidate.1() else { continue }
            if fileManager.displayName(atPath: url.path).caseInsensitiveCompare(key) == .orderedSame {
                return url
            }
        }
        return nil
    }
}
