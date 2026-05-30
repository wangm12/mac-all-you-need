import Foundation

/// Orchestrates: content list → LLM suggestions → sanitize → collision-resolve → proposal.
public final class OrganizerEngine {
    private let llmService: any OrganizerLLMServiceProtocol
    private let namingPattern: NamingPattern

    public init(llmService: any OrganizerLLMServiceProtocol, namingPattern: NamingPattern = .text(caseStyle: .titleCase)) {
        self.llmService = llmService
        self.namingPattern = namingPattern
    }

    public func propose(contents: [ExtractedContent], rootURL: URL) async throws -> OrganizationProposal {
        var existingNames: Set<String> = []
        var operations: [ProposedOperation] = []

        for content in contents {
            let req = OrganizerLLMRequest(
                contentSnippet: content.snippet,
                originalFilename: content.originalFilename,
                contentKind: content.kind,
                metadata: content.metadata
            )
            do {
                let resp = try await llmService.suggest(for: req)
                let rawName = resp.suggestedName
                let sanitizedName = FilenameSanitizer.sanitize(rawName, extension: content.fileExtension)
                let withExt = sanitizedName.isEmpty ? content.originalFilename : "\(sanitizedName).\(content.fileExtension)"
                let finalName = CollisionResolver.resolve(desired: withExt, existing: existingNames)
                existingNames.insert(finalName)

                // Determine subfolder depth (path separator count)
                let subfolderDepth = resp.suggestedSubfolder.map { $0.filter { $0 == "/" }.count } ?? 0
                let subfolder = subfolderDepth <= 3 ? resp.suggestedSubfolder : nil  // cap at 3 levels

                let op = ProposedOperation(
                    sourceURL: content.originalURL,
                    proposedFilename: finalName,
                    proposedSubfolder: subfolder,
                    confidence: resp.confidence
                )
                operations.append(op)
            } catch {
                // On LLM error: keep original filename
                operations.append(ProposedOperation(sourceURL: content.originalURL, proposedFilename: content.originalFilename, confidence: 0))
            }
        }

        return OrganizationProposal(rootURL: rootURL, operations: operations)
    }
}
