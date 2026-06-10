import Foundation

public struct FeaturePackManifest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let wrapperVersion: String
    public let packs: [String: PackEntry]

    public init(schemaVersion: Int, wrapperVersion: String, packs: [String: PackEntry]) {
        self.schemaVersion = schemaVersion
        self.wrapperVersion = wrapperVersion
        self.packs = packs
    }

    public struct PackEntry: Codable, Equatable, Sendable {
        /// True when the bundled manifest still has placeholder release URL / SHA values.
        /// Local dev builds seed packs from app resources instead of downloading.
        public var isDevPlaceholder: Bool {
            zipSha256.allSatisfy { $0 == "0" } || url.absoluteString.contains("<owner>")
        }

        public let version: String
        public let url: URL
        public let zipSha256: String
        public let sizeBytes: Int64
        public let files: [String: FileEntry]
        public let codesignRequirement: String

        public init(
            version: String,
            url: URL,
            zipSha256: String,
            sizeBytes: Int64,
            files: [String: FileEntry],
            codesignRequirement: String
        ) {
            self.version = version
            self.url = url
            self.zipSha256 = zipSha256
            self.sizeBytes = sizeBytes
            self.files = files
            self.codesignRequirement = codesignRequirement
        }
    }

    public struct FileEntry: Codable, Equatable, Sendable {
        public let sha256: String
        public let executable: Bool
        public let maxBytes: Int64

        public init(sha256: String, executable: Bool, maxBytes: Int64) {
            self.sha256 = sha256
            self.executable = executable
            self.maxBytes = maxBytes
        }
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
