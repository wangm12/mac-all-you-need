import Foundation

public struct FeaturePackManifest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let wrapperVersion: String
    public let packs: [String: PackEntry]

    public struct PackEntry: Codable, Equatable, Sendable {
        public let version: String
        public let url: URL
        public let zipSha256: String
        public let sizeBytes: Int64
        public let files: [String: FileEntry]
        public let codesignRequirement: String
    }

    public struct FileEntry: Codable, Equatable, Sendable {
        public let sha256: String
        public let executable: Bool
        public let maxBytes: Int64
    }

    public enum DecodingFailure: Error, Equatable {
        case schemaMismatch(expected: Int, found: Int)
    }

    public static func decode(from data: Data, expectedSchemaVersion: Int) throws -> FeaturePackManifest {
        let manifest = try JSONDecoder().decode(FeaturePackManifest.self, from: data)
        if manifest.schemaVersion != expectedSchemaVersion {
            throw DecodingFailure.schemaMismatch(expected: expectedSchemaVersion, found: manifest.schemaVersion)
        }
        return manifest
    }
}
