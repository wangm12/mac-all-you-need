import Core
import SwiftUI

/// Lists applied manifests and offers a one-tap undo for each reversible operation set.
struct OrganizerHistoryView: View {
    let coordinator: FileOrganizerCoordinator?

    @State private var manifests: [Manifest] = []
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            if let error = errorMessage {
                Text(error).foregroundStyle(MAYNTheme.danger).font(.caption).padding(16)
            }
            if manifests.isEmpty {
                Text("No organization history yet.")
                    .foregroundStyle(.secondary)
                    .padding(16)
            } else {
                List(manifests) { manifest in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(manifest.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.callout)
                            Text("\(manifest.operations.count) files · \(manifest.state.rawValue)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if manifest.state == .applied {
                            MAYNButton(role: .secondary) { undo(manifest) } label: { Text("Undo") }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .background(MAYNTheme.window)
        .onAppear(perform: reload)
    }

    private func reload() {
        guard let coordinator else { return }
        do { manifests = try coordinator.history() } catch { errorMessage = error.localizedDescription }
    }

    private func undo(_ manifest: Manifest) {
        guard let coordinator else { return }
        do {
            try coordinator.undo(manifestID: manifest.id)
            reload()
        } catch {
            errorMessage = "Undo failed: \(error.localizedDescription)"
        }
    }
}
