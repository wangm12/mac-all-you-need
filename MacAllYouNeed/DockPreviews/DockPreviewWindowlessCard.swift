import SwiftUI

/// Running app with no open windows (DockDoor `WindowlessAppPreview` subset).
struct DockPreviewWindowlessCard: View {
    let onQuit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "app.dashed")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                Text("No open windows")
                    .font(.headline)
                Text("This app is running without visible windows.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Quit App", action: onQuit)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(12)
        .frame(minWidth: 280)
    }
}
