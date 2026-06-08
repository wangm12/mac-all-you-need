import AppKit
import Foundation

@MainActor
final class AppIconResolver {
    private var iconCache: [String: NSImage] = [:]
    private var nameCache: [String: String] = [:]

    func icon(for bundleID: String) -> NSImage? {
        if let cached = iconCache[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 32, height: 32)
        iconCache[bundleID] = icon
        return icon
    }

    /// Resolves icons and display names for unique bundle IDs before building dock rows.
    func prefetch(bundleIDs: [String]) {
        for id in Set(bundleIDs) where !id.isEmpty {
            _ = icon(for: id)
            _ = displayName(for: id)
        }
    }

    func displayName(for bundleID: String) -> String {
        if let cached = nameCache[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
              let bundle = Bundle(url: url)
        else {
            nameCache[bundleID] = bundleID
            return bundleID
        }
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? bundleID
        nameCache[bundleID] = name
        return name
    }
}
