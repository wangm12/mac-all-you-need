import FeatureCore
import SwiftUI

/// Listed by the Voice settings tab via "Clear cached models…". One row per
/// declared `AssetCacheDescriptor`. Each row has its own delete button so the
/// user can reclaim space without uninstalling the feature.
struct VoiceCacheCleanupSheet: View {
    struct Row: Identifiable, Equatable {
        let id: String
        let displayName: String
        let bytes: Int64
    }

    let descriptor: FeatureDescriptor
    let onClose: () -> Void

    @State private var rows: [Row]
    private let cacheManager = FeatureCacheManager()

    init(descriptor: FeatureDescriptor, onClose: @escaping () -> Void) {
        self.descriptor = descriptor
        self.onClose = onClose
        self._rows = State(initialValue: Self.makeRows(for: descriptor))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Clear cached models").font(.title3).bold()
            Text("Remove downloaded ASR model files. The provider will re-download them the next time you select that model.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            MAYNDivider()

            if rows.isEmpty {
                Text("No model caches declared.").font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(rows) { row in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.displayName)
                            Text(formatBytes(row.bytes))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        MAYNButton("Clear", role: .destructive) {
                            delete(rowID: row.id)
                        }
                        .disabled(row.bytes == 0)
                    }
                    .padding(.vertical, 4)
                }
            }

            MAYNDivider()

            HStack {
                Spacer()
                MAYNButton("Done", action: onClose).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    /// Static so a unit test can build rows without rendering SwiftUI.
    static func makeRows(for descriptor: FeatureDescriptor) -> [Row] {
        descriptor.assetCaches.map { cache in
            Row(id: cache.id, displayName: cache.displayName, bytes: cache.actualBytes())
        }
    }

    /// Static so a unit test can exercise deletion without rendering SwiftUI.
    static func delete(
        cacheID: String,
        in descriptor: FeatureDescriptor,
        cacheManager: FeatureCacheManager
    ) throws {
        try cacheManager.deleteCaches([cacheID], in: descriptor)
    }

    private func delete(rowID: String) {
        do {
            try Self.delete(cacheID: rowID, in: descriptor, cacheManager: cacheManager)
            rows = Self.makeRows(for: descriptor)
        } catch {
            NSLog("VoiceCacheCleanupSheet: delete \(rowID) failed: \(error)")
        }
    }

    private func formatBytes(_ b: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: b, countStyle: .file)
    }
}
