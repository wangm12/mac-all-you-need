import Foundation

/// Loads and caches the wrapper-bundled FeaturePackManifest.json.
/// Lookup by FeatureID maps to the manifest's pack key (raw value of FeatureID).
public final class FeatureManifestLoader: @unchecked Sendable {
    public enum LoadError: Error, Equatable {
        case fileMissing(URL)
        case packNotInManifest(String)
    }

    public let manifestURL: URL
    public let expectedSchemaVersion: Int
    private let lock = NSLock()
    private var cached: FeaturePackManifest?

    public init(manifestURL: URL, expectedSchemaVersion: Int = 1) {
        self.manifestURL = manifestURL
        self.expectedSchemaVersion = expectedSchemaVersion
    }

    /// Convenience initializer that resolves the manifest from a bundle.
    /// Returns nil if the bundle does not contain `FeaturePackManifest.json`.
    public static func bundled(in bundle: Bundle = .main) -> FeatureManifestLoader? {
        guard let url = bundle.url(forResource: "FeaturePackManifest", withExtension: "json") else {
            return nil
        }
        return FeatureManifestLoader(manifestURL: url)
    }

    public func load() throws -> FeaturePackManifest {
        lock.lock()
        defer { lock.unlock() }
        if let cached { return cached }
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw LoadError.fileMissing(manifestURL)
        }
        let data = try Data(contentsOf: manifestURL)
        let manifest = try FeaturePackManifest.decode(from: data, expectedSchemaVersion: expectedSchemaVersion)
        cached = manifest
        return manifest
    }

    public func packEntry(forFeatureID id: FeatureID) throws -> FeaturePackManifest.PackEntry {
        let manifest = try load()
        guard let entry = manifest.packs[id.rawValue] else {
            throw LoadError.packNotInManifest(id.rawValue)
        }
        return entry
    }
}
