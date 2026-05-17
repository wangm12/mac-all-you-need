import FeatureCore
import SwiftUI

/// Popover body shown when the user chooses "About <Feature>…" from the
/// context menu on a `FeatureToolCard`.
///
/// Three optional sections are shown:
/// - **Disk Usage** — present when the feature declares asset caches or packs.
/// - **Permissions** — present when the feature requires TCC permissions.
/// - **System Extension** — present when the bundled OS extension runs
///   regardless of the feature's enabled state.
///
/// If none of the three sections have content to display, a fallback
/// "No additional information." message is shown instead.
struct FeatureAboutContent: View {
    let descriptor: FeatureDescriptor
    let state: FeatureRuntimeState

    var body: some View {
        let hasDiskSection = !descriptor.assetCaches.isEmpty || !descriptor.assetPacks.isEmpty
        let hasPermissionsSection = !descriptor.requiredPermissions.isEmpty
        let hasExtensionSection: Bool = {
            if case .staticBundleExtension(let config) = descriptor.osExtensionPolicy,
               config.runsRegardlessOfFeatureState { return true }
            return false
        }()

        if hasDiskSection || hasPermissionsSection || hasExtensionSection {
            VStack(alignment: .leading, spacing: 16) {
                if hasDiskSection {
                    diskSection
                }
                if hasPermissionsSection {
                    permissionsSection
                }
                if hasExtensionSection {
                    extensionSection
                }
            }
        } else {
            Text("No additional information.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    // MARK: Disk Usage

    private var diskSection: some View {
        MAYNSection(title: "Disk Usage") {
            let bytes = FeatureCacheManager().totalBytes(for: descriptor)
            let formatted = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
            MAYNSettingsRow(title: "Storage") {
                Text(formatted)
                    .foregroundStyle(.secondary)
            }
            if case .present(let version) = state.assetState {
                MAYNDivider()
                MAYNSettingsRow(title: "Version") {
                    Text(version)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Permissions

    private var permissionsSection: some View {
        MAYNSection(title: "Permissions") {
            ForEach(descriptor.requiredPermissions, id: \.self) { permission in
                if permission != descriptor.requiredPermissions.first {
                    MAYNDivider()
                }
                MAYNSettingsRow(title: permissionLabel(permission)) {
                    EmptyView()
                }
            }
        }
    }

    private func permissionLabel(_ permission: Permission) -> String {
        switch permission {
        case .accessibility: return "Accessibility"
        case .fullDiskAccess: return "Full Disk Access"
        case .microphone: return "Microphone"
        case .notifications: return "Notifications"
        }
    }

    // MARK: System Extension

    private var extensionSection: some View {
        MAYNSection(title: "System Extension") {
            Text(
                "The Quick Look extension is bundled with the app and stays installed. " +
                "Disabling this feature hides previews; full removal requires uninstalling Mac All You Need."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }
}
