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
    /// Smart Text detection JSON (`Detection.encodedJSON()`). Persisted in
    /// `clipboard_records.detected_type` (migration 008-smart-text). Nil for
    /// records captured before Smart Text was enabled.
    public let detectedTypeJSON: String?
    /// Background Vision OCR result for image records. Persisted in
    /// `clipboard_records.ocr_text` (migration 008-smart-text).
    public let ocrText: String?
    /// Apple NLEmbedding vector for semantic search, encoded little-endian via
    /// `ClipEmbeddingService.encode`. Persisted in `clipboard_records.embedding`
    /// (migration 008-smart-text).
    public let embedding: Data?

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
        customLabel: String? = nil,
        detectedTypeJSON: String? = nil,
        ocrText: String? = nil,
        embedding: Data? = nil
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
        self.detectedTypeJSON = detectedTypeJSON
        self.ocrText = ocrText
        self.embedding = embedding
    }
}
