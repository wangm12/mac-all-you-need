import Foundation

/// How confident we are that the user actively used a feature on the previous
/// (pre-modular) release. Used by `Migrator` to decide whether to enable or
/// disable the feature post-migration.
enum PriorUsageLevel: Equatable {
    /// State exists in the shared DB (clipboard records, download records, etc.) — strongest signal.
    case directEvidence
    /// Settings tab has at least one non-default persisted value.
    case indirectEvidence
    /// No usage signal at all.
    case none
}
