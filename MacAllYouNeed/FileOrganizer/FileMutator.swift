import Core
import Foundation

/// Applies and rolls back file operations against the real filesystem.
final class FileMutator {
    enum MutatorError: Error {
        case sourceNotFound(URL)
        case destinationConflict(URL)
        case rollbackFailed([Error])
    }

    /// Applies pending operations from a manifest. Returns errors per operation (partial success allowed).
    func apply(manifest: inout Manifest, rootURL: URL) -> [Error] {
        var errors: [Error] = []
        for (i, op) in manifest.operations.enumerated() {
            guard op.state == .pending else { continue }
            do {
                let parent = op.destinationURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: op.sourceURL, to: op.destinationURL)
                manifest.operations[i] = ManifestOperation(
                    id: op.id, sourceURL: op.sourceURL, destinationURL: op.destinationURL,
                    state: .applied, appliedAt: Date()
                )
            } catch {
                manifest.operations[i] = ManifestOperation(
                    id: op.id, sourceURL: op.sourceURL, destinationURL: op.destinationURL,
                    state: .failed, appliedAt: nil
                )
                errors.append(error)
            }
        }
        return errors
    }

    /// Undoes all applied operations in reverse order.
    func rollback(manifest: inout Manifest) -> [Error] {
        var errors: [Error] = []
        for (i, op) in manifest.operations.enumerated().reversed() {
            guard op.state == .applied else { continue }
            do {
                try FileManager.default.moveItem(at: op.destinationURL, to: op.sourceURL)
                manifest.operations[i] = ManifestOperation(
                    id: op.id, sourceURL: op.sourceURL, destinationURL: op.destinationURL,
                    state: .undone, appliedAt: nil
                )
            } catch {
                errors.append(error)
            }
        }
        return errors
    }
}
