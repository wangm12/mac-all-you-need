import Foundation

/// Stores operation manifests as JSON files in the App Group container.
/// O(N) directory scan is acceptable for typical manifest counts (<100).
public final class OrganizerManifestStore {
    private let directory: URL

    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func save(_ manifest: Manifest) throws {
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: manifestURL(id: manifest.id))
    }

    public func load(id: String) throws -> Manifest? {
        let url = manifestURL(id: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url))
    }

    public func all() throws -> [Manifest] {
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        return urls.filter { $0.pathExtension == "json" }.compactMap { url in
            try? JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url))
        }.sorted { $0.createdAt > $1.createdAt }
    }

    public func delete(id: String) throws {
        let url = manifestURL(id: id)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func manifestURL(id: String) -> URL {
        directory.appendingPathComponent("\(id).json")
    }
}
