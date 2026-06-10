import Core
import FeatureCore
import SwiftUI

struct OnboardingDoneView: View {
    let enabledIDs: [FeatureID]
    var deferredPermissions: Set<Permission> = []
    let onDone: () -> Void
    @AppStorage("launchAtLogin", store: AppGroupSettings.defaults) private var launchAtLogin = true

    var body: some View {
        SetupTaskPage(
            symbol: "checkmark",
            title: "You're all set",
            subtitle: "Selected features are being turned on. Open the Dashboard any time to manage them."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .toggleStyle(.switch)
                    .onChange(of: launchAtLogin) { _, on in
                        LoginItemController.setLaunchAtLogin(on)
                    }

                if enabledIDs.isEmpty {
                    StatusPill(text: "No features enabled yet", kind: .neutral)
                    Text("Open the Dashboard any time to turn features on.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    EnabledFeatureList(ids: enabledIDs)
                }

                if !deferredPermissions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Permissions to finish later")
                            .font(.headline)
                        ForEach(Array(deferredPermissions).sorted(by: { PermissionGateProbe.displayName(for: $0) < PermissionGateProbe.displayName(for: $1) }), id: \.self) { permission in
                            HStack {
                                Image(systemName: "exclamationmark.circle")
                                Text(PermissionGateProbe.displayName(for: permission))
                                Spacer()
                                MAYNButton("Settings") {
                                    PermissionGateProbe.openSettings(for: permission)
                                }
                            }
                            .font(.callout)
                        }
                    }
                }
            }
        }
    }
}

private struct EnabledFeatureList: View {
    let ids: [FeatureID]

    private var displayIDs: [FeatureID] {
        OnboardingFeaturePickerOrdering.featureIDs.filter { ids.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Enabling")
                .font(.headline)
            ForEach(displayIDs, id: \.self) { id in
                if let tile = DashboardToolTilePresentation.primaryTile(for: id) {
                    HStack(spacing: 10) {
                        Image(systemName: tile.symbolName)
                            .frame(width: 18)
                        Text(tile.title)
                        Spacer()
                    }
                    .font(.callout)
                    .padding(.vertical, 2)
                }
            }
        }
    }
}
