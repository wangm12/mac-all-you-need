import SwiftUI

/// Shown once per panel when thumbnails need Screen Recording (DockDoor `ScreenRecordWarningView` subset).
struct DockPreviewScreenRecordingBanner: View {
    let onRequestAccess: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Screen Recording required for window previews")
                .font(.subheadline.weight(.semibold))
            Text("Dock hover uses static window thumbnails only. Nothing is recorded or sent off your Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Open Screen Recording Settings", action: onRequestAccess)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(12)
        .frame(maxWidth: 320)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }
}
