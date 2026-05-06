import Foundation

public struct EnvelopeMetadata: Codable, Equatable, Sendable {
    public let kind: RecordKind
    public let id: RecordID
    public let created: Date
    public let modified: Date
    public let deviceID: DeviceID
    public let lamport: UInt64

    public init(kind: RecordKind, id: RecordID, created: Date, modified: Date, deviceID: DeviceID, lamport: UInt64) {
        self.kind = kind
        self.id = id
        self.created = created
        self.modified = modified
        self.deviceID = deviceID
        self.lamport = lamport
    }

    enum CodingKeys: String, CodingKey {
        case kind, id, created, modified
        case deviceID = "device_id"
        case lamport
    }
}

public struct Envelope: Equatable, Sendable {
    public let combined: Data
    public init(combined: Data) {
        self.combined = combined
    }
}
