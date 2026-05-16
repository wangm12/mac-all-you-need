import FeatureCore
import SwiftUI

struct FeatureSetupPermissionsView: View {
    let descriptor: FeatureDescriptor
    let onPermissionGranted: (Permission) -> Void
    @State private var liveGranted: [Permission: Bool] = [:]
    private let pollTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        SetupTaskPage(
            symbol: "lock",
            title: "Permissions for \(descriptor.displayName)",
            subtitle: "Grant the permissions \(descriptor.displayName) needs. This step advances automatically once each is granted."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(descriptor.requiredPermissions, id: \.self) { permission in
                    PermissionCard(
                        title: PermissionGateProbe.displayName(for: permission),
                        reason: PermissionGateProbe.reason(for: permission, descriptor: descriptor),
                        state: (liveGranted[permission] ?? PermissionGateProbe.isGranted(permission)) ? .granted : .needed,
                        actionTitle: "Open System Settings"
                    ) {
                        PermissionGateProbe.request(permission) { granted in
                            liveGranted[permission] = granted
                            if !granted { PermissionGateProbe.openSettings(for: permission) }
                            if granted { onPermissionGranted(permission) }
                        }
                    }
                }
            }
        }
        .onAppear {
            for permission in descriptor.requiredPermissions {
                let granted = PermissionGateProbe.isGranted(permission)
                liveGranted[permission] = granted
                if granted { onPermissionGranted(permission) }
            }
        }
        .onReceive(pollTimer) { _ in
            for permission in descriptor.requiredPermissions {
                let now = PermissionGateProbe.isGranted(permission)
                if liveGranted[permission] != now {
                    liveGranted[permission] = now
                    if now { onPermissionGranted(permission) }
                }
            }
        }
    }
}
