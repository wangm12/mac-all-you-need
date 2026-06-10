import FeatureCore
import Foundation

struct PermissionUnionEntry: Equatable {
    let permission: Permission
    let featureNames: [String]
}

enum PermissionUnionPlanner {
    static func union(for descriptors: [FeatureDescriptor]) -> [PermissionUnionEntry] {
        var map: [Permission: [String]] = [:]
        for descriptor in descriptors {
            for permission in descriptor.requiredPermissions {
                map[permission, default: []].append(descriptor.displayName)
            }
        }
        return Permission.allCases.compactMap { permission in
            guard let names = map[permission], !names.isEmpty else { return nil }
            return PermissionUnionEntry(permission: permission, featureNames: names)
        }
    }

    static func union(for ids: [FeatureID], registry: FeatureRegistry) -> [PermissionUnionEntry] {
        let descriptors = ids.compactMap { registry.descriptor(for: $0) }
        return union(for: descriptors)
    }

    static func reason(for entry: PermissionUnionEntry) -> String {
        let features = entry.featureNames.joined(separator: ", ")
        switch entry.permission {
        case .accessibility:
            return "Required for \(features) to control windows, paste text, or read UI context."
        case .microphone:
            return "Required for \(features) to capture spoken audio."
        case .screenRecording:
            return "Required for \(features) to show window previews. Nothing is recorded or saved."
        case .fullDiskAccess:
            return "Required for \(features) to access protected files."
        case .notifications:
            return "Optional for \(features) to show completion alerts."
        case .reminders:
            return "Required for \(features) to save tasks to Apple Reminders."
        }
    }
}

extension Permission {
    static let allCases: [Permission] = [
        .accessibility,
        .microphone,
        .screenRecording,
        .fullDiskAccess,
        .notifications,
        .reminders,
    ]
}
