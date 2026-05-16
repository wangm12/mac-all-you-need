import Foundation
import FeatureCore

public enum SideloadInstaller {
    public static func install(
        zipURL: URL,
        userProvidedZipSha256: String,
        featurePackKey: String,
        manifest: FeaturePackManifest,
        featureLiveBaseDir: URL,
        stagingDir: URL,
        options: PackInstaller.Options = .init()
    ) throws -> PackInstaller.Report {
        // Pre-check: user-supplied SHA must match before we do anything else.
        let actual = try SHA256Hasher.hex(ofFileAt: zipURL)
        guard actual == userProvidedZipSha256 else {
            throw PackPipelineError.wholeZipShaMismatch(expected: userProvidedZipSha256, actual: actual)
        }
        guard let entry = manifest.packs[featurePackKey] else {
            throw PackPipelineError.missingFile(name: featurePackKey)
        }
        // Reuse the full install pipeline (which re-verifies the manifest's recorded zip SHA).
        return try PackInstaller.install(
            packZipURL: zipURL,
            entry: entry,
            featureLiveBaseDir: featureLiveBaseDir,
            stagingDir: stagingDir,
            options: options
        )
    }
}
