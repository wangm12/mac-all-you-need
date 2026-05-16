import Foundation

public struct AssetPack: Equatable, Sendable {
    public let id: String                      // matches FeatureID raw string
    public let bundledManifestKey: String      // key into FeaturePackManifest.packs
    public init(id: String, bundledManifestKey: String) {
        self.id = id
        self.bundledManifestKey = bundledManifestKey
    }
}
