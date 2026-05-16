import FeatureCore
import Foundation

/// Pure decision function: turns (usage signal × asset presence) into a
/// `(FeatureRuntimeState, AssetSource)` pair. Spec § 7.2.
enum MigrationDecisionMatrix {
    enum AssetPresence: Equatable {
        /// Feature has no asset pack at all.
        case swiftOnly
        /// Pack files on disk, all per-file SHAs matched the manifest.
        case presentMatchingSHA(version: String)
        /// Pack files on disk but at least one per-file SHA failed to match.
        case shaMismatch(reason: String)
        /// No pack files on disk for this feature's expected version directory.
        case absent
    }

    static func decide(
        feature: FeatureID,
        requiresAsset: Bool,
        assetPresence: AssetPresence,
        priorUsage: PriorUsageLevel
    ) -> MigrationReport.Outcome {
        let activation: ActivationState = (priorUsage == .none) ? .disabled : .enabled

        if !requiresAsset {
            return MigrationReport.Outcome(
                resultingState: .init(assetState: .notRequired, activationState: activation),
                assetSource: .notRequired,
                priorUsage: priorUsage
            )
        }

        switch assetPresence {
        case .swiftOnly:
            // Defensive: requiresAsset && swiftOnly is contradictory; treat as Swift-only.
            return MigrationReport.Outcome(
                resultingState: .init(assetState: .notRequired, activationState: activation),
                assetSource: .notRequired,
                priorUsage: priorUsage
            )
        case .presentMatchingSHA(let version):
            return MigrationReport.Outcome(
                resultingState: .init(assetState: .present(version: version), activationState: activation),
                assetSource: .preInstallScript,
                priorUsage: priorUsage
            )
        case .shaMismatch(let reason):
            return MigrationReport.Outcome(
                resultingState: .init(
                    assetState: .downloadFailed(reason: "version mismatch — \(reason)"),
                    activationState: .disabled  // never enable a broken asset
                ),
                assetSource: .versionMismatch,
                priorUsage: priorUsage
            )
        case .absent:
            return MigrationReport.Outcome(
                resultingState: .init(assetState: .notDownloaded, activationState: .disabled),
                assetSource: .needsDownload,
                priorUsage: priorUsage
            )
        }
    }
}
