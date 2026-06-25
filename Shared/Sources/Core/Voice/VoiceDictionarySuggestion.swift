import Foundation

public struct VoiceDictionarySuggestion: Identifiable, Equatable, Sendable {
    public enum Status: String, Equatable, Sendable {
        case pending
        case accepted
        case dismissed
    }

    public let id: String
    public let phrase: String
    public let replacement: String
    public let normKey: String
    public let occurrences: Int
    public let status: Status
    public let firstSeenAt: Date
    public let updatedAt: Date

    public init(
        id: String,
        phrase: String,
        replacement: String,
        normKey: String,
        occurrences: Int,
        status: Status,
        firstSeenAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.phrase = phrase
        self.replacement = replacement
        self.normKey = normKey
        self.occurrences = occurrences
        self.status = status
        self.firstSeenAt = firstSeenAt
        self.updatedAt = updatedAt
    }
}
