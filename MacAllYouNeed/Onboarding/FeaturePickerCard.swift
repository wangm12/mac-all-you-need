import FeatureCore
import SwiftUI

struct FeaturePickerCard: View {
    let descriptor: FeatureDescriptor
    @Binding var isSelected: Bool
    @State private var showsDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: descriptor.icon)
                    .font(.title3)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(descriptor.displayName).font(.headline)
                    Text(descriptor.summary).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Toggle("", isOn: $isSelected)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
            }

            DisclosureGroup(isExpanded: $showsDetail) {
                VStack(alignment: .leading, spacing: 6) {
                    if !descriptor.detailDescription.isEmpty {
                        Text(descriptor.detailDescription).font(.caption)
                    }
                    if !descriptor.requiredPermissions.isEmpty {
                        Text("Permissions: " + descriptor.requiredPermissions
                             .map(PermissionGateProbe.displayName(for:))
                             .joined(separator: ", "))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    if let pack = descriptor.assetPacks.first {
                        Text("Download: \(downloadSizeText(packKey: pack.bundledManifestKey))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 4)
            } label: {
                Text("Learn more").font(.caption)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MAYNTheme.panel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? MAYNTheme.strongBorder : MAYNTheme.subtleBorder, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { isSelected.toggle() }
    }

    /// Resolved at render-time from the bundled FeaturePackManifest.json (Phase 06).
    /// Falls back to "—" if the manifest can't be read (offline dev build, etc.).
    private func downloadSizeText(packKey: String) -> String {
        guard let manifest = try? FeatureManifestLoader.bundled()?.load(),
              let pack = manifest.packs[packKey] else { return "—" }
        return ByteCountFormatter.string(fromByteCount: pack.sizeBytes, countStyle: .file)
    }
}
