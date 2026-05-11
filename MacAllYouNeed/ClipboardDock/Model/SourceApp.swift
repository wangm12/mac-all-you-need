import AppKit
import Foundation

struct SourceApp: Hashable {
    let bundleID: String
    let displayName: String
    let icon: NSImage?

    static func == (lhs: SourceApp, rhs: SourceApp) -> Bool {
        lhs.bundleID == rhs.bundleID && lhs.displayName == rhs.displayName
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(bundleID)
        hasher.combine(displayName)
    }
}
