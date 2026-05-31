import CoreGraphics
import SwiftUI

struct ScreenRecordingPermissionRow: View {
    let status: PermissionDisplayState
    let isHighlighted: Bool
    let onAction: () -> Void

    var body: some View {
        PermissionCard(
            title: "Screen Recording",
            reason: "Allows Dock Previews to capture live window thumbnails. Without it, the preview panel shows titles only.",
            state: status.cardState,
            actionTitle: "Open",
            isHighlighted: isHighlighted,
            action: onAction
        )
    }
}

