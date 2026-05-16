import FeatureCore
import SwiftUI

struct FeatureCardActionView: View {
    let descriptor: FeatureDescriptor
    let state: FeatureRuntimeState
    let onInstall: () -> Void
    let onEnable: () -> Void
    let onDisable: () -> Void
    let onUninstall: () -> Void
    let onCancelDownload: () -> Void
    let onRetryInstall: () -> Void

    var body: some View {
        switch (state.assetState, state.activationState) {
        case (.notRequired, .disabled):
            Button("Enable", action: onEnable).buttonStyle(.borderedProminent)
        case (.notRequired, .enabled):
            Toggle("Enabled", isOn: .init(get: { true }, set: { _ in onDisable() }))
                .toggleStyle(.switch)
        case (.notDownloaded, _):
            Button("Install", action: onInstall).buttonStyle(.borderedProminent)
        case (.downloading(let progress), _):
            HStack(spacing: 12) {
                ProgressView(value: progress).frame(maxWidth: 200)
                Button("Cancel", action: onCancelDownload).buttonStyle(.bordered)
            }
        case (.downloadFailed(let reason), _):
            HStack {
                Text(reason).font(.caption).foregroundStyle(.red)
                Button("Retry", action: onRetryInstall).buttonStyle(.borderedProminent)
            }
        case (.present, .disabled):
            HStack {
                Button("Enable", action: onEnable).buttonStyle(.borderedProminent)
                Menu("⋯") {
                    Button("Uninstall…", role: .destructive, action: onUninstall)
                }.menuStyle(.borderlessButton).fixedSize()
            }
        case (.present, .enabled):
            HStack {
                Toggle("Enabled", isOn: .init(get: { true }, set: { _ in onDisable() }))
                    .toggleStyle(.switch)
                Menu("⋯") {
                    Button("Uninstall…", role: .destructive, action: onUninstall)
                }.menuStyle(.borderlessButton).fixedSize()
            }
        }
    }
}
