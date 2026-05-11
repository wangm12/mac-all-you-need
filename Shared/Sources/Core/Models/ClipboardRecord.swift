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
    /// User-set rename label. When non-nil, the dock UI shows this in place
    /// of the auto-generated `preview`. Persisted in `clipboard_records`
    /// (migration 003-custom-label).
    public let customLabel: String?

    public init(
        id: RecordID,
        created: Date,
        modified: Date,
        deviceID: DeviceID,
        lamport: UInt64,
        kind: RecordKind,
        preview: String,
        sourceAppBundleID: String?,
        frequency: Int,
        lastAccessed: Date?,
        customLabel: String? = nil
    ) {
        self.id = id
        self.created = created
        self.modified = modified
        self.deviceID = deviceID
        self.lamport = lamport
        self.kind = kind
        self.preview = preview
        self.sourceAppBundleID = sourceAppBundleID
        self.frequency = frequency
        self.lastAccessed = lastAccessed
        self.customLabel = customLabel
    }
}
