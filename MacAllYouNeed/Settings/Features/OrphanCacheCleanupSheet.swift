import Core
import SwiftUI

/// A one-time launch prompt that appears when `OrphanCacheScanner` finds
/// provider cache directories not declared by any current descriptor.
/// The dismissed set is persisted via `AppGroupSettings` so the prompt does
/// not recur for the same set of orphans.
struct OrphanCacheCleanupSheet: View {
    let orphans: [OrphanCacheScanner.Orphan]
    let onDelete: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Old Voice models found").font(.title3).bold()
            Text("These cached model files are no longer referenced by any installed Voice provider. You can delete them to reclaim disk space.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            MAYNDivider()

            ForEach(orphans, id: \.url.path) { orphan in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(orphan.url.lastPathComponent)
                        Text(formatBytes(orphan.bytes))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }

            MAYNDivider()

            HStack {
                Spacer()
                MAYNButton("Keep", action: onDismiss).keyboardShortcut(.cancelAction)
                MAYNButton("Delete", role: .destructive, action: onDelete)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private func formatBytes(_ b: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: b, countStyle: .file)
    }
}

/// Persisted-dismissal sentinel.
///
/// We store the sorted list of orphan paths the user dismissed so that a
/// brand-new orphan (e.g., from a future provider release) still triggers a
/// prompt. Storing only `Bool` would silence all future orphans permanently.
enum OrphanCacheDismissal {
    static let key = "feature.voice.orphanCachesDismissed.v1"

    static func dismissedSet(in defaults: UserDefaults = AppGroupSettings.defaults) -> Set<String> {
        let array = defaults.stringArray(forKey: key) ?? []
        return Set(array)
    }

    static func markDismissed(_ paths: [String], in defaults: UserDefaults = AppGroupSettings.defaults) {
        let combined = dismissedSet(in: defaults).union(paths)
        defaults.set(Array(combined).sorted(), forKey: key)
    }

    /// Filters an orphan list down to the ones the user has not previously dismissed.
    static func unseen(
        _ orphans: [OrphanCacheScanner.Orphan],
        in defaults: UserDefaults = AppGroupSettings.defaults
    ) -> [OrphanCacheScanner.Orphan] {
        let dismissed = dismissedSet(in: defaults)
        return orphans.filter { !dismissed.contains($0.url.standardizedFileURL.path) }
    }
}
