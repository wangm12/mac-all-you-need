import FeatureCore
import Foundation

/// Surface returned by `Migrator.migrateIfNeeded(...)` and consumed by the What's New sheet.
struct MigrationReport: Equatable {
    /// `true` if the migration actually executed in this call (sentinel was unset on entry).
    /// `false` if the sentinel was already set — caller should skip the What's New sheet entirely.
    let didRun: Bool
    /// Per-feature outcome. Empty when `didRun == false`.
    let outcomes: [FeatureID: Outcome]

    struct Outcome: Equatable {
        let resultingState: FeatureRuntimeState
        let assetSource: AssetSource
        let priorUsage: PriorUsageLevel
    }

    enum AssetSource: Equatable {
        /// Pre-install script copied binaries from the old bundle and SHAs match.
        case preInstallScript
        /// Pre-install script copied binaries but per-file SHA didn't match the new manifest.
        /// User will see "Update Downloader" in the What's New sheet.
        case versionMismatch
        /// Feature is Swift-only (no asset pack).
        case notRequired
        /// No binaries on disk; user will see "Install" in the What's New sheet.
        case needsDownload
    }

    static let noop = MigrationReport(didRun: false, outcomes: [:])
}
