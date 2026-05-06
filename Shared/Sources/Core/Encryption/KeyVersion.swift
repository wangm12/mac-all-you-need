import Foundation

public struct KeyVersion: Hashable, Equatable, Codable, Sendable {
    public let value: Int
    public init(_ value: Int) { self.value = value }
    public static let v1 = KeyVersion(1)
}
