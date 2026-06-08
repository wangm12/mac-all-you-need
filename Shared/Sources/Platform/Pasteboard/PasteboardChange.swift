import Foundation

public struct PasteboardChange: Equatable, Sendable {
    public let changeCount: Int
    public let frontmostAppBundleID: String?
    public let items: [PasteboardItem]
    public let pasteboardTypes: [String]

    public init(
        changeCount: Int,
        frontmostAppBundleID: String?,
        items: [PasteboardItem],
        pasteboardTypes: [String] = []
    ) {
        self.changeCount = changeCount
        self.frontmostAppBundleID = frontmostAppBundleID
        self.items = items
        self.pasteboardTypes = pasteboardTypes
    }

    public var historyCaptureItems: [PasteboardItem] {
        let capturableItems = items.filter(\.hasVisibleHistoryContent)

        for item in capturableItems {
            if case .png = item { return [item] }
        }
        for item in capturableItems {
            if case .tiff = item { return [item] }
        }

        let hasPlainText = capturableItems.contains { item in
            if case .text = item { return true }
            return false
        }
        let hasRTF = capturableItems.contains { item in
            if case .rtf = item { return true }
            return false
        }
        if hasPlainText || hasRTF {
            return capturableItems.filter { item in
                if case .html = item { return false }
                return true
            }
        }
        return capturableItems
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

private extension PasteboardItem {
    var hasVisibleHistoryContent: Bool {
        switch self {
        case let .text(text):
            return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case let .html(html):
            return !Self.visibleHTMLText(html).isEmpty
        case let .rtf(data):
            return !data.isEmpty
        case .png, .tiff, .fileURLs, .unknown:
            return true
        }
    }

    static func visibleHTMLText(_ html: String) -> String {
        html
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
