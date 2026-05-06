import Foundation

public struct DeviceID: Hashable, Equatable, Codable, Sendable {
    public let rawValue: String

    public init?(rawValue: String) {
        guard UUID(uuidString: rawValue) != nil else { return nil }
        self.rawValue = rawValue
    }

    public static func generate() -> DeviceID {
        DeviceID(rawValue: UUID().uuidString)!
    }
}
