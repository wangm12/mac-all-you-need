import Foundation

public enum QuarantineRemover {
    private static let xattrName = "com.apple.quarantine"

    public static func hasQuarantine(at url: URL) -> Bool {
        let size = getxattr(url.path, xattrName, nil, 0, 0, 0)
        return size >= 0
    }

    public static func remove(at url: URL) throws {
        guard hasQuarantine(at: url) else { return }
        let result = removexattr(url.path, xattrName, 0)
        if result != 0 {
            throw PackPipelineError.quarantineRemovalFailed(name: url.lastPathComponent)
        }
    }
}
