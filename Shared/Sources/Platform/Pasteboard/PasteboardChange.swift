import Foundation

public struct PasteboardChange: Equatable, Sendable {
    public let changeCount: Int
    public let frontmostAppBundleID: String?
    public let items: [PasteboardItem]
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
