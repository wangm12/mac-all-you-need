import Foundation

public struct OrganizerLLMRequest: Sendable {
    public let contentSnippet: String
    public let originalFilename: String
    public let contentKind: ContentKind
    public let metadata: [String: String]

    public init(contentSnippet: String, originalFilename: String, contentKind: ContentKind, metadata: [String: String] = [:]) {
        self.contentSnippet = contentSnippet
        self.originalFilename = originalFilename
        self.contentKind = contentKind
        self.metadata = metadata
    }
}

public struct OrganizerLLMResponse: Sendable {
    public let suggestedName: String        // filename without extension
    public let suggestedSubfolder: String?  // relative path like "2026/Invoices"
    public let confidence: Double           // 0.0-1.0

    public init(suggestedName: String, suggestedSubfolder: String? = nil, confidence: Double = 1.0) {
        self.suggestedName = suggestedName
        self.suggestedSubfolder = suggestedSubfolder
        self.confidence = confidence
    }
}

public protocol OrganizerLLMServiceProtocol: Sendable {
    func suggest(for request: OrganizerLLMRequest) async throws -> OrganizerLLMResponse
}

public final class FakeOrganizerLLMService: OrganizerLLMServiceProtocol, @unchecked Sendable {
    private(set) public var callCount = 0
    public var throwOnIndex: Int?
    public var responses: [OrganizerLLMResponse]

    public init(responses: [OrganizerLLMResponse] = []) {
        self.responses = responses
    }

    public func suggest(for request: OrganizerLLMRequest) async throws -> OrganizerLLMResponse {
        defer { callCount += 1 }
        if let throwOnIndex, callCount == throwOnIndex { throw NSError(domain: "FakeLLM", code: 0) }
        let idx = min(callCount, responses.count - 1)
        return responses.isEmpty ? OrganizerLLMResponse(suggestedName: "suggested-name") : responses[idx]
    }
}
