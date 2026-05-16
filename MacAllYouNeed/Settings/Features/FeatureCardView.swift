import FeatureCore
import SwiftUI

struct FeatureCardView: View {
    enum Action {
        case install, enable, disable, uninstall, cancelDownload, retryInstall
    }

    let descriptor: FeatureDescriptor
    let state: FeatureRuntimeState
    let onAction: (Action) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: descriptor.icon).font(.title2)
                Text(descriptor.displayName).font(.headline)
                Spacer()
                statusBadge
            }
            Text(descriptor.summary).font(.subheadline).foregroundStyle(.secondary)
            if !descriptor.requiredPermissions.isEmpty {
                Text(permissionsDescription).font(.caption).foregroundStyle(.tertiary)
            }
            if let usage = diskUsageDescription {
                Text(usage).font(.caption).foregroundStyle(.tertiary)
            }
            if let note = osExtensionNote {
                osExtensionInfoBadge(text: note)
            }
            FeatureCardActionView(
                descriptor: descriptor,
                state: state,
                onInstall: { onAction(.install) },
                onEnable: { onAction(.enable) },
                onDisable: { onAction(.disable) },
                onUninstall: { onAction(.uninstall) },
                onCancelDownload: { onAction(.cancelDownload) },
                onRetryInstall: { onAction(.retryInstall) }
            )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: MAYNControlMetrics.cardRadius, style: .continuous)
                .fill(MAYNTheme.elevated)
        )
    }

    private var statusBadge: some View {
        Group {
            switch (state.assetState, state.activationState) {
            case (_, .enabled):
                Text("Enabled").capsuleBadge(.green.opacity(0.2))
            case (.notDownloaded, _):
                Text("Not installed").capsuleBadge(.gray.opacity(0.2))
            default:
                Text("Disabled").capsuleBadge(.gray.opacity(0.2))
            }
        }
        .font(.caption2)
    }

    private var permissionsDescription: String {
        let names = descriptor.requiredPermissions.map(\.rawValue).joined(separator: ", ")
        return "Permissions: \(names)"
    }

    private var diskUsageDescription: String? {
        guard !descriptor.assetCaches.isEmpty || !descriptor.assetPacks.isEmpty else { return nil }
        let cacheBytes = FeatureCacheManager().totalBytes(for: descriptor)
        let formatted = ByteCountFormatter.string(fromByteCount: cacheBytes, countStyle: .file)
        return "Disk: \(formatted)"
    }

    private var osExtensionNote: String? {
        guard case let .staticBundleExtension(config) = descriptor.osExtensionPolicy,
              config.runsRegardlessOfFeatureState else { return nil }
        return "The Quick Look extension stays installed with the app. " +
               "Disabling here hides it from previews; full removal requires uninstalling Mac All You Need."
    }

    @ViewBuilder
    private func osExtensionInfoBadge(text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
                .font(.caption)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.secondary.opacity(0.08)))
    }
}

private extension Text {
    func capsuleBadge(_ fill: Color) -> some View {
        self.padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(fill))
    }
}
