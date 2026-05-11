import Foundation

public struct Pinboard: Codable, Equatable, Sendable {
    public let id: RecordID
    public var name: String
    public var color: String?
    public var itemIDs: [RecordID]
    public var modified: Date
    public var deviceID: DeviceID?
    public var lamport: UInt64

    public init(name: String, color: String? = nil, itemIDs: [RecordID] = []) {
        id = RecordID.generate()
        self.name = name
        self.color = color
        self.itemIDs = itemIDs
        modified = Date()
        deviceID = nil
        lamport = 0
    }
}
