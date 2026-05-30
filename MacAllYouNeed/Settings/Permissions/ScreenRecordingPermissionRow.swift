import CoreGraphics
import SwiftUI

/// Self-contained Screen Recording permission row used by the Dock Previews
/// surfaces. Reflects current authorization and offers a one-tap request.
struct ScreenRecordingPermissionRow: View {
    @State private var isGranted = false

    var body: some View {
        HStack {
            Label("Screen Recording", systemImage: "rectangle.on.rectangle")
            Spacer()
            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(MAYNTheme.success)
                Text("Allowed")
                    .foregroundStyle(MAYNTheme.muted)
            } else {
                MAYNButton("Allow", role: .secondary) {
                    CGRequestScreenCaptureAccess()
                    isGranted = CGPreflightScreenCaptureAccess()
                }
            }
        }
        .task {
            isGranted = CGPreflightScreenCaptureAccess()
        }
    }
}
