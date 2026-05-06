import Foundation

public enum RecordKind: String, Codable, CaseIterable, Sendable {
    case clipboardItem = "clipboard_item"
    case snippet
    case pinboard
    case settings
    case downloadHistory = "download_history"
}
