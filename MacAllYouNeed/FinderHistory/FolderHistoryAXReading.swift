import ApplicationServices
import Core
import Foundation

/// Injectable seam for reading the AX document path from a Finder window element.
/// Allows tests to substitute a fake without a live accessibility connection.
protocol FolderHistoryAXReader: Sendable {
    func documentPath(for windowElement: AXUIElement) -> String?
}

/// Production reader: pulls `kAXDocumentAttribute` from the focused window and
/// normalizes it to a canonical POSIX path.
struct SystemFolderHistoryAXReader: FolderHistoryAXReader {
    func documentPath(for windowElement: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(windowElement, kAXDocumentAttribute as CFString, &value) == .success,
              let urlString = value as? String
        else { return nil }
        return FolderPathNormalizer.normalize(urlString)
    }
}
