import AppKit
import Core
import FeatureCore
import SwiftUI

struct UnifiedPermissionsView: View {
    let registry: FeatureRegistry
    let selectedIDs: [FeatureID]
    @Binding var deferredPermissions: Set<Permission>
    @State private var liveGranted: [Permission: Bool] = [:]
    @State private var expandedInstructions: Set<Permission> = []
    private let pollTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var entries: [PermissionUnionEntry] {
        PermissionUnionPlanner.union(for: selectedIDs, registry: registry)
    }

    var body: some View {
        SetupTaskPage(
            symbol: "lock.shield",
            title: "Permissions required",
            subtitle: "Grant the capabilities this app may need as you enable features. Choose Later for any you want to defer — you can finish them in System Settings."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                if entries.isEmpty {
                    StatusPill(text: "No system permissions needed for your selection", kind: .neutral)
                } else {
                    ForEach(entries, id: \.permission) { entry in
                        permissionBlock(for: entry)
                    }
                }

                LoginItemOnboardingCard()
                Text("You can defer any permission and finish it later in System Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            refreshGrantedState()
            Task { await PermissionGateProbe.refreshNotificationStatus() }
        }
        .onDisappear {
            PermissionGrantPresenter.dismissFloatingPanel()
        }
        .onReceive(pollTimer) { _ in
            refreshGrantedState()
        }
    }

    @ViewBuilder
    private func permissionBlock(for entry: PermissionUnionEntry) -> some View {
        let permission = entry.permission
        let granted = liveGranted[permission] ?? PermissionGateProbe.isGranted(permission)
        let deferred = deferredPermissions.contains(permission)
        VStack(alignment: .leading, spacing: 10) {
            PermissionCard(
                title: PermissionGateProbe.displayName(for: permission),
                reason: PermissionUnionPlanner.reason(for: entry),
                state: granted ? .granted : (deferred ? .optional : .needed),
                actionTitle: "Grant"
            ) {
                grant(permission)
            }
            if !granted {
                HStack(spacing: 8) {
                    MAYNButton("Later in Settings") {
                        deferredPermissions.insert(permission)
                        DeferredPermissionsStore.markDeferred(permission)
                    }
                }
            }
            if expandedInstructions.contains(permission), !granted {
                instructionStrip(for: permission)
            }
        }
    }

    private func grant(_ permission: Permission) {
        expandedInstructions.insert(permission)
        PermissionGateProbe.request(permission) { nowGranted in
            liveGranted[permission] = nowGranted
            if nowGranted {
                deferredPermissions.remove(permission)
                PermissionGrantPresenter.dismissFloatingPanel()
            } else {
                PermissionGrantPresenter.presentGrant(
                    for: permission,
                    sourceWindow: NSApp.keyWindow
                ) {
                    PermissionGateProbe.openSettings(for: permission)
                }
            }
        }
    }

    @ViewBuilder
    private func instructionStrip(for permission: Permission) -> some View {
        let inline = PermissionGrantPresenter.inlineInstruction(for: permission)
        InstructionStrip(
            text: inline.primaryText,
            appName: "Mac All You Need",
            symbol: inline.symbol,
            secondaryText: inline.secondaryText,
            dragAppURL: inline.dragAppURL,
            actionTitle: "Open Settings"
        ) {
            PermissionGateProbe.openSettings(for: permission)
        }
    }

    private func refreshGrantedState() {
        for entry in entries {
            let permission = entry.permission
            let wasGranted = liveGranted[permission] ?? false
            let now = permission == .notifications
                ? PermissionGateProbe.cachedNotificationGranted
                : PermissionGateProbe.isGranted(permission)
            liveGranted[permission] = now
            if now {
                deferredPermissions.remove(permission)
                if !wasGranted {
                    PermissionGrantPresenter.dismissFloatingPanel()
                }
            }
        }
    }
}

private struct LoginItemOnboardingCard: View {
    @AppStorage("launchAtLogin", store: AppGroupSettings.defaults) private var launchAtLogin = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Background clipboard capture")
                .font(.headline)
            Text("The Clipboard helper runs at login so copies are saved even when Mac All You Need is quit.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Toggle("Launch at login", isOn: $launchAtLogin)
                .toggleStyle(.switch)
                .onChange(of: launchAtLogin) { _, on in
                    LoginItemController.setLaunchAtLogin(on)
                }
        }
        .padding(14)
        .background(MAYNTheme.panel, in: RoundedRectangle(cornerRadius: MAYNControlMetrics.panelRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MAYNControlMetrics.panelRadius, style: .continuous)
                .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
        )
    }
}
