import FeatureCore
import SwiftUI

struct UninstallConfirmationSheet: View {
    let descriptor: FeatureDescriptor
    @State private var sheetState: UninstallSheetState
    let onCancel: () -> Void
    let onConfirm: (UninstallSheetState) -> Void

    init(
        descriptor: FeatureDescriptor,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping (UninstallSheetState) -> Void
    ) {
        self.descriptor = descriptor
        self._sheetState = State(initialValue: UninstallSheetState.from(descriptor: descriptor))
        self.onCancel = onCancel
        self.onConfirm = onConfirm
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Uninstall \(descriptor.displayName)?").font(.title3).bold()
            Text("Pack files will be removed.").font(.subheadline).foregroundStyle(.secondary)

            if !sheetState.cacheRows.isEmpty {
                MAYNDivider()
                Text("Optional: also remove cached data").font(.caption).foregroundStyle(.secondary)
                ForEach(sheetState.cacheRows) { row in
                    Toggle(isOn: .init(
                        get: { row.checked },
                        set: { _ in sheetState.toggle(cacheID: row.id) }
                    )) {
                        VStack(alignment: .leading) {
                            Text(row.displayName)
                            Text(formatBytes(row.bytes)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            MAYNDivider()
            Text("User documents (downloaded video files, exported items) are always preserved.")
                .font(.caption).foregroundStyle(.tertiary)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Uninstall", role: .destructive) { onConfirm(sheetState) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 460)
    }

    private func formatBytes(_ b: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: b, countStyle: .file)
    }
}
