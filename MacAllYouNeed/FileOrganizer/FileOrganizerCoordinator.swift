import Core
import Foundation

/// Composition root for the AI File Organizer feature.
@MainActor
final class FileOrganizerCoordinator {
    private let engine: OrganizerEngine
    private let manifestStore: OrganizerManifestStore
    private let fileMutator: FileMutator
    private weak var organizerWorker: OrganizerFeatureWorker?

    init(
        llmGenerate: @escaping (String, String) async throws -> String,
        organizerWorker: OrganizerFeatureWorker? = nil
    ) throws {
        let llmService = S2OrganizerLLMService(generate: llmGenerate)
        engine = OrganizerEngine(llmService: llmService)
        let dir = AppGroup.containerURL()
            .appendingPathComponent("organizer-manifests")
        manifestStore = try OrganizerManifestStore(directory: dir)
        fileMutator = FileMutator()
        self.organizerWorker = organizerWorker
    }

    func setOrganizerWorker(_ worker: OrganizerFeatureWorker?) {
        organizerWorker = worker
    }

    func scan(url: URL) async -> OrganizationProposal? {
        guard let files = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            .filter({ !$0.hasDirectoryPath }) else { return nil }
        let fileSlice = Array(files.prefix(50))
        let contents: [ExtractedContent]
        if let organizerWorker {
            contents = await organizerWorker.perform {
                await Self.extractContents(from: fileSlice)
            }
        } else {
            contents = await Self.extractContents(from: fileSlice)
        }
        return try? await engine.propose(contents: contents, rootURL: url)
    }

    private static func extractContents(from files: [URL]) async -> [ExtractedContent] {
        await withTaskGroup(of: ExtractedContent.self) { group in
            for file in files {
                group.addTask { await ContentExtractor.shared.extract(from: file) }
            }
            var results: [ExtractedContent] = []
            for await content in group { results.append(content) }
            return results
        }
    }

    /// Builds a manifest from the approved operations and applies them to the filesystem.
    /// The manifest is always persisted (even on partial failure) so the operation is reversible.
    func apply(proposal: OrganizationProposal) throws {
        let ops = proposal.approvedOperations.map { op -> ManifestOperation in
            let destURL = proposal.rootURL.appendingPathComponent(op.destinationPath)
            return ManifestOperation(sourceURL: op.sourceURL, destinationURL: destURL)
        }
        var manifest = Manifest(operations: ops)
        let errors = fileMutator.apply(manifest: &manifest, rootURL: proposal.rootURL)
        manifest.state = errors.isEmpty ? .applied : .failed
        try manifestStore.save(manifest)
        if let first = errors.first { throw first }
    }

    func history() throws -> [Manifest] {
        try manifestStore.all()
    }

    func undo(manifestID: String) throws {
        guard var manifest = try manifestStore.load(id: manifestID) else { return }
        let errors = fileMutator.rollback(manifest: &manifest)
        manifest.state = errors.isEmpty ? .undone : .failed
        try manifestStore.save(manifest)
        if let first = errors.first { throw first }
    }
}
