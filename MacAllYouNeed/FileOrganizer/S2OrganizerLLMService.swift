import Core
import Foundation

/// Real OrganizerLLMService backed by the S2 shared LLM layer (same Groq/local selection as Voice).
final class S2OrganizerLLMService: OrganizerLLMServiceProtocol, @unchecked Sendable {
    private let generate: (String, String) async throws -> String

    /// Production: inject via `VoiceTextGenerationProvider.generate(systemPrompt:userText:)`
    init(generate: @escaping (String, String) async throws -> String) {
        self.generate = generate
    }

    private static let systemPrompt = """
    You are a file organization assistant. Given file metadata and a content snippet,
    suggest a clean, descriptive filename (without extension) and optionally a subfolder path.

    Respond in this exact format:
    NAME: <suggested filename without extension>
    FOLDER: <optional subfolder like "2026/Invoices" — omit if no clear category>

    Rules:
    - Filename should be descriptive but concise (max 80 chars)
    - Use title case
    - No special characters except spaces and hyphens
    - Subfolder depth max 2 levels (e.g., "Year/Category")
    - If uncertain, just suggest the NAME and omit FOLDER
    """

    func suggest(for request: OrganizerLLMRequest) async throws -> OrganizerLLMResponse {
        let userPrompt = """
        Filename: \(request.originalFilename)
        Type: \(request.contentKind.rawValue)
        Content: \(request.contentSnippet.prefix(300))
        """
        let response = try await generate(Self.systemPrompt, userPrompt)
        return parseResponse(response)
    }

    private func parseResponse(_ raw: String) -> OrganizerLLMResponse {
        var name = ""
        var folder: String?
        for line in raw.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("NAME:") { name = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces) }
            if trimmed.hasPrefix("FOLDER:") { folder = String(trimmed.dropFirst(7)).trimmingCharacters(in: .whitespaces) }
        }
        let cleanedFolder = (folder?.isEmpty ?? true) ? nil : folder
        return OrganizerLLMResponse(suggestedName: name.isEmpty ? "unnamed" : name, suggestedSubfolder: cleanedFolder)
    }
}
