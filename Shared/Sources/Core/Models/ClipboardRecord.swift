import Foundation

public enum ClipboardRecord: Codable, Equatable, Sendable {
    case text(String)
    case rtf(Data)
    case html(String)
    case image(blobID: String, width: Int, height: Int)
    case files([URL])
}

public struct ClipboardItemMeta: Equatable, Sendable {
    public let id: RecordID
    public let created: Date
    public let modified: Date
    public let deviceID: DeviceID
    public let lamport: UInt64
    public let kind: RecordKind
    public let preview: String
    public let sourceAppBundleID: String?
    public let frequency: Int
    public let lastAccessed: Date?
}
