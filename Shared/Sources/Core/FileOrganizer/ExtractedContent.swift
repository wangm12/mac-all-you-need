import Foundation

public enum ContentKind: String, Codable, Sendable, CaseIterable {
    case text, pdf, image, spreadsheet, archive, unknown
}

public struct ExtractedContent: Codable, Sendable, Equatable {
    public let originalURL: URL
    public let utTypeIdentifier: String
    public let kind: ContentKind
    public let snippet: String
    public let metadata: [String: String]

    public init(originalURL: URL, utTypeIdentifier: String, kind: ContentKind, snippet: String, metadata: [String: String] = [:]) {
        self.originalURL = originalURL
        self.utTypeIdentifier = utTypeIdentifier
        self.kind = kind
        self.snippet = snippet
        self.metadata = metadata
    }

    public var originalFilename: String { originalURL.lastPathComponent }
    public var fileExtension: String { originalURL.pathExtension.lowercased() }
}
