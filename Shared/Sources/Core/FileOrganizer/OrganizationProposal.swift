import Foundation

public struct ProposedOperation: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let sourceURL: URL
    public let proposedFilename: String
    public let proposedSubfolder: String?
    public let confidence: Double
    public var isApproved: Bool

    public init(id: String = UUID().uuidString, sourceURL: URL, proposedFilename: String, proposedSubfolder: String? = nil, confidence: Double = 1.0, isApproved: Bool = true) {
        self.id = id
        self.sourceURL = sourceURL
        self.proposedFilename = proposedFilename
        self.proposedSubfolder = proposedSubfolder
        self.confidence = confidence
        self.isApproved = isApproved
    }

    public var destinationPath: String {
        if let sub = proposedSubfolder { return "\(sub)/\(proposedFilename)" }
        return proposedFilename
    }
}

public struct OrganizationProposal: Codable, Sendable {
    public let rootURL: URL
    public var operations: [ProposedOperation]
    public let createdAt: Date

    public init(rootURL: URL, operations: [ProposedOperation], createdAt: Date = Date()) {
        self.rootURL = rootURL
        self.operations = operations
        self.createdAt = createdAt
    }

    public var approvedOperations: [ProposedOperation] { operations.filter { $0.isApproved } }
}
