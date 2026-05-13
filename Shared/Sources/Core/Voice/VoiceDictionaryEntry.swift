import Foundation

public struct VoiceDictionaryEntry: Identifiable, Sendable, Equatable {
    public let id: String
    public let phrase: String
    public let replacement: String
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: String,
        phrase: String,
        replacement: String,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.phrase = phrase
        self.replacement = replacement
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
