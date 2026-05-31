import ApplicationServices
import Core
import Foundation

/// Injectable seam for reading the AX document path from a Finder window element.
/// Allows tests to substitute a fake without a live accessibility connection.
protocol FolderHistoryAXReader: Sendable {
    func documentPath(for windowElement: AXUIElement) -> String?
}

/// Production reader: tries kAXDocumentAttribute first (most Finder windows),
/// then kAXURLAttribute as a fallback for modern macOS Finder variants.
struct SystemFolderHistoryAXReader: FolderHistoryAXReader {
    func documentPath(for windowElement: AXUIElement) -> String? {
        // kAXDocumentAttribute returns a file URL string on most Finder windows.
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(windowElement, kAXDocumentAttribute as CFString, &value) == .success,
           let raw = value as? String,
           let normalized = FolderPathNormalizer.normalize(raw) {
            return normalized
        }
        // Fallback: some modern macOS Finder windows expose kAXURLAttribute instead.
        if AXUIElementCopyAttributeValue(windowElement, kAXURLAttribute as CFString, &value) == .success {
            if let url = value as? URL {
                return FolderPathNormalizer.normalize(url.absoluteString)
            }
            if let raw = value as? String {
                return FolderPathNormalizer.normalize(raw)
            }
        }
        return nil
    }
}
