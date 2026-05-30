import Foundation

public enum CollisionResolver {
    /// Given a desired filename and a set of existing names in the directory,
    /// returns a unique name by appending " (2)", " (3)", etc.
    public static func resolve(desired: String, existing: Set<String>) -> String {
        if !existing.contains(desired) { return desired }
        let parts = desired.components(separatedBy: ".")
        let name: String
        let ext: String
        if parts.count > 1 {
            ext = parts.last!
            name = parts.dropLast().joined(separator: ".")
        } else {
            name = desired
            ext = ""
        }
        var i = 2
        while i < 10000 {
            let candidate = ext.isEmpty ? "\(name) (\(i))" : "\(name) (\(i)).\(ext)"
            if !existing.contains(candidate) { return candidate }
            i += 1
        }
        return "\(name) (\(UUID().uuidString.prefix(8))).\(ext)"
    }
}
