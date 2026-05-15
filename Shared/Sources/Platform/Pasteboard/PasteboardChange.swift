import Foundation

public struct PasteboardChange: Equatable, Sendable {
    public let changeCount: Int
    public let frontmostAppBundleID: String?
    public let items: [PasteboardItem]

    public var historyCaptureItems: [PasteboardItem] {
        for item in items {
            if case .png = item { return [item] }
        }
        for item in items {
            if case .tiff = item { return [item] }
        }

        let hasPlainText = items.contains { item in
            if case .text = item { return true }
            return false
        }
        let hasRTF = items.contains { item in
            if case .rtf = item { return true }
            return false
        }
        if hasPlainText || hasRTF {
            return items.filter { item in
                if case .html = item { return false }
                return true
            }
        }
        return items
    }
}

public enum PasteboardItem: Equatable, Sendable {
    case text(String)
    case rtf(Data)
    case html(String)
    case png(Data)
    case tiff(Data)
    case fileURLs([URL])
    case unknown(uti: String, data: Data)
}
