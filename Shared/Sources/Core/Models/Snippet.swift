import Foundation

public struct Snippet: Codable, Equatable, Sendable {
    public let id: RecordID
    public var trigger: String?
    public var name: String
    public var body: String
    public var modified: Date
    public var deviceID: DeviceID?
    public var lamport: UInt64

    public init(name: String, body: String, trigger: String? = nil) {
        id = RecordID.generate()
        self.name = name
        self.body = body
        self.trigger = trigger
        modified = Date()
        deviceID = nil
        lamport = 0
    }
}
