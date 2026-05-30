import Foundation

public enum ManifestOperationState: String, Codable, Sendable {
    case pending, applied, undone, failed
}

public struct ManifestOperation: Codable, Sendable, Identifiable {
    public let id: String
    public let sourceURL: URL
    public let destinationURL: URL
    public var state: ManifestOperationState
    public let appliedAt: Date?

    public init(id: String = UUID().uuidString, sourceURL: URL, destinationURL: URL, state: ManifestOperationState = .pending, appliedAt: Date? = nil) {
        self.id = id
        self.sourceURL = sourceURL
        self.destinationURL = destinationURL
        self.state = state
        self.appliedAt = appliedAt
    }
}

public struct Manifest: Codable, Sendable, Identifiable {
    public let id: String
    public var operations: [ManifestOperation]
    public let createdAt: Date
    public var state: ManifestOperationState

    public init(id: String = UUID().uuidString, operations: [ManifestOperation] = [], createdAt: Date = Date(), state: ManifestOperationState = .pending) {
        self.id = id
        self.operations = operations
        self.createdAt = createdAt
        self.state = state
    }
}
