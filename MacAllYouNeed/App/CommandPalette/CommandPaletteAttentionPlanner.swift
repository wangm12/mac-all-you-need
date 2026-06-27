import FeatureCore
import Foundation

struct CommandPaletteAttentionSnapshot: Equatable {
    let failedDownloadCount: Int
    let orphanCacheCount: Int
    let missingPermissions: [Permission]
    let permissionsAttentionTitle: String?
    let voiceSetupNeeded: Bool

    var hasItems: Bool {
        failedDownloadCount > 0
            || orphanCacheCount > 0
            || !missingPermissions.isEmpty
            || voiceSetupNeeded
    }

    var badgeTitle: String? {
        if voiceSetupNeeded {
            return "Complete Voice setup"
        }
        if let permissionsAttentionTitle {
            return permissionsAttentionTitle
        }
        if failedDownloadCount > 0 {
            return "Review \(failedDownloadCount) downloads"
        }
        if orphanCacheCount > 0 {
            return "Review \(orphanCacheCount) orphan caches"
        }
        return nil
    }
}

@MainActor
enum CommandPaletteAttentionPlanner {
    static func snapshot(
        registry: FeatureRegistry,
        stateFor: (FeatureID) -> FeatureRuntimeState,
        failedDownloadCount: Int,
        orphanCacheCount: Int
    ) -> CommandPaletteAttentionSnapshot {
        let missing = missingPermissions(registry: registry, stateFor: stateFor)
        let permissionsTitle: String? = {
            guard !missing.isEmpty else { return nil }
            if missing.count == 1, let permission = missing.first {
                return "Grant \(PermissionGateProbe.displayName(for: permission))"
            }
            return "Review \(missing.count) permissions"
        }()
        return CommandPaletteAttentionSnapshot(
            failedDownloadCount: failedDownloadCount,
            orphanCacheCount: orphanCacheCount,
            missingPermissions: missing,
            permissionsAttentionTitle: permissionsTitle,
            voiceSetupNeeded: voiceSetupNeeded(stateFor: stateFor)
        )
    }

    private static func missingPermissions(
        registry: FeatureRegistry,
        stateFor: (FeatureID) -> FeatureRuntimeState
    ) -> [Permission] {
        var required = Set<Permission>()
        for descriptor in registry.descriptors {
            guard stateFor(descriptor.id).activationState == .enabled else { continue }
            descriptor.requiredPermissions.forEach { required.insert($0) }
        }
        return required.sorted { lhs, rhs in
            PermissionGateProbe.displayName(for: lhs) < PermissionGateProbe.displayName(for: rhs)
        }.filter { !PermissionGateProbe.isGranted($0) }
    }

    private static func voiceSetupNeeded(stateFor: (FeatureID) -> FeatureRuntimeState) -> Bool {
        guard stateFor(.voice).activationState == .enabled else { return false }
        return !PermissionGateProbe.isGranted(.microphone)
            || !PermissionGateProbe.isGranted(.accessibility)
    }
}
