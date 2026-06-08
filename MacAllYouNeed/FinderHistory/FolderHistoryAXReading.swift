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
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(windowElement, kAXDocumentAttribute as CFString, &value) == .success,
           let normalized = Self.normalizedPath(from: value)
        {
            return normalized
        }
        value = nil
        if AXUIElementCopyAttributeValue(windowElement, kAXURLAttribute as CFString, &value) == .success,
           let normalized = Self.normalizedPath(from: value)
        {
            return normalized
        }
        return nil
    }

    private static func normalizedPath(from value: CFTypeRef?) -> String? {
        guard let value else { return nil }
        if let raw = value as? String {
            return FolderPathNormalizer.normalize(raw)
        }
        if let url = value as? URL {
            return FolderPathNormalizer.normalize(url.path)
        }
        if let url = value as? NSURL, let path = url.path {
            return FolderPathNormalizer.normalize(path)
        }
        if CFGetTypeID(value) == CFURLGetTypeID() {
            let cfURL = value as! CFURL // swiftlint:disable:this force_cast
            if let path = CFURLCopyFileSystemPath(cfURL, .cfurlposixPathStyle) as String? {
                return FolderPathNormalizer.normalize(path)
            }
        }
        return nil
    }
}
