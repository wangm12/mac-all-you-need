import Foundation

/// Pure conversion from a raw AX document value (file URL string or POSIX path)
/// into a canonical POSIX path suitable for storage and comparison.
public enum FolderPathNormalizer {
    public static func normalize(_ raw: String) -> String? {
        guard !raw.isEmpty else { return nil }
        var path: String
        if raw.hasPrefix("file://") {
            guard let url = URL(string: raw) else { return nil }
            path = url.path
        } else {
            path = raw
        }
        // Resolve symlinked prefixes (e.g. /private/var → /var) and clean up "." / ".."
        let url = URL(fileURLWithPath: path)
        path = url.standardized.path
        // Strip trailing slash, except for the root "/".
        if path.hasSuffix("/"), path != "/" {
            path = String(path.dropLast())
        }
        return path.isEmpty ? nil : path
    }
}
